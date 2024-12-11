#!/bin/bash

#
# Extract a sysinfo archive into a directory suitable for commit and
# auto-generate a tablet definition file.
#
# Usage: 
#     git-update.sh <archive> <--url=<post> | --nourl> [--oem=<name>] [--product=<name>]
#
# archive           Path to the sysinfo archive to be processed
# --url=<post>      Link to the post which produced this archive
# --nourl           Explicitly do not reference a public sysinfo posting
# --oem=<name>      Override the OEM name contained in machine.txt
# --product=<name>  Override the product name contained in machine.txt
#

set -e

SCRIPTDIR=$(dirname $(readlink -f "$0"))

####################
# Argument parsing
#
for arg in "${@}"; do
  case $arg in
    --url=*) ISSUE_URL="${arg#*=}"; shift;;
    --nourl) NOURL=1; shift;;
    --oem=*) OEM="${arg#*=}"; shift;;
    --product=*) PRODUCT="${arg#*=}"; shift;;
    *) ARCHIVE=$(readlink -f "${arg}"); shift;;
  esac
done

if [[ -f "${ARCHIVE}" ]]; then
  IDENT=$(tar --list -f "${ARCHIVE}" | head -n1)
  IDENT=${IDENT%/}
  MACHINE=$(tar xf "${ARCHIVE}" -O ${IDENT}/machine.txt)
else
  IDENT="${ARCHIVE}"
  IDENT=${IDENT%/}
  MACHINE=$(cat "${IDENT}"/machine.txt)
fi

if [[ -n "${NOURL}" ]]; then
  echo "NOTE: Treating as a private bug..."
  ISSUE_URL="From private bug report"
elif [[ -z "${ISSUE_URL}" ]]; then
  echo "ERROR: The --url=<issue> parameter is required."
  exit 1
elif [[ "${ISSUE_URL}" != *"github"* ]]; then
  echo "ERROR: This script can only handle Github issues."
  exit 1
fi

if [[ -z "${OEM}" ]]; then
  OEM=$(awk -F: '/\/chassis_vendor/ {print $2}' <<< "${MACHINE}")
  case "${OEM}" in
    "Acer")                  OEM="Acer";;
    "Dell Inc.")             OEM="Dell";;
    "FUJITSU")               OEM="Fujitsu";;
    "Google")                OEM="Google";;
    "Hewlett-Packard")       OEM="HP";;
    "HP")                    OEM="HP";;
    "LENOVO")                OEM="Lenovo";;
    "Microsoft Corporation") OEM="Microsoft";;
    "SAMSUNG ELECTRONICS CO., LTD.") OEM="Samsung";;
    "Motion Computing")      OEM="Motion Computing";;
    "MOTION")                OEM="Motion Computing";;
    "ASUSTeK COMPUTER INC.") OEM="ASUS";;
    "HUAWEI")                OEM="Huawei";;
    "Panasonic Corporation") OEM="Panasonic";;
    *)                       echo "ERROR: Unknown OEM '${OEM}'. Please specify one with the --oem=<name> argument."; exit 1;;
  esac
fi

if [[ -z "${PRODUCT}" ]]; then
  if [[ "${OEM}" = "Lenovo" ]]; then
    PRODUCT=$(awk -F: '/\/product_family/ {print $2}' <<< "${MACHINE}")
  else
    PRODUCT=$(awk -F: '/\/product_name/ {print $2}' <<< "${MACHINE}")
  fi

  if [[ -z "${PRODUCT}" ]]; then
    echo "ERROR: Unable to determine product name. Please specify one with the --product=<name> argument."
    exit 1
  fi
fi

if [[ "${PRODUCT}" =~ "${OEM} "* ]]; then
    echo "NOTE: Removing manufacturer from product name..."
    PRODUCT=${PRODUCT#"${OEM} "}
fi

echo "Manufacturer: \"${OEM}\""
echo "Product: \"${PRODUCT}\""
while true; do
  read -p "Is this correct? (Y/N) " yn
  case $yn in
    [Yy]*) break;;
    [Nn]*)
      echo "ERROR: Please specify OEM and/or product with the --oem=<name> and --product=<name> arguments."
      exit 1;;
    *);;
  esac
done



####################
# Extract archive into proper directory
#
if [[ ! -d "$ARCHIVE" ]]; then
  if [[ ! -d "${OEM} ${PRODUCT}" ]]; then
    mkdir "${OEM} ${PRODUCT}"
  fi
  cd "${OEM} ${PRODUCT}"
  tar xf "${ARCHIVE}"
fi



####################
# Process archive: extract and convert data
#
ARCHIVE_DATE=$(date -r "${IDENT}" +%Y-%m-%d)

if test $(ls "${IDENT}/"*.hid.bin 2>/dev/null | wc -l) -gt 0; then
  for F in "${IDENT}/"*.hid.bin; do
    hidrd-convert -i natv -o spec "${F}" > "${F%bin}txt"
    hidrd-convert -i natv -o xml "${F}" > "${F%bin}xml"
  done
fi

# Find the Wacom pen sensor
# Create a device ID (e.g. "i2c:056a:1234")
# Determine width and height in inches
# Create tablet definition



####################
# Create/update README file
#
if [[ ! -f "README" ]]; then
  NOTES=""

  cat <<-EOF > README
	Manufacturer: ${OEM}
	Model Name: ${PRODUCT}
	Model Number:
	
	Notes: ${NOTES}
	
	Source(s):
	EOF
fi

if [[ -z "${NOURL}" ]]; then
  ANCHOR="#${ISSUE_URL#*#}"
  if [[ "$ANCHOR" = "#${ISSUE_URL}" ]]; then
    USERNAME=$(curl "${ISSUE_URL}" | sed -En 's!.*>([^<]*)</a>\s+opened this issue.*!\1!p' | head -n1)
  else
    USERNAME=$(curl "${ISSUE_URL}" | grep -C10 "$ANCHOR" | sed -En 's!^.+>([^<]+)</a>$!\1!p' | head -n1)
  fi
  USER_URL="https://github.com/${USERNAME}"
  cat <<-EOF >> README
	* ${IDENT}
	  ${USERNAME} [${USER_URL}]
	  ${ISSUE_URL}
	  ${ARCHIVE_DATE}
	
	EOF
else
  cat <<-EOF >> README
	* ${IDENT}
	  ${ISSUE_URL}
	  ${ARCHIVE_DATE}
	
	EOF
fi

echo "Generated '$(pwd)/README"

####################
# Determine libwacom properties
#

${SCRIPTDIR}/gen-libwacom.sh --ref="${ISSUE_URL}" --oem="${OEM}" --product="${PRODUCT}" "${IDENT}"
