#!/bin/bash

# Constants

privateKey=requester
publicKey=$(echo '0x41a60f71063cd7c9e5247d3e7d551f91f94b5c3b' | tr '[:upper:]' '[:lower:]')

PUBLIC_METADATA_FILE='0x8000000000000000000000000000000000000001'
REGISTRY_CONTRACT='0x9B0E06b0Ceb584C1f5B46b18d6eDEC09d5BC073E'


# Options

verbose=''

usage() { 
  echo "Usage:"
  echo "  $(basename $0) buy <book-id>"
  echo "  $(basename $0) discover [author-id]"
  echo "  $(basename $0) library"
  echo "  $(basename $0) listen"
  exit 1; 
}

while getopts "vh" flag; do
    case "${flag}" in
        v) verbose='-v' ;;
        h) usage ;;
        *) usage ;;
    esac
done
shift $((OPTIND-1))


# Commands

run() {
  case $1 in
    discover) discover $2 ;;
    buy) buy $2 ;;
    library) library $2 ;;
    listen) listen $2 ;;
    *) usage ;;
  esac
}

discover() {
  authorIdParam=$1
  format=$2
  filter=''
  if [ ! -z $authorIdParam ]
  then 
    assertAddress $authorIdParam 1 "parameter is not an account address"
    filter='{"author": "'${authorIdParam}'"}';
    trace "querying on-chain registry for author id ${authorIdParam} using filter ${filter}"
  else
    trace "querying on-chain registry for all audiobooks"
  fi
  events=$(bubble contract events -f $(dirname $0)/../contracts/artifacts/AudiobookRegistry.json ${REGISTRY_CONTRACT} Register "${filter}")
  assertZero $? 4 "failed to query on-chain registry"
  bubbles=$( jq -r '.[].bubbleContract' <<< "[${events}]" | uniq)
  bubbleArr=( $bubbles )
  numBubbles=${#bubbleArr[@]}
  trace "${numBubbles} audiobooks found"
  authorId=$authorIdParam
  count=0
  for b in $bubbles
  do
    ((count++))
    if [ -z $authorIdParam ]
    then
      trace "getting owner of bubble contract ${b}"
      authorId=$(bubble contract call -f $(dirname $0)/../contracts/artifacts/AudiobookSDAC.json $b owner)
      assertZero $? 3 "failed to query owner from bubble contract ${b}"
    fi
    trace "reading metadata from bubble at ${b}"
    metadata=$(bubble vault read --key ${privateKey} bubble ${b} $PUBLIC_METADATA_FILE)
    assertZero $? 3 "failed to read metadata from bubble"
    author=\"$(jq -r '.author' <<< ${metadata})\"
    title=\"$(jq -r '.title' <<< ${metadata})\"
    case "${format}" in
      json) 
        separator=','
        if [ $count -eq $numBubbles ]; then separator=''; fi
        echo '{"id": "'${b}'", "author-id": "'${authorId}'", "author": '${author}', "title": '${title}'}'${separator} ;;
      *) echo "id: ${b}, author-id: ${authorId}, author: ${author}, title: ${title}" ;;
    esac
  done
}

buy() {
  id=$1
  assertNotEmpty "${id}" 1 "missing book-id parameter"
  trace "getting nft contract address from bubble contract"
  nftContract=$(bubble contract call -f $(dirname $0)/../contracts/artifacts/AudiobookSDAC.json ${id} nftContract)
  assertZero $? 2 "failed to query bubble contract for the nft contract address" "${nftContract}"
  assertAddress "${nftContract}" 1 "failed to query bubble contract for the nft contract address - returned contract is invalid: '${nftContract}'"
  trace "getting price from nft contract ${nftContract}"
  price=$(bubble contract call -f $(dirname $0)/../contracts/artifacts/AudiobookNFT.json ${nftContract} price)
  assertZero $? 2 "failed to query nft contract for the price" "${price}"
  read -p "Price is ${price} WEI, do you want to continue? y/n " approval
  if [ "$approval" == 'y' ]
  then
    trace "minting token from nft contract ${nftContract}"
    tokenId=$(bubble contract transact --key ${privateKey} -f $(dirname $0)/../contracts/artifacts/AudiobookNFT.json -o '{"value": '${price}'}' ${nftContract} mintToken)
    assertZero $? 2 "failed to query nft contract for the price" "${tokenId}"
    echo "Purchase Successful.  Your purchase and token ID will appear in your library after the transaction has been mined."
  fi
}

