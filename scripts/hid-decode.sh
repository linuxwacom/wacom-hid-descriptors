#!/usr/bin/env bash


usage() {
    cat <<EOF
Usage: $(basename "$0") <0123:abcd.hid.bin>

Converts a .hid.bin format captured by sysinfo
into a text file that can be replayed by hid-replay

See https://gitlab.freedesktop.org/libevdev/hid-tools/
EOF
}

die () {
    echo "$1" 1>&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            usage
            exit 0
            ;;
        *.hid.bin)
            binfile="$1"
            shift
            ;;
        **)
            usage
            exit 2
            ;;
    esac
done

[[ -n "$binfile" ]] || { usage && exit 1; }

command -v hid-decode || die "hid-decode is missing, please install hid-tools"

# Extract the device name from the udevadm 
fname=$(basename "$binfile") 
dirpath=$(dirname "$binfile")
udevadm_file="udevadm_${fname%.hid.bin}.txt"

[[ -e "$dirpath/$udevadm_file" ]] || die "Unable to find matching udevadm output"

name=$(grep --max-count=1 "ATTR{name}" "$dirpath/$udevadm_file" | sed -e "s/.*==\"\(.*\)\"/\1/")
name=${name% Pen} # Strip the kernel prefix, whichever one applies and came first
name=${name% Pad}
name=${name% Finger}

bustype=$(grep --max-count=1 "ATTR{id/bustype}" "$dirpath/$udevadm_file" | sed -e "s/.*==\"\(.*\)\"/\1/")
vid=$(grep --max-count=1 "ATTR{id/vendor}" "$dirpath/$udevadm_file"      | sed -e "s/.*==\"\(.*\)\"/\1/")
pid=$(grep --max-count=1 "ATTR{id/product}" "$dirpath/$udevadm_file"     | sed -e "s/.*==\"\(.*\)\"/\1/")

# grep "ATTR{name}" ./Wacom\ Cintiq\ Pro\ 27/sysinfo.rLRz2hqrEy/udevadm_0003:056A:03C0.0001.txt

hid-decode "$binfile" \
    | sed -e "s/^N: .*/N: $name/" \
    | sed -e "s/^I: .*/I: $bustype $vid $pid/"
