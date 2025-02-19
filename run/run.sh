#!/usr/bin/env bash
set -Eeuo pipefail

# Docker environment variables

: ${URL:=''}            # URL of the PAT file
: ${DEBUG:='N'}         # Enable debug mode
: ${ALLOCATE:='Y'}      # Preallocate diskspace
: ${CPU_CORES:='1'}     # Amount of CPU cores
: ${DISK_SIZE:='16G'}   # Initial data disk size
: ${RAM_SIZE:='512M'}   # Maximum RAM amount

echo "Starting Virtual DSM for Docker v${VERSION}..."
trap 'echo >&2 "Error status $? for: ${BASH_COMMAND} (line $LINENO/$BASH_LINENO)"' ERR

[ ! -f "/run/run.sh" ] && echo "ERROR: Script must run inside Docker container!" && exit 11
[ "$(id -u)" -ne "0" ] && echo "ERROR: Script must be executed with root privileges." && exit 12

STORAGE="/storage"
KERNEL=$(uname -r | cut -b 1)

[ ! -d "$STORAGE" ] && echo "ERROR: Storage folder (${STORAGE}) not found!" && exit 13

if [ -f "$STORAGE"/dsm.ver ]; then
  BASE=$(cat "${STORAGE}/dsm.ver")
else
  # Fallback for old installs
  BASE="DSM_VirtualDSM_42962"
fi

[ -n "$URL" ] && BASE=$(basename "$URL" .pat)

if [[ ! -f "$STORAGE/$BASE.boot.img" ]] || [[ ! -f "$STORAGE/$BASE.system.img" ]]; then
  . /run/install.sh
fi

# Initialize disks
. /run/disk.sh

# Initialize network
. /run/network.sh

# Initialize serialport
. /run/serial.sh

# Configure shutdown
. /run/power.sh

KVM_ERR=""
KVM_OPTS=""

if [ -e /dev/kvm ] && sh -c 'echo -n > /dev/kvm' &> /dev/null; then
  if ! grep -q -e vmx -e svm /proc/cpuinfo; then
    KVM_ERR="(cpuinfo $(grep -c -e vmx -e svm /proc/cpuinfo))"
  fi
else
  [ -e /dev/kvm ] && KVM_ERR="(no write access)" || KVM_ERR="(device file missing)"
fi

if [ -n "${KVM_ERR}" ]; then
  echo "ERROR: KVM acceleration not detected ${KVM_ERR}, please enable it."
  [[ "${DEBUG}" == [Yy1]* ]] && exit 88
else
  KVM_OPTS=",accel=kvm -enable-kvm -cpu host"
fi

DEF_OPTS="-nographic -nodefaults -boot strict=on -display none"
RAM_OPTS=$(echo "-m ${RAM_SIZE}" | sed 's/MB/M/g;s/GB/G/g;s/TB/T/g')
CPU_OPTS="-smp ${CPU_CORES},sockets=1,dies=1,cores=${CPU_CORES},threads=1"
MAC_OPTS="-machine type=q35,usb=off,dump-guest-core=off,hpet=off${KVM_OPTS}"
EXTRA_OPTS="-device virtio-balloon-pci,id=balloon0,bus=pcie.0,addr=0x4"
EXTRA_OPTS="$EXTRA_OPTS -object rng-random,id=objrng0,filename=/dev/urandom"
EXTRA_OPTS="$EXTRA_OPTS -device virtio-rng-pci,rng=objrng0,id=rng0,bus=pcie.0,addr=0x1c"

ARGS="${DEF_OPTS} ${CPU_OPTS} ${RAM_OPTS} ${MAC_OPTS} ${MON_OPTS} ${SERIAL_OPTS} ${NET_OPTS} ${DISK_OPTS} ${EXTRA_OPTS}"
ARGS=$(echo "$ARGS" | sed 's/\t/ /g' | tr -s ' ')

trap - ERR

set -m
(
  [[ "${DEBUG}" == [Yy1]* ]] && set -x
  qemu-system-x86_64 ${ARGS:+ $ARGS} & echo $! > "${_QEMU_PID}"
  { set +x; } 2>/dev/null
)
set +m

if (( KERNEL > 4 )); then
  pidwait -F "${_QEMU_PID}" & wait $!
else
  tail --pid "$(cat "${_QEMU_PID}")" --follow /dev/null & wait $!
fi