library() {
  trace "getting all titles"
  oldVerbose=$verbose
  verbose=''
  allBooks=$(discover '' 'json')
  verbose=$oldVerbose
  bubbles=$( jq -r '.[].id' <<< "[${allBooks}]")
  bubbleArr=( $bubbles )
  numBubbles=${#bubbleArr[@]}
  trace "checking ${numBubbles} titles for token ids you own"
  filter='[{"to": "'${publicKey}'"}, {"from": "'${publicKey}'"}]'
  for b in $bubbles
  do
    nftContract=$(bubble contract call -f $(dirname $0)/../contracts/artifacts/AudiobookSDAC.json ${b} nftContract)
    assertZero $? 2 "failed to query bubble contract ${b} for the nft contract address"
    assertAddress "${nftContract}" 1 "failed to query bubble ${b} contract for the nft contract address - returned contract is invalid: '${nftContract}'"
    events=$(bubble contract events -f $(dirname $0)/../contracts/artifacts/AudiobookNFT.json ${nftContract} Transfer "${filter}")
    assertZero $? 4 "failed to query on-chain registry"
    tokens=''
    for e in $events
    do
      e=$(sed 's/,$//' <<< "${e}")
      from=$(jq -r '.from' <<< "${e}" | tr '[:upper:]' '[:lower:]')
      to=$(jq -r '.to' <<< "${e}" | tr '[:upper:]' '[:lower:]')
      tokenId=$(jq -r '.tokenId' <<< "${e}")
      if [ "${to}" == $publicKey ]; then tokens="${tokens} ${tokenId}"; fi
      if [ "${from}" == $publicKey ]; then tokens=${tokens//${tokenId}/}; fi
    done
    for t in $tokens
    do
      echo "book: ${b}, token: ${t}"
    done
  done
}

listen() {
  id=$1
  assertNotEmpty "${id}" 1 "missing book-id parameter"
  trace "reading metadata from bubble at ${1}"
  metadata=$(bubble vault read --key ${privateKey} bubble ${1} $PUBLIC_METADATA_FILE)
  assertZero $? 3 "failed to read metadata from bubble"
  author=\"$(jq -r '.author' <<< ${metadata})\"
  title=\"$(jq -r '.title' <<< ${metadata})\"
  audiofile=$(jq -r '.bubble.audio' <<< ${metadata})
  assertNotNull "${audiofile}" 2 "metadata is invalid: audio file is missing"
  filetype=${audiofile##*.}
  if [ -z $filetype ]; then filetype='download'; fi
  target="${1}.${filetype}"
  trace "downloading ${audiofile} from bubble at ${1}"
  bubble vault read --binary $target --key ${privateKey} bubble $1 $audiofile
  assertZero $? 2 "failed to download audio file"
  echo "Successfully downloaded audiobook to ${target}"
}

assertZero() {
  if [ $1 -ne 0 ]; then error $2 "${3}" "${4}"; fi
}

assertNotEmpty() {
  if [ -z "$1" ]; then error $2 "${3}" "${4}"; fi
}

assertNotNull() {
  if [ -z "$1" -o "$1" == "null" ]; then error $2 "${3}" "${4}"; fi
}

assertFileExists() {
  if [ ! -f $1 ]; then error $2 "${3}" "${4}"; fi
}

assertAddress() {
  if [[ ! "$1" =~ ^0x[0-9a-fA-F]{40}$ ]]; then error $2 "${3}" "${4}"; fi
}

error() {
  if [ ! -z "$3" ]; then echo $3; fi
  echo $2
  exit $1
}

trace() {
  if [ ! -z $verbose ]; then echo "[trace] ${@}"; fi
}


# go
run $@
