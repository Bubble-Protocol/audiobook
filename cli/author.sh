#!/bin/bash

# Constants

privateKey=author  # override with -k option

PUBLIC_METADATA_FILE='0x8000000000000000000000000000000000000000000000000000000000000001'
REGISTRY_CONTRACT='0xeac5f76BEeD5e94458836690640dD250E816242F'


# Options

verbose=''

usage() { 
  echo "Usage:"
  echo "  $(basename $0) bibliography"
  echo "  $(basename $0) balance <book-id>"
  echo "  $(basename $0) publish <metadata-file> <audio-file> [book-image] [author-image]"
  echo "  $(basename $0) setPrice <book-id> <price>"
  echo "  $(basename $0) update <book-id> <filetype> <file>"
  echo "  $(basename $0) withdraw <book-id> <amount>"
  echo
  echo "Options:"
  echo "  -k <private-key>   use the given private key or bubble tools label"
  echo "  -p   gas price (overrides recommended price)"
  echo "  -h   display this help"
  echo "  -v   verbose"
  echo
  echo "Default key: ${privateKey}"
  exit 1; 
}


# Commands

run() {

  while getopts "vhk:" flag; do
    case "${flag}" in
      h) usage ;;
      k) 
        privateKey=$OPTARG;
        assertNotEmpty "${privateKey}" 1 "private key is missing"
        ;;
      p)
        gasPrice="-p ${OPTARG}"
        assertNotEmpty "${OPTARG}" 1 "gas price is missing"
        ;;
      v) verbose='-v' ;;
      *) usage ;;
    esac
  done
  shift $((OPTIND-1))

  publicKey=$(bubble wallet info ${privateKey} 2>/dev/null)
  assertZero $? 1 "invalid private key"

  case $1 in
    publish) publish $2 $3 $4 $5 ;;
    bibliography) displayBibliography ;;
    update) update $2 $3 $4 ;;
    setPrice) setPrice $2 $3 ;;
    balance) balance $2 ;;
    withdraw) withdraw $2 $3 ;;
    *) usage ;;
  esac
}

