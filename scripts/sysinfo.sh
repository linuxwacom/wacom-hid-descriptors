#!/bin/sh

echo "Gathering system & tablet information. This may take a few seconds."

TMPDIR=$(mktemp -d --tmpdir sysinfo.XXXXXXXXXX) || { echo "Failed."; exit 1; }
cd "$TMPDIR"

grep "" /sys/module/wacom/*version* > module_wacom.txt 2>&1
modinfo wacom >> module_wacom.txt 2>&1

grep "" /sys/module/wacom_w8001/*version* > module_wacom_w8001.txt 2>&1
modinfo wacom_w8001 >> module_wacom_w8001.txt 2>&1

ls -l /usr/lib{,64}/libwacom.so* > userspace.txt 2>&1
ls -l /usr/lib{,64}/libinput.so* >> userspace.txt 2>&1
ls -l /usr/lib{,64}/xorg/modules/input/wacom_drv.so* >> userspace.txt 2>&1

uname -a > host.txt 2>&1
HOST=$(lsb_release -a 2>/dev/null || hostnamectl 2>/dev/null || cat /etc/*release 2>/dev/null)
echo "$HOST" >> host.txt

lsusb -v -d 056a: > lsusb.txt 2>&1
lsusb -v -d 0531: >> lsusb.txt 2>&1
lsusb -t > lsusb_tree.txt 2>&1

grep "" /sys/class/dmi/id/* > sys_class_dmi_id.txt 2>&1

for D in /sys/bus/hid/drivers/wacom/*; do
	if test ! -f "$D/report_descriptor"; then
		continue
	fi

	cp "$D/report_descriptor" "$(basename "$D").hid.bin"
	for X in "$D"/input/*/event*; do
		 udevadm info -a -p "$X" > "udevadm_$(basename "$X").txt"
	done
done

DO_PRINT=0
udevadm info -e | while read -r LINE; do
	if [[ "$LINE" == "P: "* ]]; then
		DEVICE=$(echo "$LINE" | cut -d' ' -f 2-)
		if grep -q "$DEVICE" udevadm_*.txt 2>/dev/null; then
			DO_PRINT=1
		else
			DO_PRINT=0
		fi
	fi
	if [[ $DO_PRINT == 1 ]]; then
		echo "$LINE" >> udevadm.txt
	fi
done

cd ..
tar czf "$(basename "$TMPDIR").tar.gz" "$(basename "$TMPDIR")"
rm -rf "$TMPDIR"

echo "Finished. Data available in '$(pwd)/$(basename "$TMPDIR").tar.gz'"
