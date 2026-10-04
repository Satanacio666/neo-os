#!/usr/bin/env python3
"""
interactive_uart_harness.py - Interactive UART Harness & Framebuffer Screenshot Tool
NeoOS AArch64 Ring 0 SASOS

Features:
- Character-by-character UART injection simulating manual user input and code pasting
- Multi-line HolyC snippet pasting into the live shell REPL
- High-fidelity QMP framebuffer screendump capture (PPM -> PNG)
- Step-by-step execution and automated validation across userland applications
"""

import os
import sys
import time
import socket
import json
import subprocess
from PIL import Image

QMP_SOCK = "/tmp/qmp_uart_harness.sock"
DISK_IMG = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
REDSEA_IMG = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
BIOS_PATH = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
SCREENSHOTS_DIR = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots"
ARTIFACTS_DIR = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe"

class UARTHarness:
    def __init__(self):
        self.proc = None
        self.qmp = None
        os.makedirs(SCREENSHOTS_DIR, exist_ok=True)
        os.makedirs(ARTIFACTS_DIR, exist_ok=True)
        if os.path.exists(QMP_SOCK):
            try: os.remove(QMP_SOCK)
            except: pass

    def start_qemu(self):
        cmd = [
            "taskset", "-c", "0",
            "qemu-system-aarch64",
            "-M", "virt,gic-version=2",
            "-accel", "tcg,thread=single,tb-size=256",
            "-cpu", "cortex-a72",
            "-smp", "1",
            "-m", "1024",
            "-bios", BIOS_PATH,
            "-device", "ramfb",
            "-device", "virtio-gpu-device,xres=1024,yres=768",
            "-device", "usb-ehci",
            "-device", "usb-tablet",
            "-net", "none",
            "-drive", f"file={DISK_IMG},format=raw,id=disk,if=none",
            "-device", "virtio-blk-pci,drive=disk,bootindex=0",
            "-drive", f"file={REDSEA_IMG},format=raw,id=redsea,if=none",
            "-device", "virtio-blk-device,drive=redsea",
            "-display", "none",
            "-serial", "stdio",
            "-qmp", f"unix:{QMP_SOCK},server,nowait"
        ]
        print("[HARNESS] Launching QEMU AArch64 (single-core, taskset -c 0)...")
        self.proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=False,
            bufsize=0
        )

        # Connect to QMP
        print("[HARNESS] Connecting to QMP socket...")
        for attempt in range(50):
            try:
                self.qmp = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.qmp.connect(QMP_SOCK)
                break
            except Exception:
                time.sleep(0.2)

        if not self.qmp:
            raise RuntimeError("Failed to connect to QMP socket!")

        self.qmp.recv(2048)
        self.qmp.sendall(b'{"execute": "qmp_capabilities"}\n')
        self.qmp.recv(2048)
        print("[HARNESS] QMP connection established and capabilities negotiated.")

    def read_until(self, target, timeout=25):
        start = time.time()
        buf = ""
        while time.time() - start < timeout:
            ch = self.proc.stdout.read(1)
            if not ch:
                time.sleep(0.01)
                continue
            decoded = ch.decode('latin-1', errors='replace')
            buf += decoded
            sys.stdout.write(decoded)
            sys.stdout.flush()
            if target in buf:
                return buf
        raise TimeoutError(f"Timed out waiting for target '{target}' in UART output. Accumulated buffer:\n{buf}")

    def type_chars(self, text, char_delay=0.01):
        """Injects characters one-by-one via UART serial simulating user typing."""
        for c in text:
            self.proc.stdin.write(c.encode('ascii', errors='replace'))
            self.proc.stdin.flush()
            time.sleep(char_delay)

    def paste_code(self, code_text):
        """Pastes a block of HolyC code character-by-character and hits Enter."""
        print(f"\n[HARNESS] Pasting code ({len(code_text)} chars)...")
        self.type_chars(code_text, char_delay=0.01)
        self.proc.stdin.write(b"\n")
        self.proc.stdin.flush()

    def send_command(self, cmd_text, wait_prompt=True, timeout=20):
        print(f"\n[HARNESS] Sending command: '{cmd_text}'")
        self.type_chars(cmd_text, char_delay=0.01)
        self.proc.stdin.write(b"\n")
        self.proc.stdin.flush()
        if wait_prompt:
            return self.read_until("neo:/>", timeout=timeout)
        return ""

    def capture_screenshot(self, name, description=""):
        ppm_path = f"/tmp/{name}.ppm"
        png_local = os.path.join(SCREENSHOTS_DIR, f"{name}.png")
        png_artifact = os.path.join(ARTIFACTS_DIR, f"{name}.png")

        print(f"\n[HARNESS] Capturing screendump: {name} ({description})...")
        time.sleep(0.6) # allow render/swap to finish
        payload = json.dumps({"execute": "screendump", "arguments": {"filename": ppm_path}})
        self.qmp.sendall(payload.encode('utf-8') + b"\n")
        self.qmp.recv(2048)
        time.sleep(0.2)

        if os.path.exists(ppm_path):
            img = Image.open(ppm_path)
            img.save(png_local)
            img.save(png_artifact)
            try: os.remove(ppm_path)
            except: pass
            print(f"[HARNESS] Screenshot successfully saved:")
            print(f"  Local   : {png_local}")
            print(f"  Artifact: {png_artifact}")
            return png_artifact
        else:
            print(f"[HARNESS ERROR] PPM file {ppm_path} was not created!")
            return None

    def close(self):
        print("\n[HARNESS] Shutting down QEMU...")
        try:
            if self.qmp:
                self.qmp.sendall(b'{"execute": "quit"}\n')
                self.qmp.close()
        except: pass
        if self.proc:
            self.proc.terminate()
            try: self.proc.wait(timeout=2)
            except: self.proc.kill()
        print("[HARNESS] Shutdown complete.")

