#!/bin/bash

PIDFILE="/var/run/agent.pid"
SCRIPT="/usr/local/bin/agent.sh"

status() {

  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")"; then
    echo 'Service running'
    return 1
  fi

  return 0
}

start() {

  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")"; then
    echo 'Service already running'
    return 1
  fi

  echo 'Starting agent service...'
  chmod 666 /dev/ttyS0

  if [ ! -f "$SCRIPT" ]; then

    echo 'ERROR: Agent script not found!' > /dev/ttyS0

    URL="https://raw.githubusercontent.com/kroese/virtual-dsm/master/agent/agent.sh"

    if ! curl -sfk -m 10 -o "${SCRIPT}" "${URL}"; then
      rm -f "${SCRIPT}"
      return 1
    fi

    chmod 755 "${SCRIPT}"

  fi

  echo "-" > /var/lock/subsys/agent.sh
  "$SCRIPT" &> /dev/ttyS0 & echo $! > "$PIDFILE"

  return 0
}

stop() {

  if [ ! -f "$PIDFILE" ] || ! kill -0 "$(cat "$PIDFILE")"; then
    echo 'Service not running'
    return 1
  fi

  echo 'Stopping agent service...'

  chmod 666 /dev/ttyS0
  echo 'Stopping agent service...' > /dev/ttyS0

  kill -15 "$(cat "$PIDFILE")" && rm -f "$PIDFILE"
  rm -f /var/lock/subsys/agent.sh

  echo 'Service stopped'
  return 0
}

case "$1" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  status)
    status
    ;;
  restart)
    stop
    start
    ;;
  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
esac