publish() {
  trace "createAudiobook '${1}' '${2}'"
  trace "using private key '${privateKey}'"
  assertNotEmpty "$1" 1 "metadata file parameter is missing"
  assertFileExists "$1" 1 "metadata file does not exist"
  assertNotEmpty "$2" 1 "audio file parameter is missing"
  assertFileExists "$2" 1 "audio file does not exist"
  assertOptionalFileExists "$3" 1 "book image file does not exist"
  assertOptionalFileExists "$4" 1 "author image file does not exist"

  metadata=$(<$1)
  nftTitle=$( jq -r '.nft.title' <<< "${metadata}")
  assertZero $? 1 "metadata is invalid"
  nftSymbol=$( jq -r '.nft.symbol' <<< "${metadata}")
  price=$( jq -r '.nft.price' <<< "${metadata}")
  audio=$( jq -r '.bubble.audio' <<< "${metadata}")
  bookImage=$( jq -r '.bubble.image' <<< "${metadata}")
  authorImage=$( jq -r '.bubble."author-image"' <<< "${metadata}")
  assertNotNull "${nftTitle}" 1 "metadata is invalid: nft.title is missing"
  assertNotNull "${nftSymbol}" 1 "metadata is invalid: nft.symbol is missing"
  assertNotNull "${price}" 1 "metadata is invalid: nft.price is missing"
  assertNotNull "${audio}" 1 "metadata is invalid: bubble.audio is missing"
  assertNotNull "${bookImage}" 1 "metadata is invalid: bubble.image is missing"
  assertNotNull "${authorImage}" 1 "metadata is invalid: bubble.author-image is missing"

  trace "Deploying nft contract with args ('${nftTitle}', '${nftSymbol}', ${price})"
  nftContract=$(bubble contract deploy --key ${privateKey} ${gasPrice} -f $(dirname $0)/../contracts/artifacts/AudiobookNFT.json "${nftTitle}" "${nftSymbol}" "${price}")
  echo "NFT Contract: ${nftContract}" >> contracts.log
  assertZero $? 2 "failed to deploy nft contract" "${nftContract}"
  assertAddress "${nftContract}" 1 "failed to deploy nft contract - contract address is invalid: '${nftContract}'"
  echo "Successfully deployed NFT Contract: ${nftContract}"

  trace "Deploying bubble contract"
  bubbleContract=$(bubble contract deploy --key ${privateKey} ${gasPrice} -f $(dirname $0)/../contracts/artifacts/AudiobookACC.json "${nftContract}")
  echo "Bubble Contract: ${bubbleContract}" >> contracts.log
  assertZero $? 2 "failed to deploy bubble contract"
  assertAddress "${bubbleContract}" 1 "failed to deploy nft contract - contract is invalid: '${bubbleContract}'"
  echo "Successfully deployed Bubble Contract: ${bubbleContract}"

  trace "Creating bubble"
  bubble content create-bubble ${verbose} --key ${privateKey} bubble-base $bubbleContract
  assertZero $? 2 "failed to create bubble"
  echo "Successfully created bubble"
  
  writeMetadata $bubbleContract $1
  assertZero $? 3 "failed to write metadata to bubble"
  echo "Successfully wrote metadata"

  writeFile 'bin' "audio" $bubbleContract "${audio}" $2 
  assertZero $? 3 "failed to write audio file to bubble"
  echo "Successfully wrote audio"

  if [ ! -z $3 ]; then 
    writeFile 'bin' "book image" $bubbleContract "${bookImage}" $3
    assertZero $? 3 "failed to write image to bubble"
    echo "Successfully wrote image"
  fi

  if [ ! -z $4 ]; then 
    writeFile 'bin' "author image" $bubbleContract "${authorImage}" $4
    assertZero $? 3 "failed to write author image to bubble"
    echo "Successfully wrote author image"
  fi

  trace "Registering book launch with on-chain Audiobook Registry"
  receipt=$(bubble contract transact --key ${privateKey} ${gasPrice} -f $(dirname $0)/../contracts/artifacts/AudiobookRegistry.json ${REGISTRY_CONTRACT} register ${bubbleContract})
  assertZero $? 4 "failed to register book launch with on-chain registry" "${receipt}"
  echo "Successfully registered book launch with on-chain Audiobook Registry"
  echo "Your unique book id is: ${bubbleContract}"
}

displayBibliography() {
  trace "getting events for account ${publicKey} from AudiobookRegistry contract ${REGISTRY_CONTRACT}"
  events=$(bubble contract events -f $(dirname $0)/../contracts/artifacts/AudiobookRegistry.json ${REGISTRY_CONTRACT} Register '{"author": "'${publicKey}'"}')
  assertZero $? 4 "failed to query bibliography from on-chain registry"
  bubbles=$( jq -r '.[].bubbleContract' <<< "[${events}]" | uniq)
  for b in $bubbles
  do
    trace "reading metadata from bubble at ${b}"
    metadata=$(bubble content read --key ${privateKey} bubble-base ${b} $PUBLIC_METADATA_FILE)
    echo "id: ${b}, title: \"$(jq -r '.title' <<< ${metadata})\""
  done
}

