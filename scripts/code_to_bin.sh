#!/bin/bash

# Convert "code"-style HID dumps into binary HID descriptors
#
# Usage: code_to_bin.sh [-D <name>=<definition>]... [--] <source>
#
# Options:
#   -D <name>=<definition>   Add a compiler preprocessor #define for 'name'
#                            which has the provided definition.
#   source                   A file containing a "code"-style HID descriptor
#
# This script attempts to convert "code"-style HID descriptors (i.e. files
# consisting of comma-seperated hex literals and possibly comments or
# macro references) into a binary HID descriptor. The script will attempt
# to use the file as the contents of a C array that is compiled, so the
# input must satisfy basic C grammar requirements. The binary descriptor
# is sent to stdout, and so should either be redirected to a file or piped
# into another command.
#
# Because "code"-style descriptors may potentially reference preprocessor
# macros, this script allows the definition of any necessary macros on
# the command-line. A few stock definitions are also included that may
# be useful. These stock definitions occur before those provided on the
# command-line, and so may be referenced if necessary.
#

set -e

POSITIONAL=()
DEFINES=()
CONSUME=0
while [[ $# -gt 0 ]]; do
	KEY="$1"
	if [[ $CONSUME -eq 0 ]]; then
		case $KEY in
		-D)
			NAME="${2%%=*}"
			DEFN="${2#*=}"
			DEFINES+=("#define $NAME $DEFN")
			shift
			shift
			;;
		--)
			CONSUME=1
			shift
			;;
		*)
			POSITIONAL+=("$1")
			shift
			;;
		esac
	else
		POSITIONAL+=("$1")
		shift
	fi
done
set -- "${POSITIONAL[@]}"

SOURCEFILE=$(readlink -e "$1")
shift

if [[ $# -gt 0 ]]; then
	echo "Unknown arguments: $@"
	exit 1
fi


SRC_TEMP=$(mktemp --suffix=.c)
OBJ_TEMP=$(mktemp --suffix=.o)
BIN_TEMP=$(mktemp --suffix=.bin)

trap "{ rm -f \"$SRC_TEMP\" \"$OBJ_TEMP\" \"$BIN_TEMP\"; }" EXIT


IFS=$(echo -en "\n\b"); cat >> "$SRC_TEMP" <<EOF-EOF-EOF
#define BYTEX(X,N) ((N>>(X*8))&0xff)
#define LE32(N)    BYTEX(0,N), BYTEX(1,N), BYTEX(2,N) BYTEX(3,N)
#define LE16(N)    BYTEX(0,N), BYTEX(1,N)
#define LE8(N)     BYTEX(0,N)

${DEFINES[*]}

const unsigned char hiddata[] = {
#include "$SOURCEFILE"
};
EOF-EOF-EOF


gcc -c -o "$OBJ_TEMP" "$SRC_TEMP"
objcopy -O binary -j .rodata "$OBJ_TEMP" "$BIN_TEMP"
cat "$BIN_TEMP"
