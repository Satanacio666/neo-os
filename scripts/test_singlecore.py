#!/usr/bin/env python3
import sys
import pexpect
import time

cmd = (
    "taskset -c 0 qemu-system-aarch64 -M virt,gic-version=2 "
    "-accel tcg,thread=single,tb-size=256 -cpu cortex-a72 -smp 1 -m 1024 "
    "-bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd -device ramfb "
    "-device virtio-gpu-device,xres=1024,yres=768 -device usb-ehci -device usb-tablet -net none "
    "-drive file=build/disk.img,format=raw,id=disk,if=none -device virtio-blk-pci,drive=disk,bootindex=0 "
    "-drive file=build/redsea.img,format=raw,id=redsea,if=none -device virtio-blk-device,drive=redsea "
    "-display none -serial stdio"
)

print("[TEST] Spawning single-core QEMU instance...")
child = pexpect.spawn(cmd, encoding='utf-8', timeout=40)
child.logfile = sys.stdout

try:
    print("[TEST] Waiting for NeoOS Shell prompt...")
    child.expect("Interactive Shell operational. Starting main loop...", timeout=20)
    time.sleep(1)

    print("\n[TEST] Sending 'jittest' command...")
    child.sendline("jittest")
    child.expect("ALL 10 JIT ADVANCED CONSTRUCTS VERIFIED 100% OPERATIONAL!", timeout=15)
    child.expect("neo:/>", timeout=10)
    print("\n[TEST] jittest completed successfully!")

    print("\n[TEST] Sending 'run HolyBenchmark.HC' command...")
    child.sendline("run HolyBenchmark.HC")
    child.expect("Total Benchmark Execution Time", timeout=15)
    child.expect("neo:/>", timeout=10)
    print("\n[TEST] HolyBenchmark.HC completed successfully!")

    print("\n[TEST] All single-core tests PASSED perfectly!")
except Exception as e:
    print(f"\n[TEST ERROR] {e}")
    sys.exit(1)
finally:
    child.close(force=True)
