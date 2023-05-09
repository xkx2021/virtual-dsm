#!/bin/bash
set -Eeuo pipefail

# Docker environment variables

: ${HOST_CPU:=''}
: ${HOST_BUILD:=''}
: ${HOST_DEBUG:=''}
: ${HOST_SERIAL:=''}
: ${GUEST_SERIAL:=''}
: ${HOST_VERSION:=''}
: ${HOST_TIMESTAMP:=''}

if [ -z "$HOST_CPU" ]; then
  HOST_CPU=$(lscpu | sed -nr '/Model name/ s/.*:\s*(.*) @ .*/\1/p' | sed ':a;s/  / /;ta' | sed s/"(R)"//g | sed 's/[^[:alnum:] ]\+/ /g' | sed 's/  */ /g')
fi

if [ -n "$HOST_CPU" ]; then
  HOST_CPU="$HOST_CPU,,"
else
  HOST_CPU="QEMU, Virtual CPU, X86_64"
fi

HOST_ARGS=()
HOST_ARGS+=("-cpu_arch=${HOST_CPU}")

[ -n "$CPU_CORES" ] && HOST_ARGS+=("-cpu=${CPU_CORES}")
[ -n "$HOST_BUILD" ] && HOST_ARGS+=("-build=${HOST_BUILD}")
[ -n "$HOST_SERIAL" ] && HOST_ARGS+=("-hostsn=${HOST_SERIAL}")
[ -n "$GUEST_SERIAL" ] && HOST_ARGS+=("-guestsn=${GUEST_SERIAL}")
[ -n "$HOST_VERSION" ] && HOST_ARGS+=("-version=${HOST_VERSION}")
[ -n "$HOST_TIMESTAMP" ] && HOST_ARGS+=("-ts=${HOST_TIMESTAMP}")

if [[ "${HOST_DEBUG}" == [Yy1]* ]]; then
  set -x
  ./run/host.bin "${HOST_ARGS[@]}" &
  { set +x; } 2>/dev/null
  echo
else
  ./run/host.bin "${HOST_ARGS[@]}" > /dev/null 2>&1 &
fi

# Configure serial ports

SERIAL_OPTS="\
	-serial mon:stdio \
	-device virtio-serial-pci,id=virtio-serial0,bus=pcie.0,addr=0x3 \
	-chardev pty,id=charserial0 \
	-device isa-serial,chardev=charserial0,id=serial0 \
	-chardev socket,id=charchannel0,host=127.0.0.1,port=12345,reconnect=10 \
	-device virtserialport,bus=virtio-serial0.0,nr=1,chardev=charchannel0,id=channel0,name=vchannel"
