#!/bin/bash

SUFFIX=$1
STARTUP_KDEVICES=$(ls /dev/input/event* | sort)

echo READY
read

RUNNING_KDEVICES=$(ls /dev/input/event* | sort)
NEW_KDEVICES=$(comm -13 <(echo "$STARTUP_KDEVICES") <(echo "$RUNNING_KDEVICES"))

for KDEVICE in $NEW_KDEVICES; do
    evemu-record $KDEVICE > "$(basename $KDEVICE)-evemu-${SUFFIX}.txt" &
done
wait
