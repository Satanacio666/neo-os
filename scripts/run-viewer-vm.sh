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
# CAMADA 1.3: permite bootar uma imagem de disco ALTERNATIVA (isolamento do
# p1-parity: patch de KernelInit.HC numa COPIA, nunca no build/disk.img oficial).
DISK_IMG=${NEO_DISK_IMG:-$BUILD/disk.img}
# P1.4: NEO_NO_GOP=1 => sem -device ramfb (servidor headless). A flag e' passada
# ao QEMU via expansao de shell (nao pode ficar no array com quotes simples).
if [ "${NEO_NO_GOP:-0}" = "1" ]; then NO_GOP_DEVICE=""; else NO_GOP_DEVICE="-device ramfb"; fi
QEMU_BIOS=${NEO_QEMU_BIOS:-/usr/share/qemu-efi-aarch64/QEMU_EFI.fd}

# P7.4 F4: TCG threading. Default single (deterministic, one host thread); set
# NEO_MTTCG=1 for MTTCG (one host thread per vCPU) to measure the *real* SMP
# wall-clock speed-up of the tiled back-end. Never combined with NEO_ICOUNT.
ACCEL_THREAD=single
if [ "${NEO_MTTCG:-0}" = "1" ]; then ACCEL_THREAD=multi; fi

QEMU_ARGS=(
  -M virt,gic-version=${NEO_GIC_VERSION:-2}
  -accel "tcg,${NEO_QEMU_ACCEL:-thread=${ACCEL_THREAD},tb-size=512}"
  -cpu "${NEO_QEMU_CPU:-cortex-a72}"
  -smp "${NEO_SMP:-4}"
  # P7.4 F1: deterministic measurement mode. `-icount shift=0,align=off,sleep=off`
  # drives the guest's virtual clock from the instruction count, so CNTVCT_EL0
  # (and therefore `renderbench`) measures WORK, not host wall-clock. Enable with
  # NEO_ICOUNT=1; two consecutive runs must agree to <0.1%. Never used for normal
  # runs (icount is slower).
  ${NEO_ICOUNT:+-icount}
  ${NEO_ICOUNT:+shift=0,align=off,sleep=off}
  # Dev default is 256 MB: NeoOS's working set is tiny (it sizes its heap/JIT pool from
  # the UEFI map), and QEMU's host RSS tracks the guest's *touched* RAM — so a smaller
  # guest means a smaller host footprint. Override with NEO_GUEST_MB for benchmarks.
  -m "${NEO_GUEST_MB:-256}"
  -bios "$QEMU_BIOS"
  ${NO_GOP_DEVICE}
  # VirtIO-GPU REMOVIDO (31/10): sem acesso a virtio neste ambiente de teste,
  # o caminho oficial de apresentacao e' o ramfb (escrita direta na VRAM), que
  # ja' era o UNICO que funcionava de fato (nao havia [VIRTIO-GPU] no log).
  # apps/GfxDevice.HC segue no codigo como implementacao DORMENTE (documentada),
  # a ser reativada quando houver ambiente com virtio. Reativar = descomentar.
  #-device virtio-gpu-device,xres=1024,yres=768
  -device virtio-keyboard-device
  -device virtio-tablet-device
  -device usb-ehci
  -device usb-kbd
  -device usb-tablet
  -net none
  -drive file="$DISK_IMG",format=raw,id=disk,if=none
  -device virtio-blk-pci,drive=disk,bootindex=0
  -drive file="$BUILD/redsea.img",format=raw,id=redsea,if=none
  -device virtio-blk-device,drive=redsea
  -display none
  -vnc "127.0.0.1:${VNC_DISPLAY}"
  -monitor "unix:${MONSOCK},server=on,wait=off"
  -chardev "socket,id=uart0,path=${UARTSOCK},server=on,wait=off"
  -serial chardev:uart0
)

# Optional gdbstub: NEO_DEBUG=1 starts QEMU halted with a gdb server on tcp::1234.
if [ "${NEO_DEBUG:-0}" = "1" ]; then QEMU_ARGS+=( -s -S ); fi

is_running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

case "${1:-start}" in
  start)
    if is_running; then echo "already running (pid $(cat "$PIDFILE"))"; exit 0; fi
    if [ ! -f "$DISK_IMG" ] || [ ! -f "$BUILD/redsea.img" ]; then
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
