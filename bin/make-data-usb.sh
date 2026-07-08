#!/usr/bin/env bash
: <<DOCXX
-----------------------------------------------------------------------------
  make-data-usb.sh

  Purpose:
    Safely repartition and format a USB or removable block device as a single
    data partition.

  Usage:
    sudo ./make-data-usb.sh -t exfat sdb
    sudo ./make-data-usb.sh sdb -t exfat

  Filesystems supported:
    - ext4
    - exfat
    - vfat

  WARNING:
    THIS SCRIPT DESTROYS ALL DATA ON THE SPECIFIED DEVICE.

  Author:
    Morganism

  License:
    MIT, Copyleft © Morganism
-----------------------------------------------------------------------------
DOCXX

RED="\033[0;31m"
GREEN="\033[0;32m"
WHITE="\033[0;37m"
RESET="\033[0m"

set -euo pipefail

# -------------------------------
# CONFIG
# -------------------------------
FS_TYPE="ext4"
LABEL="DATAUSB"

# -------------------------------
# HELP
# -------------------------------
show_help() {
  echo -e "${WHITE}"
  echo -e "Usage:"
  echo -e "  sudo $0 -t <filesystem> <device>"
  echo -e "  sudo $0 <device> -t <filesystem>"
  echo -e ""
  echo -e "Example:"
  echo -e "  sudo $0 -t exfat sdb"
  echo -e ""
  echo -e "Accepted filesystems:"
  echo -e "  ext4 | exfat | vfat"
  echo -e ""
  echo -e "Available block devices:"
  lsblk -d -o NAME,SIZE,TYPE,MODEL,RM | awk '
    NR==1 {print; next}
    $3=="disk" && $1 !~ /^loop/ && $1 !~ /^ram/ {print}
  '
  echo -e "${RESET}"
  exit 0
}

# -------------------------------
# ARG PARSING (FIXED ORDER-INDEPENDENT)
# -------------------------------
POSITIONAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--type)
      FS_TYPE="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      ;;
    *)
      POSITIONAL="$1"
      shift
      ;;
  esac
done

DEVICE="${POSITIONAL:-}"

if [[ -z "$DEVICE" ]]; then
  show_help
fi

# -------------------------------
# NORMALISE DEVICE PATH
# -------------------------------
if [[ "$DEVICE" != /dev/* ]]; then
  DEVICE="/dev/$DEVICE"
fi

# -------------------------------
# VALIDATION
# -------------------------------
if [[ ! -b "$DEVICE" ]]; then
  echo -e "${RED}ERROR: $DEVICE is not a valid block device${RESET}"
  echo -e "${WHITE}Available devices:${RESET}"
  lsblk -d -o NAME,SIZE,TYPE,MODEL,RM | awk '
    NR==1 {print; next}
    $3=="disk" && $1 !~ /^loop/ && $1 !~ /^ram/ {print}
  '
  exit 1
fi

if [[ "$DEVICE" == *loop* ]]; then
  echo -e "${RED}ERROR: Refusing loop device${RESET}"
  exit 1
fi

# -------------------------------
# SUDO CHECK
# -------------------------------
sudo -v
echo -e "${GREEN}✔ sudo verified${RESET}"

echo -e "${WHITE}========================================${RESET}"
echo -e "${WHITE} DEVICE : $DEVICE${RESET}"
echo -e "${WHITE} FS     : $FS_TYPE${RESET}"
echo -e "${WHITE} LABEL  : $LABEL${RESET}"
echo -e "${WHITE}========================================${RESET}"

sudo lsblk "$DEVICE"
echo
read -rp "Type 'YES' to WIPE device: " CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
  echo -e "${WHITE}Aborted.${RESET}"
  exit 1
fi

# -------------------------------
# UNMOUNT
# -------------------------------
echo -e "${WHITE}[*] Unmounting partitions...${RESET}"

for part in $(lsblk -ln -o NAME "$DEVICE" | tail -n +2); do
  sudo umount "/dev/$part" 2>/dev/null || true
done

# -------------------------------
# PARTITION
# -------------------------------
echo -e "${WHITE}[*] Creating GPT partition table...${RESET}"

sudo parted --script "$DEVICE" \
  mklabel gpt \
  mkpart primary 0% 100%

sleep 2
sudo partprobe "$DEVICE"

PARTITION="${DEVICE}1"

# -------------------------------
# FORMAT
# -------------------------------
echo -e "${WHITE}[*] Formatting $PARTITION as $FS_TYPE...${RESET}"

case "$FS_TYPE" in
  ext4)
    sudo mkfs.ext4 -F -L "$LABEL" "$PARTITION"
    ;;
  exfat)
    sudo mkfs.exfat -n "$LABEL" "$PARTITION"
    ;;
  vfat)
    sudo mkfs.vfat -F32 -n "$LABEL" "$PARTITION"
    ;;
  *)
    echo -e "${RED}ERROR: Unsupported filesystem '$FS_TYPE'${RESET}"
    echo -e "${WHITE}Supported: ext4 | exfat | vfat${RESET}"
    exit 1
    ;;
esac

# -------------------------------
# DONE
# -------------------------------
echo
echo -e "${GREEN}✔ USB data drive ready${RESET}"
sudo lsblk "$DEVICE"
