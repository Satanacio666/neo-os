#!/usr/bin/env python3
"""Mede o boot do NeoOS em QEMU: tempo até cada marco e onde para.
Uso: neo-perf.py <rotulo> [args extras do QEMU...]
"""
import os, subprocess, sys, time, signal

ROOT = "/var/minis/workspace/neo-os"
label = sys.argv[1]
extra = sys.argv[2:]
log = "/tmp/perf-%s.log" % label
if os.path.exists(log):
    os.unlink(log)

base = [
    "qemu-system-aarch64",
    "-M", "virt,gic-version=2",
    "-accel", "tcg,thread=single,tb-size=512",
    "-cpu", "cortex-a72",
    "-smp", "4", "-m", "1024",
    "-bios", "/usr/share/AAVMF/QEMU_EFI.fd",
    "-device", "ramfb",
    "-device", "virtio-gpu-device,xres=1024,yres=768",
    "-device", "virtio-keyboard-device", "-device", "virtio-tablet-device",
    "-device", "usb-ehci", "-device", "usb-kbd", "-device", "usb-tablet",
    "-net", "none",
    "-drive", "file=%s/build/disk.img,format=raw,id=disk,if=none" % ROOT,
    "-device", "virtio-blk-pci,drive=disk,bootindex=0",
    "-drive", "file=%s/build/redsea.img,format=raw,id=redsea,if=none" % ROOT,
    "-device", "virtio-blk-device,drive=redsea",
    "-display", "none",
    "-serial", "file:" + log,
]

# remove pares default que o usuario sobrescreveu via extra
def strip_defaults(argv, keys):
    out, i = [], 0
    while i < len(argv):
        if argv[i] in keys:
            i += 2
            continue
        if argv[i].startswith("--") or (argv[i].startswith("-") and len(argv[i]) == 2):
            out.append(argv[i]); out.append(argv[i + 1]); i += 2
        else:
            out.append(argv[i]); i += 1
    return out


keys = {extra[i] for i in range(0, len(extra) - 1, 2) if extra[i].startswith("-")}
args = strip_defaults(base, keys) + extra

MILESTONES = [
    ("uefi-gop", "GOP FrameBufferBase"),
    ("kinit", "Compiling and Executing KernelInit.HC"),
    ("compiler-hc", "Compiler.HC compiled"),
    ("halplatform", "Compiling HalPlatform.HC"),
    ("crash", "Synchronous Exception"),
    ("shell", "DolDocShell active"),
    ("golden", "GOLDEN BOOT"),
    ("selftest", "SELFTEST"),
]

p = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
t0 = time.time()
seen = {}
deadline = t0 + 300
text = ""
while time.time() < deadline:
    time.sleep(0.4)
    try:
        text = open(log, errors="replace").read()
    except Exception:
        text = ""
    for name, needle in MILESTONES:
        if name not in seen and needle in text:
            seen[name] = time.time() - t0
    if "crash" in seen or "shell" in seen:
        break
    if p.poll() is not None:
        break

print("== %s ==" % label)
for name, _ in MILESTONES:
    if name in seen:
        print("   %-12s %6.1f s" % (name, seen[name]))
if not seen:
    print("   (nenhum marco)")
    print("   stderr:", (p.stderr.read(400).decode(errors="replace") if p.stderr else "")[:300])
print("   linhas no serial: %d" % text.count("\n"))
print("   ultimo: %s" % (text.strip().splitlines()[-1][:90] if text.strip() else "(vazio)"))
try:
    p.send_signal(signal.SIGKILL)
except Exception:
    pass
p.wait()
