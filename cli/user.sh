#!/bin/bash

# Constants

privateKey=requester

PUBLIC_METADATA_FILE='0x8000000000000000000000000000000000000001'
REGISTRY_CONTRACT='0x9B0E06b0Ceb584C1f5B46b18d6eDEC09d5BC073E'


# Options

verbose=''

usage() { 
  echo "Usage:"
  echo "  $0 discover [author-id]"
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
    *) usage ;;
  esac
}

discover() {
  authorIdParam=$1
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
  trace "${#bubbleArr[@]} audiobooks found"
  authorId=$authorIdParam
  for b in $bubbles
  do
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
    echo "id: ${b}, author-id: ${authorId}, author: ${author}, title: ${title}"
  done
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
