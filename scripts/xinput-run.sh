#!/bin/bash

SUFFIX=$1
STARTUP_XDEVICES=$(xinput list --id-only | sort)

echo READY
read

RUNNING_XDEVICES=$(xinput list --id-only | sort)
NEW_XDEVICES=$(comm -13 <(echo "$STARTUP_XDEVICES") <(echo "$RUNNING_XDEVICES"))

xdotool mousemove 0 0
for XDEVICE in $NEW_XDEVICES; do
    xinput set-int-prop $XDEVICE "Device Accel Profile" 32 -1
    xinput test-xi2 --root $XDEVICE > "$XDEVICE-xinput-${SUFFIX}.txt" &
done
wait
