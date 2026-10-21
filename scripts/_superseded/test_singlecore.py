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
child = pexpect.spawn(cmd, encoding='latin-1', timeout=40)
child.logfile = sys.stdout

try:
    print("[TEST] Waiting for NeoOS Shell prompt...")
    child.expect("Interactive Shell operational. Starting main loop...", timeout=20)
    time.sleep(1)

    print("\n[TEST] Sending 'jittest' command...")
    child.sendline("jittest")
    child.expect("ALL 12 JIT ADVANCED CONSTRUCTS VERIFIED 100% OPERATIONAL!", timeout=15)
    child.expect("neo:/>", timeout=10)
    print("\n[TEST] jittest completed successfully!")

    print("\n[TEST] Sending 'run HolyBenchmark.HC' command...")
    child.sendline("run HolyBenchmark.HC")
    child.expect("Total Benchmark Execution Time", timeout=20)
    child.expect("neo:/>", timeout=10)
    print("\n[TEST] HolyBenchmark.HC completed successfully!")

    print("\n[TEST] Sending 'raster tile' command...")
    child.sendline("raster tile")
    child.expect("Unified L1 Tile NEON Engine", timeout=10)
    child.expect("neo:/>", timeout=10)
    print("\n[TEST] raster tile command verified successfully!")

    print("\n[TEST] Sending 'filer' command (pure HolyC)...")
    child.sendline("filer")
    child.expect("Filer.HC", timeout=15)
    child.expect("neo:/>", timeout=10)
    print("\n[TEST] filer command verified successfully!")

    print("\n[TEST] Sending 'run RasterTile.HC' (pure HolyC L1-Tiled Pineda engine)...")
    child.sendline("run RasterTile.HC")
    child.expect("RasterTile.HC", timeout=15)
    child.expect("Analytical edge equations exact", timeout=15)
    child.expect("neo:/>", timeout=10)
    print("\n[TEST] RasterTile.HC verified successfully!")

    print("\n[TEST] Sending 'run FontVector.HC' (pure HolyC Bézier Vector typography)...")
    child.sendline("run FontVector.HC")
    child.expect("FontVector.HC", timeout=15)
    child.expect("boundary conditions verified", timeout=15)
    child.expect("neo:/>", timeout=10)
    print("\n[TEST] FontVector.HC verified successfully!")

    print("\n[TEST] Sending 'run Menu.HC' (pure HolyC App Drawer)...")
    child.sendline("run Menu.HC")
    child.expect("Menu.HC", timeout=15)
    child.expect("neo:/>", timeout=10)
    print("\n[TEST] Menu.HC verified successfully!")

    print("\n[TEST] Sending 'run WM.HC' (pure HolyC Window Manager)...")
    child.sendline("run WM.HC")
    child.expect("WM.HC", timeout=15)
    child.expect("neo:/>", timeout=10)
    print("\n[TEST] WM.HC verified successfully!")

    print("\n[TEST] Sending 'run Shell.HC' (pure HolyC Shell Console)...")
    child.sendline("run Shell.HC")
    child.expect("Shell.HC", timeout=15)
    child.expect("neo:/>", timeout=10)
    print("\n[TEST] Shell.HC verified successfully!")

    print("\n[TEST] Sending 'gears' (pure HolyC 3D GLXGears)...")
    child.sendline("gears")
    child.expect("Gears.HC", timeout=15)
    child.expect("neo:/>", timeout=10)
    child.sendline("stopbench")
    child.expect("closed", timeout=10)
    child.expect("neo:/>", timeout=10)
    print("\n[TEST] gears verified successfully!")

    print("\n[TEST] Sending 'physics' (pure HolyC 3D Dynamics)...")
    child.sendline("physics")
    child.expect("Physics3D.HC", timeout=15)
    child.expect("neo:/>", timeout=10)
    child.sendline("stopbench")
    child.expect("closed", timeout=10)
    child.expect("neo:/>", timeout=10)
    print("\n[TEST] physics verified successfully!")

    print("\n[TEST] Sending 'bench' (pure HolyC Unified 3D Benchmark)...")
    child.sendline("bench")
    child.expect("HolyBenchmark3D.HC", timeout=15)
    child.expect("neo:/>", timeout=10)
    child.sendline("stopbench")
    child.expect("closed", timeout=10)
    child.expect("neo:/>", timeout=10)
    print("\n[TEST] bench verified successfully!")

    print("\n[TEST] All single-core tests PASSED perfectly!")
except Exception as e:
    print(f"\n[TEST ERROR] {e}")
    sys.exit(1)
finally:
    child.close(force=True)
