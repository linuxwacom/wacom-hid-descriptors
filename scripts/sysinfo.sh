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
echo "  * General host information..."
uname -a >> host.txt 2>&1
HOST=$(lsb_release -a 2>/dev/null || hostnamectl 2>/dev/null || cat /etc/*release 2>/dev/null)
echo "$HOST" >> host.txt

grep "" /sys/class/dmi/id/* 2>&1 | grep -v -e "_serial:" -e "_uuid:" -e "asset_tag:" >> machine.txt


## Kernel driver information
echo "  * Kernel driver information..."
find /lib/modules/$(uname -r) -type f -iname "*wacom*" | xargs ls -l >> kernel_drivers.txt
find /lib/modules/$(uname -r) -type f -iname "hid-generic.ko*" | xargs ls -l >> kernel_drivers.txt
find /lib/modules/$(uname -r) -type f -iname "hid-multitouch.ko*" | xargs ls -l >> kernel_drivers.txt
find /lib/modules/$(uname -r) -type f -iname "hid.ko*" | xargs ls -l >> kernel_drivers.txt
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
echo >> kernel_drivers.txt
modinfo hid-generic >> kernel_drivers.txt 2>&1
echo >> kernel_drivers.txt
modinfo hid-multitouch >> kernel_drivers.txt 2>&1
echo >> kernel_drivers.txt
modinfo hid >> kernel_drivers.txt 2>&1


## Kernel device information
echo "  * Kernel device information..."
VENDORIDS="0531 056A 2D1F WACf FUJ 04F3 ELAN 1B96 NTRG 045E MSFT"
DEVFIND=$(eval find /sys/devices -type d $(for ID in $VENDORIDS; do echo -n "-iname \"*$ID*\" -or "; done | sed 's/ -or $//'))
MODULEFIND=$(for DEV in /sys/module/*{hid_generic,hid_multitouch,wacom}*/drivers/*/{$(echo $VENDORIDS | sed 's/ /,/g')}; do test -d "$DEV" && echo "$DEV" || true; done)
DEVLIST=$(for DEV in $DEVFIND $MODULEFIND; do readlink -f "$DEV"; done | sort | uniq)

for DEV in $DEVLIST; do
	echo "     - $DEV..."

	if test -f "$DEV/report_descriptor"; then
		cp "$DEV/report_descriptor" "$(basename "$DEV").hid.bin"
	fi

	if test -d "$DEV/input"; then
		for INPUT in $DEV/input/*; do
			udevadm info -a -p "$INPUT" >> "udevadm_$(basename "$DEV").txt" 2>&1
		done
	fi

	echo "********* $DEV" >> devtree.txt
	find "$DEV" -not -type f -exec bash -c 'N={}; D=`readlink -f $N`; echo -n $N; if [[ x"$N" != x"$D" ]]; then echo -n " -> $D"; fi; echo' \; >> devtree.txt
	echo >> devtree.txt

	echo "********* $DEV" >> devtree_data.txt
	grep -r "" "$DEV" >> devtree_data.txt 2>&1
	echo >> devtree_data.txt
done

DO_PRINT=0
echo "     - udev..."
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
echo "  * Unbinding devices..."
for D in /sys/module/wacom/drivers/usb:wacom/*; do
	if test -d "$D/input"; then
		# Temporarily unbind usb:wacom devices so lsusb
		# can retrieve the HID descriptor
		echo "     - $DEV..."
		DEV=$(basename $D)
		BINDLIST="$BINDLIST $DEV"
		echo -n $DEV > /sys/module/wacom/drivers/usb:wacom/unbind
	fi
done

lsusb -v -d 056a: >> lsusb.txt 2>&1
lsusb -v -d 0531: >> lsusb.txt 2>&1
lsusb -v -d 2d1f: >> lsusb.txt 2>&1
lsusb -v -d 04f3: >> lsusb.txt 2>&1
lsusb -v -d 1b9b: >> lsusb.txt 2>&1
lsusb -v -d 045e: >> lsusb.txt 2>&1
lsusb -t > lsusb_tree.txt 2>&1

echo "  * Rebinding devices..."
for DEV in $BINDLIST; do
	# Rebind usb:wacom devices so that they function
	# once again
	echo "     - $DEV"
	echo -n $DEV > /sys/module/wacom/drivers/usb:wacom/bind
done


## Userspace driver information
echo "  * Userspace driver information..."
ls -l /usr/lib{,64}/xorg/modules/input/wacom_drv.so* \
      /usr/lib{,64}/libwacom.so* \
      /usr/lib{,64}/libinput.so* \
      /usr/lib{,64}/xorg/modules/input/libinput_drv.so* \
      /usr/bin/inputattach* \
      >> userspace_drivers.txt 2>&1

PACKAGES=$(pacman -Qi xf86-input-wacom libwacom libinput xf86-input-libinput linuxconsole 2>/dev/null || \
           zypper info xf86-input-wacom libwacom libinput xf86-input-libinput linuxconsoletools 2>/dev/null || \
           dpkg -s xserver-xorg-input-wacom libwacom2 libinput5 xserver-xorg-input-libinput inputattach 2>/dev/null || \
           yum info xorg-x11-drv-wacom libwacom libinput xorg-x11-drv-libinput linuxconsoletools 2>/dev/null || \
           dnf info xorg-x11-drv-wacom libwacom libinput xorg-x11-drv-libinput linuxconsoletools 2>/dev/null)
echo "$PACKAGES" >> packages.txt

xsetwacom -V >> xsetwacom.txt 2>&1


## Userspace device information
echo "  * Userspace device information..."
xinput list >> xinput.txt 2>&1
xsetwacom -v list >> xsetwacom.txt 2>&1
libwacom-list-local-devices >> libwacom.txt 2>&1
libinput-list-devices >> libinput.txt 2>&1


## Logfiles
echo "  * System logs..."
cp --preserve=timestamps /var/log/Xorg.*.log* ~/.local/share/xorg/Xorg.*.log* . 2>/dev/null
journalctl -b0 _COMM=Xorg.bin _COMM=Xorg _COMM=gdm-x-session > journalctl.log 2>&1
dmesg | grep -C5 -i -E "wacom|056a|0531|2d1f|04F3|1b96|045E|WACF|FUJ|ELAN|NTRG|MSFT" > dmesg.log


## Tarball generation
echo "  * Tarball generation..."
tar czf "$OUTFILE" -C .. "$(basename "$TMPDIR")"
echo "Finished. Data available in '$OUTFILE'"
