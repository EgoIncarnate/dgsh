#!/usr/bin/env bash
#
# Implementation of POSIX tee through dgsh-tee
#

# Process flags
args=$(getopt ai "$@")
if [ $? -ne 0 ]; then
   echo 'Usage: tee [-ai] [file ...]'
   exit 2
fi

declare -a opts

for i in $args; do
   case "$1" in
   -a)
	   opts=(-a)
	   shift
	   ;;
   -i)
	   shift
	   ;;
   --)
	   shift; break
	   ;;
   esac
done

# Process file arguments
for i; do
    opts+=('-o' "$i")
    shift
done

exec @libexecdir@/dgsh/dgsh-tee "${opts[@]}"
