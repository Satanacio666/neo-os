#!/usr/bin/env python3
import subprocess
import os
import sys
import time
import threading

def main():
    neo_dir = "/home/carlos/.gemini/antigravity/scratch/neo-os"
    disk_img = os.path.join(neo_dir, "build/disk.img")
    redsea_img = os.path.join(neo_dir, "build/redsea.img")
    qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

    # Ensure RedSea image has the latest HC code
    subprocess.run(["python3", "scripts/mkredsea.py", redsea_img, "apps/"], cwd=neo_dir, check=True)

    env = os.environ.copy()
    if "DISPLAY" not in env or not env["DISPLAY"]:
        env["DISPLAY"] = ":0.0"

    cmd = [
        "taskset", "-c", "0",
        "qemu-system-aarch64",
        "-M", "virt,gic-version=2",
        "-accel", "tcg,thread=single,tb-size=512",
        "-cpu", "cortex-a72",
        "-smp", "4",
        "-m", "1024",
        "-bios", qemu_bios,
        "-device", "ramfb",
        "-device", "virtio-gpu-device,xres=1024,yres=768",
        "-device", "virtio-keyboard-device",
        "-device", "virtio-tablet-device",
        "-device", "usb-ehci",
        "-device", "usb-kbd",
        "-device", "usb-tablet",
        "-net", "none",
        "-drive", f"file={disk_img},format=raw,id=disk,if=none",
        "-device", "virtio-blk-pci,drive=disk,bootindex=0",
        "-drive", f"file={redsea_img},format=raw,id=redsea,if=none",
        "-device", "virtio-blk-device,drive=redsea",
        "-display", "gtk,zoom-to-fit=on",
        "-serial", "stdio"
    ]

    print(f"[LAUNCHER] Starting NeoOS with GUI window on {env['DISPLAY']}...")
    proc = subprocess.Popen(
        cmd,
        cwd=neo_dir,
        env=env,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=False,
        bufsize=0
    )

    booted = threading.Event()

    def stdout_reader():
        while True:
            line = proc.stdout.readline()
            if not line:
                break
            try:
                dec = line.decode('utf-8', errors='replace')
                sys.stdout.write(dec)
                sys.stdout.flush()
                if "DolDocShell active" in dec:
                    booted.set()
            except Exception:
                pass

    t = threading.Thread(target=stdout_reader, daemon=True)
    t.start()

    print("[LAUNCHER] Waiting for cold boot into DolDocShell...")
    if booted.wait(timeout=45):
        print("\n[LAUNCHER] DolDocShell active! Automatically launching Master Showcase Document...")
        time.sleep(0.5)
        for ch in "showcase\n":
            proc.stdin.write(ch.encode('ascii'))
            proc.stdin.flush()
            time.sleep(0.03)
        print("[LAUNCHER] 'showcase' command submitted! Master Showcase Document is now live on screen.")
    else:
        print("[LAUNCHER] Timeout waiting for boot banner. Sending 'showcase' anyway...")
        try:
            proc.stdin.write(b"showcase\n")
            proc.stdin.flush()
        except Exception:
            pass

    # Keep running to maintain the live QEMU window
    try:
        proc.wait()
    except KeyboardInterrupt:
        print("[LAUNCHER] Terminating QEMU...")
        proc.terminate()

if __name__ == "__main__":
    main()
