#!/bin/bash

# Constants

privateKey=owner
publicKey='0xc16a409a39ede3f38e212900f8d3afe6aa6a8929'

PUBLIC_METADATA_FILE='0x8000000000000000000000000000000000000001'
REGISTRY_CONTRACT='0x9B0E06b0Ceb584C1f5B46b18d6eDEC09d5BC073E'


# Options

verbose=''

usage() { 
  echo "Usage:"
  echo "  $0 create <metadata-file> <audio-file> [book-image] [author-image]"
  echo "  $0 bibliography"
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
    create) createAudiobook $2 $3 $4 $5 ;;
    bibliography) showBibliography ;;
    *) usage ;;
  esac
}

createAudiobook() {
  trace "createAudiobook '${1}' '${2}'"
  assertNotEmpty "$1" 1 "metadata file parameter is missing"
  assertFileExists "$1" 1 "metadata file does not exist"
  assertNotEmpty "$2" 1 "audio file parameter is missing"
  assertFileExists "$2" 1 "audio file does not exist"

  metadata=$(<$1)
  nftTitle=$( jq -r '.nft.title' <<< "${metadata}")
  assertZero $? 1 "metadata is invalid"
  nftSymbol=$( jq -r '.nft.symbol' <<< "${metadata}")
  audio=$( jq -r '.bubble.audio' <<< "${metadata}")
  bookImage=$( jq -r '.bubble.image' <<< "${metadata}")
  authorImage=$( jq -r '.bubble."author-image"' <<< "${metadata}")
  assertNotNull "${nftTitle}" 1 "metadata is invalid: nft.title is missing"
  assertNotNull "${nftSymbol}" 1 "metadata is invalid: nft.symbol is missing"
  assertNotNull "${audio}" 1 "metadata is invalid: bubble.audio is missing"
  assertNotNull "${bookImage}" 1 "metadata is invalid: bubble.image is missing"
  assertNotNull "${authorImage}" 1 "metadata is invalid: bubble.author-image is missing"

  trace "Deploying nft contract with args '${nftTitle}' ${nftSymbol}"
  #nftContract=$(bubble contract deploy --key ${privateKey} -f $(dirname $0)/../contracts/artifacts/AudiobookNFT.json "${nftTitle}" "${nftSymbol}")
  #echo "NFT Contract: ${nftContract}" >> contracts.log
  nftContract="0xBaEbfC8781906Be65659EF5FdA5B59B24358D4e2"
  assertZero $? 2 "failed to deploy nft contract" "${nftContract}"
  assertAddress "${nftContract}" 1 "failed to deploy nft contract - contract is invalid: '${nftContract}'"
  echo "Successfully deployed NFT Contract: ${nftContract}"

  trace "Deploying bubble contract"
  #bubbleContract=$(bubble contract deploy --key ${privateKey} -f $(dirname $0)/../contracts/artifacts/AudiobookSDAC.json "${nftContract}")
  #echo "Bubble Contract: ${bubbleContract}" >> contracts.log
  bubbleContract="0x7A3bF9f9557b7c9BE95aF3D97bEc58e9809C03EA"
  assertZero $? 2 "failed to deploy bubble contract"
  assertAddress "${bubbleContract}" 1 "failed to deploy nft contract - contract is invalid: '${bubbleContract}'"
  echo "Successfully deployed Bubble Contract: ${bubbleContract}"

  trace "Creating bubble"
  #bubble vault create ${verbose} --key ${privateKey} bubble $bubbleContract
  assertZero $? 2 "failed to create bubble"
  echo "Successfully created bubble"
  
  #writeMetadata $bubbleContract $1
  assertZero $? 3 "failed to write metadata to bubble"
  echo "Successfully wrote metadata"

  #writeFile 'bin' "audio" $bubbleContract "${audio}" $2 
  assertZero $? 3 "failed to write audio file to bubble"
  echo "Successfully wrote audio"

  if [ ! -z $3 ]; then 
    #writeFile 'bin' "book image" $bubbleContract "${bookImage}" $3
    assertZero $? 3 "failed to write image to bubble"
    echo "Successfully wrote image"
  fi

  if [ ! -z $4 ]; then 
    #writeFile 'bin' "author image" $bubbleContract "${authorImage}" $4
    assertZero $? 3 "failed to write author image to bubble"
    echo "Successfully wrote author image"
  fi

  trace "Registering book launch with on-chain Audiobook Registry"
  trace `bubble contract transact --key ${privateKey} -f $(dirname $0)/../contracts/artifacts/AudiobookRegistry.json ${REGISTRY_CONTRACT} register ${bubbleContract}`
  assertZero $? 4 "failed to register book launch with on-chain registry"
  echo "Successfully registered book launch with on-chain Audiobook Registry"
}

showBibliography() {
  events=$(node ../../bubble-tools/src/cli.mjs contract events -f $(dirname $0)/../contracts/artifacts/AudiobookRegistry.json ${REGISTRY_CONTRACT} Register '{"author": "'${publicKey}'"}')
  assertZero $? 4 "failed to query bibliography from on-chain registry"
  bubbles=$( jq -r '.[].bubbleContract' <<< "[${events}]" | uniq)
  for b in $bubbles
  do
    trace "reading metadata from bubble at ${b}"
    metadata=$(bubble vault read --key ${privateKey} bubble ${b} $PUBLIC_METADATA_FILE)
    echo "id: ${b}, title: \"$(jq -r '.title' <<< ${metadata})\""
  done
}

writeMetadata() {
  writeFile 'utf8' metadata $1 $PUBLIC_METADATA_FILE $2
  return $?
}

writeFile() {
  binaryOption=''
  if [ "$1" == 'bin' ]; then binaryOption='-b'; fi
  type=$2
  contract=$3
  filename=$4
  inputfile=$5
  assertNotEmpty "${contract}" 1 "contract is missing"
  assertNotEmpty "${inputfile}" 1 "${type} is missing"
  assertFileExists "${inputfile}" 1 "${type} file '${inputfile}' does not exist"
  trace "Writing ${type} (${inputfile}) to bubble ${contract} file ${filename}"
  bubble vault write ${verbose} ${binaryOption} --key ${privateKey} bubble ${contract} "${filename}" "${inputfile}"
  return $?
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
