#!/bin/bash

OUTDIR=$(dirname "$1")
OUTNAME=${OUTDIR}/descriptor-converted.hid
echo $OUTDIR
echo $OUTNAME
awk '/Endpoint Descriptor/ { REPORT=0 } { if (length == 0) { REPORT = 0 } if (REPORT == 1) { print $0 } } /length is/ { REPORT=1 }' < "$1" | python2 lsusb_to_hex.py > "${OUTNAME}.bin"
hidrd-convert -i natv -o spec "${OUTNAME}.bin" "${OUTNAME}.txt"
hidrd-convert -i natv -o xml "${OUTNAME}.bin" "${OUTNAME}.xml"
