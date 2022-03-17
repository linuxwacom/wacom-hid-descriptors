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

IDENT=$(tar --list -f "${ARCHIVE}" | head -n1)
IDENT=${IDENT%/}
MACHINE=$(tar xf "${ARCHIVE}" -O ${IDENT}/machine.txt)

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
if [[ ! -d "${OEM} ${PRODUCT}" ]]; then
  mkdir "${OEM} ${PRODUCT}"
fi
cd "${OEM} ${PRODUCT}"
tar xf "${ARCHIVE}"



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
  if [[ "$ANCHOR" = "#" ]]; then
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


####################
# Determine libwacom properties
#

cd "${IDENT}"

if test $(ls *.hid.txt 2>/dev/null | wc -l) -eq 0; then
  echo "ERROR: No converted HID data found. Was the sensor detected?"
  exit 1
fi

PEN_FILE=$(grep -l "Usage (Pen)" *.hid.txt || true)
TOUCHSCREEN_FILE=$(grep -l "Usage (Touchscreen)" *.hid.txt || true)

SKIP=0
if [[ $(wc -l <<< "${PEN_FILE}") -eq 0 ]]; then
    echo "WARNING: No pen devices found."
    SKIP=1
fi
if [[ $(wc -l <<< "${PEN_FILE}") -gt 1 ]]; then
    echo "WARNING: Multiple pen devices found."
    SKIP=1
fi
if [[ $(wc -l <<< "${TOUCHSCREEN_FILE}") -gt 1 ]]; then
    echo "WARNING: Multiple touchscreens found."
    SKIP=1
fi
if [[ "${PEN_FILE}" != *:056A:* && "${PEN_FILE}" != *:2D1F:* ]]; then
    echo "NOTE: Pen device is not a Wacom sensor. Tablet definition cannot be auto-generated."
    SKIP=1
fi

if [[ ${SKIP} -ne 0 ]]; then
    echo "NOTE: Unable to parse HID data. Skipping creation of libwacom tablet definition."
    exit 0
else
    echo "Attempting to parse HID data and create libwacom tablet definition..."
fi

PEN_ID=$(cut -d. -f1 <<< "${PEN_FILE}" | sed 's/^0003/usb/; s/^0018/i2c/' | tr 'A-F' 'a-f')
PEN_VID=$(cut -d: -f2 <<< "${PEN_ID}")
PEN_PID=$(cut -d: -f3 <<< "${PEN_ID}")
TOUCHSCREEN_ID=$(cut -d. -f1 <<< "${TOUCHSCREEN_FILE}" | sed 's/^0003/usb/; s/^0018/i2c/' | tr 'A-F' 'a-f')
TOUCHSCREEN_VID=$(cut -d: -f2 <<< "${TOUCHSCREEN_ID}")
TOUCHSCREEN_PID=$(cut -d: -f3 <<< "${TOUCHSCREEN_ID}")

PEN_DATA=$(awk -f ${SCRIPTDIR}/hid-data.awk "${PEN_FILE}" 2>/dev/null)

PEN_WIDTH=$(awk -vFS='\t' '/Digitizer Pen\tDesktop X/ {print $12-$11; exit}' <<< "${PEN_DATA}")
PEN_HEIGHT=$(awk -vFS='\t' '/Digitizer Pen\tDesktop Y/ {print $12-$11; exit}' <<< "${PEN_DATA}")
PEN_X=$(awk -vFS='\t' '/Digitizer Pen\tDesktop X/ {print $6-$5; exit}' <<< "${PEN_DATA}")
PEN_Y=$(awk -vFS='\t' '/Digitizer Pen\tDesktop Y/ {print $6-$5; exit}' <<< "${PEN_DATA}")
PEN_RESX=$(awk -vFS='\t' '/Digitizer Pen\tDesktop X/ {printf("%.0f", ($6-$5) / ($12-$11)); exit}' <<< "${PEN_DATA}")
PEN_RESY=$(awk -vFS='\t' '/Digitizer Pen\tDesktop Y/ {printf("%.0f", ($6-$5) / ($12-$11)); exit}' <<< "${PEN_DATA}")
SENSORTYPE=$(grep "Digitizer Battery Strength" <<< "${PEN_DATA}" > /dev/null && echo "AES" || echo "EMR")
TILT_SUPPORT=$(grep "Digitizer X Tilt" <<< "${PEN_DATA}" > /dev/null && echo "Tilt" || true)
TOUCH_SUPPORT=$(test -n "${TOUCHSCREEN_FILE}" && echo "Touch" || true)
if [[ -n "${TOUCH_SUPPORT}" ]]; then
    TOUCH_SUPPORT="${TOUCH_SUPPORT} "$(test "${PEN_ID}" == "${TOUCHSCREEN_ID}" && echo "(Integrated)" || echo "(External)")
fi

FEATURES="${TOUCH_SUPPORT}#${TILT_SUPPORT}"
FEATURES=$(sed -E 's/#+/, /g; s/^, //; s/, $//' <<< ${FEATURES})

LIBWACOM_NOTE=$(cat <<-EOF
	# ${OEM} ${PRODUCT}
	# Sensor Type: ${SENSORTYPE}
	# Features: ${FEATURES}
	# HW Resolution: ${PEN_X} x ${PEN_Y} (${PEN_RESX} x ${PEN_RESY} lpi)
	#
	# Autogenerated from ${IDENT}
	# ${ISSUE_URL}
	EOF
)

LIBWACOM_PREFIX="isdv4-"
if [[ ${PEN_VID} != "056a" ]]; then
    LIBWACOM_PREFIX="${LIBWACOM_PREFIX}${PEN_VID}-"
fi
LIBWACOM_FILE=$(tr A-Z a-z <<<"${LIBWACOM_PREFIX}${PEN_PID}.tablet")
LIBWACOM_NAME="ISDv4 ${PEN_PID}"
LIBWACOM_MATCH=${PEN_ID}
LIBWACOM_CLASS="ISDV4"
if [[ ${SENSORTYPE} == "AES" ]]; then
    LIBWACOM_STYLI="@isdv4-aes;"
elif [[ ${SENSORTYPE} == "EMR" ]]; then
    LIBWACOM_STYLI="0xfffff;0xffffe;"
fi
LIBWACOM_WIDTH=$(printf '%.0f\n' ${PEN_WIDTH})
LIBWACOM_HEIGHT=$(printf '%.0f\n' ${PEN_HEIGHT})
LIBACOM_INTEGRATION="Display;System"
if [[ -n "${TOUCH_SUPPORT}" ]]; then
    LIBWACOM_HASTOUCH="true"
    if [[ "${PEN_ID}" != "${TOUCHSCREEN_ID}" ]]; then
        LIBWACOM_MATCH="${LIBWACOM_MATCH}"$'\n'"PairedID=${TOUCHSCREEN_ID}"
    fi
else
    LIBWACOM_HASTOUCH="false"
fi

####################
# Create tablet definition file
#
cat <<-EOF > "${LIBWACOM_FILE}"
	${LIBWACOM_NOTE}
	
	[Device]
	Name=${LIBWACOM_NAME}
	ModelName=${LIBWACOM_MODEL}
	DeviceMatch=${LIBWACOM_MATCH}
	Class=${LIBWACOM_CLASS}
	Width=${LIBWACOM_WIDTH}
	Height=${LIBWACOM_HEIGHT}
	IntegratedIn=${LIBACOM_INTEGRATION}
	Styli=${LIBWACOM_STYLI}

	[Features]
	Stylus=true
	Touch=${LIBWACOM_HASTOUCH}
	Buttons=0
	EOF
