#!/bin/bash

export LC_ALL=C

function finish {
	CODE=$1
	cd ..
	rm -rf "$TMPDIR"
	exit $CODE
}
trap finish $? EXIT

function sanitize {
	KEYWORD=$(echo "$2" | sed 's/\([\/&]\)/\\\1/g')
	if [[ -n "$KEYWORD" ]]; then sed -i "s/${KEYWORD}/$1/g" *; fi
}

TMPDIR=$(mktemp -d --tmpdir sysinfo.XXXXXXXXXX) || { echo "Failed."; exit 1; }
OUTFILE=$(readlink -m "$TMPDIR/../$(basename "$TMPDIR").tar.gz")
cd "$TMPDIR"

exec 2> "sysinfo.log"
set -v


if [[ "$EUID" -ne 0 ]]; then echo "NOTE: It is recommended to run this tool as root."; fi

USBIDS="0531 056A 2D1F 04F3 1B96 045E 27C6"
ACPIIDS="WACf WCOM FUJ ELAN NTRG MSFT GXTP"
MODULES="hid_generic hid_multitouch hid_wacom wacom wacom_w8001 wacom_i2c wacom_serial4"

REGEX_VENDORS=$(echo "$USBIDS $ACPIIDS" | sed 's/ /\\|/g')
COMMA_VENDORS=$(echo "$USBIDS $ACPIIDS" | sed 's/ /,/g')
REGEX_MODULES=$(echo "$MODULES $(echo $MODULES | sed 's/_/-/g')" | sed 's/ /\\|/g')
COMMA_MODULES=$(echo "$MODULES $(echo $MODULES | sed 's/_/-/g')" | sed 's/ /,/g')

echo "Gathering system and tablet information. This may take a few seconds."

## General host information
echo "  * General host information..."
uname -a >> host.txt 2>&1
HOST=$(lsb_release -a 2>/dev/null || hostnamectl 2>/dev/null || cat /etc/*release 2>/dev/null)
echo "$HOST" >> host.txt

grep "" /sys/class/dmi/id/* 2>&1 | grep -v -e "_serial:" -e "_uuid:" -e "asset_tag:" >> machine.txt


## Kernel driver information
echo "  * Kernel driver information..."
find /lib/modules/$(uname -r) -type f -iregex ".*/\(${REGEX_MODULES}\)\.ko.*" | xargs ls -l >> kernel_drivers.txt
find /lib/modules/$(uname -r) -type f -iname "hid.ko*" | xargs ls -l >> kernel_drivers.txt
echo >> kernel_drivers.txt
find /sys/module/ -type f -ipath "*wacom*/*version*" | xargs grep "" >> kernel_drivers.txt
echo >> kernel_drivers.txt
for MODULE in $MODULES; do
	modinfo $MODULE >> kernel_drivers.txt 2>&1
	echo >> kernel_drivers.txt
done
modinfo hid >> kernel_drivers.txt 2>&1


## Kernel device information
echo "  * Kernel device information..."
DEVFIND=$(find /sys/devices -type d -iregex ".*\(${REGEX_VENDORS}\)[^/]*")
MODFIND=$(for DEV in $(eval "echo /sys/module/*{$COMMA_MODULES}*/drivers/*/*{$COMMA_VENDORS}*"); do test -d "$DEV" && echo "$DEV" || true; done)
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

for D in $USBIDS; do
	lsusb -v -d $D: >> lsusb.txt 2>&1
done
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
ls -l /usr/lib{,64}/xorg/modules/input/* \
      /usr/lib{,64}/libwacom.so* \
      /usr/lib{,64}/libinput.so* \
      /usr/lib{,64}/libevdev.so* \
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
if command -v libinput-list-devices; then
	libinput-list-devices >> libinput.txt 2>&1
else
	libinput list-devices >> libinput.txt 2>&1
fi


# RandR display information
echo "  * Device display information..."
xrandr --verbose >> xrandr.txt 2>&1


## Logfiles
echo "  * System logs..."
cp --preserve=timestamps /var/log/Xorg.*.log* ~/.local/share/xorg/Xorg.*.log* . 2>/dev/null
journalctl -b0 _COMM=Xorg.bin _COMM=Xorg _COMM=gdm-x-session > journalctl.log 2>&1
dmesg | grep -C5 -i "$REGEX_VENDORS\|$REGEX_MODULES" > dmesg.log


## Configuration Files
echo "  * System config files..."
tar czf xorg-configs.tar.gz --ignore-failed-read \
    /etc/X11/xorg.conf /etc/xorg.conf /usr/etc/X11/xorg.conf \
    /usr/lib/X11/xorg.conf /usr/share/X11/xorg.conf \
    /etc/X11/xorg.conf.d /usr/lib/X11/xorg.conf.d \
    /usr/share/X11/xorg.conf.d
tar czf udev-configs.tar.gz --ignore-failed-read \
    /usr/lib/udev/rules.d /etc/udev/rules.d

## Desktop configuration
echo "  * Desktop configuration data..."
for D in gnome cinnamon mate; do for X in desktop settings-daemon; do DIR=/org/$D/$X/peripherals/; echo "==== $DIR ===="; dconf dump $DIR; done; done > dconf-dump.txt


## Sanitization
echo "  * Removing identifying information..."
sanitize HOSTNAME "$(uname -n)"
sanitize USERNAME "$(whoami)"
sanitize MACHINEID "$(cat /etc/machine-id)"
sanitize BOOTID "$(cat /proc/sys/kernel/random/boot_id)"
sanitize BOOTID "$(tr -d '-' < /proc/sys/kernel/random/boot_id)"


## Tarball generation
echo "  * Tarball generation..."
tar czf "$OUTFILE" -C .. "$(basename "$TMPDIR")"
echo "Finished. Data available in '$OUTFILE'"
