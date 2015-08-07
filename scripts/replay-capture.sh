#!/bin/bash

# Replay a hidrecord file from stdin and capture debugging output from
# evemu and xinput.
#
# This can be executed from within an existing X session fairly reliably,
# though in some cases (especially multi-touch devices with changing
# "detail" fields) executing within a fresh session might work better:
#
#     $ sudo xinit <script> <filename> <suffix> -- :2 vt2
#

if [[ $# -ne 2 ]]; then
	echo "Usage: $0 <filename> <suffix>"
	exit 1
fi
HIDFILE=$1
SUFFIX="-$2"

STARTUP_KDEVICES=$(ls /dev/input/event* | sort)
STARTUP_XDEVICES=$(xinput list --id-only | sort)

/mnt/1/development/misc/hid-replay/src/hid-replay -s 2 -1 "$HIDFILE" &
PID_HIDREPLAY=$!
sleep 1

RUNNING_KDEVICES=$(ls /dev/input/event* | sort)
RUNNING_XDEVICES=$(xinput list --id-only | sort)

NEW_KDEVICES=$(comm -13 <(echo "$STARTUP_KDEVICES") <(echo "$RUNNING_KDEVICES"))
NEW_XDEVICES=$(comm -13 <(echo "$STARTUP_XDEVICES") <(echo "$RUNNING_XDEVICES"))

for KDEVICE in $NEW_KDEVICES; do
	evemu-record $KDEVICE > "$(basename $KDEVICE)-evemu${SUFFIX}.txt" &
done
xdotool mousemove 0 0
for XDEVICE in $NEW_XDEVICES; do
	xinput set-int-prop $XDEVICE "Device Accel Profile" 32 -1
	xinput test-xi2 --root $XDEVICE > "$XDEVICE-xinput${SUFFIX}.txt" &
done

wait $PID_HIDREPLAY
for JOB in $(jobs -p); do
	kill $JOB
done

