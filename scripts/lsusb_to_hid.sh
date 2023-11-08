#!/bin/bash

SRCFILE=$1
OUTDIR=$(dirname "${SRCFILE}")
RUNDIR=$(dirname "${0}")

D=-1
while [[ 1 ]]; do
	D=$((D+1))
	DATA=$(awk -vD=${D} 'BEGIN {d=-1;} /^Bus / {d++} {if (d==D) {print}}' "${SRCFILE}")
	if [[ -z "${DATA}" ]]; then
		break
	fi

	ID=$(echo "${DATA}" | head -n1 | awk '{print $6}')
	NUM_IF=$(echo "${DATA}" | grep bNumInterfaces | head -n1 | awk '{print $2}')

	for N in $(seq 0 ${NUM_IF}); do
		OUTNAME="${OUTDIR}/${ID}_${N}.hid"
		DESCRIPTOR=$(echo "${DATA}" | awk -vN=${N} 'BEGIN {L=9999} {l=match($0, /\S/)} /bInterfaceNumber/ {n=$2} /Report Descriptor/ {L=l; next} {if (n==N && l>L) {print} else {L=9999}}')

		if [[ -z "${DESCRIPTOR}" ]]; then
			continue
		fi

		echo "${DESCRIPTOR}" | python2 ${RUNDIR}/lsusb_to_hex.py > "${OUTNAME}.bin"
		hidrd-convert -i natv -o spec "${OUTNAME}.bin" > "${OUTNAME}.txt"
		hidrd-convert -i natv -o xml "${OUTNAME}.bin" > "${OUTNAME}.xml"
	done
done
