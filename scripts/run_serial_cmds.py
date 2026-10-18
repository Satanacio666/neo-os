#!/usr/bin/env python3
# Usage: run_serial_cmds.py "cmd1" "cmd2" ...   (env WAIT=seconds per cmd)
import subprocess, threading, time, os, sys
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
cmd = ["taskset", "-c", "0", "qemu-system-aarch64", "-M", "virt",
       "-accel", "tcg,thread=single,tb-size=512", "-cpu", "cortex-a72",
       "-smp", "4", "-m", "1024", "-bios", "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd",
       "-device", "ramfb", "-device", "virtio-gpu-device,xres=1024,yres=768",
       "-drive", f"file={root}/build/disk.img,format=raw,id=bootdisk,if=none",
       "-device", "virtio-blk-pci,drive=bootdisk,bootindex=0",
       "-drive", f"file={root}/build/redsea.img,format=raw,id=redsea,if=none",
       "-device", "virtio-blk-device,drive=redsea",
       "-serial", "stdio", "-display", "none"]
proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT, bufsize=0)
logs = []
def reader():
    for line in iter(proc.stdout.readline, b""):
        s = line.decode("utf-8", "replace").rstrip()
        logs.append(s); print(s, flush=True)
threading.Thread(target=reader, daemon=True).start()
for _ in range(240):
    if any("DolDocShell active" in l for l in logs): break
    time.sleep(0.5)
else:
    print("[HARNESS] shell never came up"); proc.kill(); sys.exit(1)
time.sleep(1)
wait = float(os.environ.get("WAIT", "8"))
for c in sys.argv[1:]:
    print(f"[HARNESS] >>> {c}", flush=True)
    for ch in c + "\n":
        proc.stdin.write(ch.encode()); proc.stdin.flush(); time.sleep(0.01)
    time.sleep(wait)
proc.kill()
