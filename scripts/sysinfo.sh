#!/bin/bash

if [[ "$EUID" -ne 0 ]]; then echo "NOTE: It is recommended to run this tool as root."; fi

echo "Gathering system and tablet information. This may take a few seconds."

TMPDIR=$(mktemp -d --tmpdir sysinfo.XXXXXXXXXX) || { echo "Failed."; exit 1; }
OUTFILE=$(readlink -m "$TMPDIR/../$(basename "$TMPDIR").tar.gz")
cd "$TMPDIR"

function finish {
	CODE=$1
	cd ..
	rm -rf "$TMPDIR"
	exit $CODE
}
trap finish $? EXIT


## General host information
uname -a >> host.txt 2>&1
HOST=$(lsb_release -a 2>/dev/null || hostnamectl 2>/dev/null || cat /etc/*release 2>/dev/null)
echo "$HOST" >> host.txt

grep "" /sys/class/dmi/id/* >> machine.txt 2>&1


## Kernel driver information
find /lib/modules/$(uname -r) -type f -iname "*wacom*" | xargs ls -l >> kernel_drivers.txt
echo >> kernel_drivers.txt
find /sys/module/ -type f -ipath "*wacom*/*version*" | xargs grep "" >> kernel_drivers.txt
echo >> kernel_drivers.txt
modinfo wacom >> kernel_drivers.txt 2>&1
echo >> kernel_drivers.txt
modinfo wacom_serial4 >> kernel_drivers.txt 2>&1
echo >> kernel_drivers.txt
modinfo wacom_w8001 >> kernel_drivers.txt 2>&1
echo >> kernel_drivers.txt
modinfo wacom_i2c >> kernel_drivers.txt 2>&1
echo >> kernel_drivers.txt
modinfo hid-wacom >> kernel_drivers.txt 2>&1


## Kernel device information
DEVLIST=$(find /sys/devices -iname "*0531*" -or -iname "*056A*" -or -iname "*2D1F*");
for F in $DEVLIST; do
	echo "*********" >> devtree.txt
	find "$F" -not -type f -exec sh -c 'N={}; D=`readlink -f $N`; echo -n $N; if [[ x"$N" != x"$D" ]]; then echo -n " -> $D"; fi; echo' \; >> devtree.txt
	echo >> devtree.txt
done

for DEV in /sys/module/hid_generic/drivers/*/*056A* \
           /sys/module/hid_generic/drivers/*/*0531* \
           /sys/module/hid_generic/drivers/*/*2D1F* \
           /sys/module/*wacom*/drivers/*/* ; do
	if test -f "$DEV/report_descriptor"; then
		cp "$DEV/report_descriptor" "$(basename "$DEV").hid.bin"
	fi

	if test -d "$DEV/input"; then
		for INPUT in $DEV/input/*; do
			udevadm info -a -p "$INPUT" >> "udevadm_$(basename "$DEV").txt" 2>&1
		done
	fi
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

BINDLIST=""
for D in /sys/module/wacom/drivers/usb:wacom/*; do
	if test -d "$D/input"; then
		# Temporarily unbind usb:wacom devices so lsusb
		# can retrieve the HID descriptor
		DEV=$(basename $D)
		BINDLIST="$BINDLIST $DEV"
		echo -n $DEV > /sys/module/wacom/drivers/usb:wacom/unbind
	fi
done

lsusb -v -d 056a: >> lsusb.txt 2>&1
lsusb -v -d 0531: >> lsusb.txt 2>&1
lsusb -v -d 2d1f: >> lsusb.txt 2>&1
lsusb -t > lsusb_tree.txt 2>&1

for DEV in $BINDLIST; do
	# Rebind usb:wacom devices so that they function
	# once again
	echo -n $DEV > /sys/module/wacom/drivers/usb:wacom/bind
done


## Userspace driver information
ls -l /usr/lib{,64}/xorg/modules/input/wacom_drv.so* \
      /usr/lib{,64}/libwacom.so* \
      /usr/lib{,64}/libinput.so* \
      /usr/lib{,64}/xorg/modules/input/libinput_drv.so* \
      >> userspace_drivers.txt 2>&1

PACKAGES=$(pacman -Qi xf86-input-wacom libwacom libinput xf86-input-libinput 2>/dev/null || \
           zypper info xf86-input-wacom libwacom libinput xf86-input-libinput 2>/dev/null || \
           dpkg -s xserver-xorg-input-wacom libwacom2 libinput5 xserver-xorg-input-libinput 2>/dev/null || \
           yum info xorg-x11-drv-wacom libwacom libinput xorg-x11-drv-libinput 2>/dev/null || \
           dnf info xorg-x11-drv-wacom libwacom libinput xorg-x11-drv-libinput 2>/dev/null)
echo "$PACKAGES" >> packages.txt

xsetwacom -V >> xsetwacom.txt 2>&1


## Userspace device information
xinput list >> xinput.txt 2>&1
xsetwacom -v list >> xsetwacom.txt 2>&1
libwacom-list-local-devices >> libwacom.txt 2>&1
libinput-list-devices >> libinput.txt 2>&1


## Tarball generation
tar czf "$OUTFILE" -C .. "$(basename "$TMPDIR")"
echo "Finished. Data available in '$OUTFILE'"
