#!/usr/bin/env python3
"""Boota o NeoOS e roda `selftest` in-guest pela UART (equivalente ao golden gate,
sem precisar do bridge em node). Também tira screendump do DolDocShell."""
import os, signal, socket, subprocess, sys, time

def find_firmware():
    """Acha o firmware UEFI AArch64 — o caminho muda por distro.

    Medido: Alpine tem em /usr/share/AAVMF/QEMU_EFI.fd; Debian/Ubuntu em
    /usr/share/qemu-efi-aarch64/QEMU_EFI.fd. Sem isso o QEMU não boota e o erro
    que aparece é "SHELL NAO APARECEU" (foi o que travou o CI no GitHub).
    """
    import os
    for p in (os.environ.get("NEO_QEMU_BIOS", ""),
              "/usr/share/AAVMF/QEMU_EFI.fd",
              "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd",
              "/usr/share/edk2/aarch64/QEMU_EFI.fd",
              "/usr/share/qemu/edk2-aarch64-code.fd"):
        if p and os.path.exists(p):
            return p
    raise SystemExit("firmware UEFI AArch64 nao encontrado (instale aavmf ou qemu-efi-aarch64)")


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UART = "/tmp/neo-uart.sock"
MON = "/tmp/neo-mon5.sock"
LOG = "/tmp/gate-serial.log"
SENTINEL = "<<<NEO-DONE:selftest>>>"

for pid in [p for p in os.listdir('/proc') if p.isdigit()]:
    try:
        if open('/proc/%s/cmdline' % pid, 'rb').read().startswith(b'qemu-system-aarch64'):
            os.kill(int(pid), signal.SIGKILL)
    except Exception:
        pass
time.sleep(2)
for f in (UART, MON, LOG):
    if os.path.exists(f):
        os.unlink(f)

args = ["qemu-system-aarch64", "-M", "virt,gic-version=2",
        "-accel", "tcg,thread=single,tb-size=512", "-cpu", "cortex-a72",
        "-smp", "4", "-m", "1024", "-bios", find_firmware(),
        "-device", "ramfb", "-device", "virtio-gpu-device,xres=1024,yres=768",
        "-device", "virtio-keyboard-device", "-device", "virtio-tablet-device",
        "-device", "usb-ehci", "-device", "usb-kbd", "-device", "usb-tablet",
        "-net", "none",
        "-drive", "file=%s/build/disk.img,format=raw,id=disk,if=none" % ROOT,
        "-device", "virtio-blk-pci,drive=disk,bootindex=0",
        "-drive", "file=%s/build/redsea.img,format=raw,id=redsea,if=none" % ROOT,
        "-device", "virtio-blk-device,drive=redsea",
        "-display", "none",
        "-chardev", "socket,id=uart0,path=%s,server=on,wait=off" % UART,
        "-serial", "chardev:uart0",
        "-monitor", "unix:%s,server=on,wait=off" % MON]

qemu = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
logf = open(LOG, "wb")
uart = None
for _ in range(60):
    time.sleep(1)
    if os.path.exists(UART):
        try:
            uart = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            uart.connect(UART)
            uart.settimeout(0.5)
            break
        except Exception:
            uart = None

t0 = time.time()
buf = b""
shell_at = None
while time.time() - t0 < 90:
    try:
        chunk = uart.recv(65536)
        if chunk:
            buf += chunk
            logf.write(chunk); logf.flush()
            if shell_at is None and b"DolDocShell active" in buf:
                shell_at = time.time() - t0
                break
    except socket.timeout:
        continue
    except Exception:
        break
print("shell ativo em: %.1fs" % shell_at if shell_at else "SHELL NAO APARECEU")

# screendump do DolDocShell
if os.path.exists(MON):
    m = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    m.settimeout(4)   # sem timeout o recv bloqueia para sempre (travou o CI no GitHub)
    m.connect(MON); time.sleep(0.5)
    try: m.recv(65536)
    except Exception: pass
    m.sendall(b"screendump /tmp/neos_shell.ppm\n")
    time.sleep(4)
    m.close()
    print("screendump:", os.path.getsize("/tmp/neos_shell.ppm") if os.path.exists("/tmp/neos_shell.ppm") else "falhou")

# roda o selftest in-guest
print(">>> enviando 'selftest' ...")
uart.sendall(b"selftest\n")
res = b""
t1 = time.time()
while time.time() - t1 < 240:
    try:
        chunk = uart.recv(65536)
        if chunk:
            res += chunk
            logf.write(chunk); logf.flush()
            if SENTINEL.encode() in res:
                break
    except socket.timeout:
        continue
    except Exception:
        break
logf.close()
print("selftest terminou em %.1fs, %d bytes" % (time.time() - t1, len(res)))
text = res.decode(errors="replace")
for line in text.splitlines():
    ls = line.strip()
    if any(k in ls for k in ("SELFTEST", "PARITY", "RENDER", "DETERMINISM", "CENSUS",
                             "PASS", "FAIL", "selftest", "NEO-DONE", "GOLDEN")):
        print("   ", ls[:120])
qemu.send_signal(signal.SIGTERM)