update() {
  id=$1
  type=$2
  file=$3
  assertNotEmpty "${id}" 1 "id parameter is missing"
  assertNotEmpty "${type}" 1 "content type parameter is missing"
  assertNotEmpty "${file}" 1 "file parameter is missing"
  trace "updating ${type} for book ${id} from file ${file}"
  trace "using private key '${privateKey}'"
  if [ $type == 'metadata' ]
  then
    writeMetadata $id $file
    assertZero $? 3 "failed to write metadata to bubble"
    echo "Successfully wrote ${type} (${file}) to bubble ${id} file ${PUBLIC_METADATA_FILE}"
  else
    trace "reading metadata from bubble at ${id}"
    metadata=$(bubble content read --key ${privateKey} bubble-base ${id} $PUBLIC_METADATA_FILE)
    assertZero $? 3 "failed to read metadata from bubble"
    filename=$( jq -r '.bubble."'${type}'"' <<< "${metadata}")
    assertNotNull "$filename" 1 "type parameter is invalid"
    writeFile 'bin' $type $id "${filename}" $file
    assertZero $? 3 "failed to write ${type} to bubble"
    echo "Successfully wrote ${type} (${file}) to bubble ${id} file ${filename}"
  fi
}

setPrice() {
  id=$1
  price=$2
  assertNotEmpty "${id}" 1 "id parameter is missing"
  assertNotEmpty "${price}" 1 "price parameter is missing"
  trace "setting price of book ${id} to ${price}"
  trace "using private key '${privateKey}'"
  trace "getting nft contract address from bubble contract"
  nftContract=$(bubble contract call -f $(dirname $0)/../contracts/artifacts/AudiobookACC.json ${id} nftContract)
  assertZero $? 2 "failed to query bubble contract for the nft contract address"
  assertAddress "${nftContract}" 1 "failed to query bubble contract for the nft contract address - returned contract is invalid: '${nftContract}'"
  trace "setting price on nft contract ${nftContract}"
  receipt=$(bubble contract transact --key ${privateKey} ${gasPrice} -f $(dirname $0)/../contracts/artifacts/AudiobookNFT.json ${nftContract} setPrice ${price})
  assertZero $? 2 "failed to set price on nft contract" "${receipt}"
  echo "Successfully set price of ${price} on nft contract ${nftContract} for audiobook id ${id}"
}

balance() {
  id=$1
  assertNotEmpty "${id}" 1 "id parameter is missing"
  trace "getting balance in WEI for book ${id}"
  trace "getting nft contract address from bubble contract"
  nftContract=$(bubble contract call -f $(dirname $0)/../contracts/artifacts/AudiobookACC.json ${id} nftContract)
  assertZero $? 2 "failed to query bubble contract for the nft contract address"
  assertAddress "${nftContract}" 1 "failed to query bubble contract for the nft contract address - returned contract is invalid: '${nftContract}'"
  trace "getting balance of nft contract ${nftContract}"
  ethBalance=$(bubble wallet balance ${nftContract})
  echo "${ethBalance}*1000000000000000000" | bc | sed 's/\.0*$//'
}

withdraw() {
  id=$1
  amount=$2
  assertNotEmpty "${id}" 1 "id parameter is missing"
  assertNotEmpty "${amount}" 1 "amount parameter is missing"
  trace "withdrawing ${amount} WEI from the nft contract of book ${id}"
  trace "using private key '${privateKey}'"
  trace "getting nft contract address from bubble contract"
  nftContract=$(bubble contract call -f $(dirname $0)/../contracts/artifacts/AudiobookACC.json ${id} nftContract)
  assertZero $? 2 "failed to query bubble contract for the nft contract address"
  assertAddress "${nftContract}" 1 "failed to query bubble contract for the nft contract address - returned contract is invalid: '${nftContract}'"
  trace "withdrawing ${amount} from nft contract ${nftContract}"
  receipt=$(bubble contract transact --key ${privateKey} ${gasPrice} -f $(dirname $0)/../contracts/artifacts/AudiobookNFT.json ${nftContract} withdraw ${amount})
  assertZero $? 2 "failed to withdraw from nft contract" "${receipt}"
  echo "Successfully withdrew ${amount} from nft contract ${nftContract}"
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
  bubble content write ${verbose} ${binaryOption} --key ${privateKey} bubble-base ${contract} "${filename}" "${inputfile}"
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

assertOptionalFileExists() {
  if [ ! -z "$1" -a ! -f "$1" ]; then error $2 "${3}" "${4}"; fi
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
