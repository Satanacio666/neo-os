#!/usr/bin/env bash
# NeoOS viewer VM: exposes the guest framebuffer over VNC (127.0.0.1:5900),
# a QEMU monitor on a unix socket, and a bidirectional PL011 UART on a unix socket.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
PIDFILE=/tmp/neo-os-vm.pid
BRIDGEPIDFILE=/tmp/neo-os-bridge.pid
MONSOCK=/tmp/neo-os-mon.sock
UARTSOCK=/tmp/neo-os-uart.sock
UARTINSOCK=/tmp/neo-os-uart-in.sock
SERLOG=/tmp/neo-os-serial.log
VNC_DISPLAY=${NEO_VNC_DISPLAY:-0}
QEMU_BIOS=${NEO_QEMU_BIOS:-/usr/share/qemu-efi-aarch64/QEMU_EFI.fd}

QEMU_ARGS=(
  -M virt,gic-version=2
  -accel tcg,thread=single,tb-size=512
  -cpu cortex-a72
  -smp 4
  -m 1024
  -bios "$QEMU_BIOS"
  -device ramfb
  -device virtio-gpu-device,xres=1024,yres=768
  -device virtio-keyboard-device
  -device virtio-tablet-device
  -device usb-ehci
  -device usb-kbd
  -device usb-tablet
  -net none
  -drive file="$BUILD/disk.img",format=raw,id=disk,if=none
  -device virtio-blk-pci,drive=disk,bootindex=0
  -drive file="$BUILD/redsea.img",format=raw,id=redsea,if=none
  -device virtio-blk-device,drive=redsea
  -display none
  -vnc "127.0.0.1:${VNC_DISPLAY}"
  -monitor "unix:${MONSOCK},server=on,wait=off"
  -chardev "socket,id=uart0,path=${UARTSOCK},server=on,wait=off"
  -serial chardev:uart0
)

is_running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

case "${1:-start}" in
  start)
    if is_running; then echo "already running (pid $(cat "$PIDFILE"))"; exit 0; fi
    if [ ! -f "$BUILD/disk.img" ] || [ ! -f "$BUILD/redsea.img" ]; then
      echo "build images missing; run 'make all' in $ROOT" >&2; exit 1; fi
    rm -f "$MONSOCK" "$UARTSOCK" "$UARTINSOCK"
    : > "$SERLOG"
    nohup qemu-system-aarch64 "${QEMU_ARGS[@]}" >/tmp/neo-os-qemu.out 2>&1 &
    echo $! > "$PIDFILE"
    sleep 0.5
    NEO_UART_SOCK="$UARTSOCK" NEO_UART_IN_SOCK="$UARTINSOCK" NEO_SERIAL_LOG="$SERLOG" \
      nohup node "$ROOT/scripts/uart-bridge.mjs" >/tmp/neo-os-bridge.out 2>&1 &
    echo $! > "$BRIDGEPIDFILE"
    echo "started vm pid $(cat "$PIDFILE"), bridge pid $(cat "$BRIDGEPIDFILE")"
    echo "VNC 127.0.0.1:590$VNC_DISPLAY | monitor $MONSOCK | uart in $UARTINSOCK | log $SERLOG"
    ;;
  stop)
    if is_running; then kill "$(cat "$PIDFILE")" 2>/dev/null; sleep 1; fi
    if [ -f "$BRIDGEPIDFILE" ]; then kill "$(cat "$BRIDGEPIDFILE")" 2>/dev/null; fi
    pkill -f "qemu-system-aarch64.*neo-os-mon.sock" 2>/dev/null
    pkill -f "uart-bridge.mjs" 2>/dev/null
    rm -f "$PIDFILE" "$BRIDGEPIDFILE" "$UARTINSOCK"
    echo "stopped"
    ;;
  restart) "$0" stop; sleep 1; "$0" start ;;
  status) if is_running; then echo "running pid $(cat "$PIDFILE")"; else echo "not running"; fi ;;
  *) echo "usage: $0 {start|stop|restart|status}" >&2; exit 2 ;;
esac