def main():
    harness = UARTHarness()
    results = {}
    try:
        harness.start_qemu()

        # Step 1: Wait for boot to complete
        print("\n=======================================================")
        print("STAGE 1: System Boot & Interactive Shell Initialization")
        print("=======================================================")
        harness.read_until("Interactive Shell operational. Starting main loop...", timeout=30)
        time.sleep(1.0)
        results["step1"] = harness.capture_screenshot("step1_boot_shell", "Fresh Boot to Shell Prompt")

        # Step 2: Test character-by-character UART typing and code pasting in Shell REPL
        print("\n=======================================================")
        print("STAGE 2: Live UART Character Typing & HolyC Code Pasting")
        print("=======================================================")
        # Test 2a: Character-by-character UART typing of arithmetic expression
        print("[HARNESS] Typing arithmetic expression '10 + 4 * 8;' character-by-character...")
        harness.paste_code("10 + 4 * 8;")
        harness.read_until("--> 42 (0x2A)", timeout=10)
        harness.read_until("neo:/>", timeout=10)

        # Test 2b: Pasting HolyC function definition
        print("[HARNESS] Pasting HolyC function 'I64 sqr(I64 n) { return n * n; }'...")
        harness.paste_code("I64 sqr(I64 n) { return n * n; }")
        harness.read_until("Compiled function 'sqr'", timeout=10)
        harness.read_until("neo:/>", timeout=10)

        # Test 2c: Invoking the compiled function from REPL
        print("[HARNESS] Invoking compiled HolyC function 'sqr(9);'...")
        harness.paste_code("sqr(9);")
        harness.read_until("--> 81 (0x51)", timeout=10)
        harness.read_until("neo:/>", timeout=10)
        time.sleep(0.5)
        results["step2"] = harness.capture_screenshot("step2_uart_pasted_code", "UART Manual Character Injection & REPL")

        # Step 3: Pure HolyC Application Drawer
        print("\n=======================================================")
        print("STAGE 3: Pure HolyC App Drawer (Menu.HC)")
        print("=======================================================")
        harness.send_command("menu", wait_prompt=True, timeout=15)
        time.sleep(0.5)
        results["step3"] = harness.capture_screenshot("step3_menu_drawer", "Pure HolyC Application Hub")

        # Step 4: Pure HolyC CPU Compute Benchmark
        print("\n=======================================================")
        print("STAGE 4: HolyC CPU Benchmark Suite (HolyBenchmark.HC)")
        print("=======================================================")
        harness.send_command("run HolyBenchmark.HC", wait_prompt=True, timeout=25)
        time.sleep(0.5)
        results["step4"] = harness.capture_screenshot("step4_cpu_benchmark", "HolyBenchmark.HC CPU Compute Suite")

        # Step 5: Pure HolyC Sovereign L1-Tiled Pineda Edge Rasterizer
        print("\n=======================================================")
        print("STAGE 5: Sovereign L1-Tiled Pineda Edge Rasterizer (RasterTile.HC)")
        print("=======================================================")
        harness.send_command("run RasterTile.HC", wait_prompt=True, timeout=20)
        time.sleep(0.5)
        results["step5"] = harness.capture_screenshot("step5_raster_tile", "RasterTile.HC L1 Scratchpad Engine")

        # Step 6: Pure HolyC Analytical Quadratic Bézier Typography
        print("\n=======================================================")
        print("STAGE 6: Analytical Quadratic Bézier Typography (FontVector.HC)")
        print("=======================================================")
        harness.send_command("run FontVector.HC", wait_prompt=True, timeout=20)
        time.sleep(0.5)
        results["step6"] = harness.capture_screenshot("step6_vector_font", "FontVector.HC Analytical Bézier Engine")

        # Step 7: Pure HolyC 3D GLXGears Engine
        print("\n=======================================================")
        print("STAGE 7: Sovereign 3D GLXGears Engine (Gears.HC)")
        print("=======================================================")
        harness.send_command("gears", wait_prompt=True, timeout=15)
        print("[HARNESS] Allowing GLXGears to render 3D viewport and RTSS HUD for 3 seconds...")
        time.sleep(3.0)
        results["step7"] = harness.capture_screenshot("step7_gears_3d", "Gears.HC 3D Viewport with RTSS HUD")
        harness.send_command("stopbench", wait_prompt=True, timeout=10)

        # Step 8: Pure HolyC 3D Dynamics & Rigid Body Physics
        print("\n=======================================================")
        print("STAGE 8: 3D Dynamics & Rigid Body Physics (Physics3D.HC)")
        print("=======================================================")
        harness.send_command("physics", wait_prompt=True, timeout=15)
        print("[HARNESS] Allowing Physics simulation to run for 3 seconds...")
        time.sleep(3.0)
        results["step8"] = harness.capture_screenshot("step8_physics_3d", "Physics3D.HC Rigid Body Viewport")
        harness.send_command("stopbench", wait_prompt=True, timeout=10)

        # Step 9: Pure HolyC Unified 3D Benchmark Suite
        print("\n=======================================================")
        print("STAGE 9: Unified 3D Benchmark Suite (HolyBenchmark3D.HC)")
        print("=======================================================")
        harness.send_command("bench", wait_prompt=True, timeout=15)
        print("[HARNESS] Allowing HolyBenchmark3D viewport to render for 3 seconds...")
        time.sleep(3.0)
        results["step9"] = harness.capture_screenshot("step9_holybenchmark_3d", "HolyBenchmark3D.HC 3D Suite")
        harness.send_command("stopbench", wait_prompt=True, timeout=10)

        # Step 10: Pure HolyC Window Manager Inspector
        print("\n=======================================================")
        print("STAGE 10: Window Manager Inspector (WM.HC)")
        print("=======================================================")
        harness.send_command("run WM.HC", wait_prompt=True, timeout=15)
        time.sleep(0.5)
        results["step10"] = harness.capture_screenshot("step10_wm_inspector", "WM.HC Window Manager Inspector")

        print("\n=======================================================")
        print("ALL 10 STAGES EXECUTED AND CAPTURED SUCCESSFULLY!")
        print("=======================================================")
        for k, v in results.items():
            print(f"  {k}: {v}")

    except Exception as e:
        print(f"\n[FATAL HARNESS ERROR] {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        harness.close()

if __name__ == "__main__":
    main()
