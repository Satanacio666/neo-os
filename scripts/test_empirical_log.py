import subprocess
import socket
import json
import time
import os
import threading

qmp_sock_path = "/tmp/qmp_neo_gears_log.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

ppm_gears = "/home/carlos/.gemini/antigravity/scratch/neo-os/gears_empirical_live.ppm"
png_gears = "/home/carlos/.gemini/antigravity/scratch/neo-os/gears_empirical_live.png"
art_gears = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/gears_empirical_live.png"
log_out = "/home/carlos/.gemini/antigravity/scratch/neo-os/GEARS_BENCHMARK.LOG"
art_log = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/GEARS_BENCHMARK.LOG"

if os.path.exists(qmp_sock_path):
    try: os.remove(qmp_sock_path)
    except: pass

cmd = [
    "qemu-system-aarch64",
    "-M", "virt",
    "-cpu", "cortex-a72",
    "-smp", "4",
    "-m", "1024",
    "-bios", qemu_bios,
    "-device", "ramfb",
    "-drive", f"file={disk_img},format=raw,id=bootdisk,if=none",
    "-device", "virtio-blk-pci,drive=bootdisk,bootindex=0",
    "-drive", f"file={redsea_img},format=raw,id=redsea,if=none",
    "-device", "virtio-blk-device,drive=redsea",
    "-serial", "stdio",
    "-display", "none",
    "-qmp", f"unix:{qmp_sock_path},server,nowait"
]

print("[TEST] Launching QEMU AArch64 for GLXGears Empirical Benchmark Logging...")
proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=False, bufsize=0)

s = None
for attempt in range(40):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(qmp_sock_path)
        break
    except Exception:
        time.sleep(0.3)

if not s:
    print("[ERROR] Failed to connect to QMP socket!")
    proc.kill()
    exit(1)

s.recv(1024)
s.sendall(b'{"execute": "qmp_capabilities"}\n')
s.recv(1024)

kernel_ready = False
captured_lines = []
log_capturing = False
log_lines = []

def reader_thread():
    global kernel_ready, log_capturing, log_lines
    while True:
        line = proc.stdout.readline()
        if not line: break
        decoded = line.decode('utf-8', errors='replace')
        captured_lines.append(decoded)
        print("[SERIAL]", decoded.strip())
        if "Interactive Shell and Multitasking operational" in decoded:
            kernel_ready = True
        if "EMPIRICAL HARDWARE" in decoded:
            log_capturing = True
        if log_capturing:
            log_lines.append(decoded)

t = threading.Thread(target=reader_thread, daemon=True)
t.start()

start_t = time.time()
while not kernel_ready and (time.time() - start_t) < 30:
    time.sleep(0.2)

if kernel_ready:
    # Gears auto-starts at boot; let it render undisturbed for 6 seconds
    print("[TEST] GLXGears is active. Rendering frames smoothly for 6 seconds...")
    time.sleep(6.0)

    # Screendump of active benchmark with RTSS HUD
    print("[TEST] Capturing active screendump...")
    s.sendall(json.dumps({"execute": "screendump", "arguments": {"filename": ppm_gears}}).encode('utf-8') + b"\n")
    s.recv(2048)
    time.sleep(0.5)

    # Now send gears_log to export the telemetry log
    print("[TEST] Sending 'gears_log' command to export empirical log...")
    proc.stdin.write(b"gears_log\n")
    proc.stdin.flush()
    time.sleep(2.0)

    # Read back the file via cat to confirm RedSea storage
    print("[TEST] Verifying RedSea file via 'cat GEARS_BENCHMARK.LOG'...")
    proc.stdin.write(b"cat GEARS_BENCHMARK.LOG\n")
    proc.stdin.flush()
    time.sleep(2.0)

    # Close gears cleanly (which also calls glxgears_export_log)
    print("[TEST] Sending 'closegears' command...")
    proc.stdin.write(b"closegears\n")
    proc.stdin.flush()
    time.sleep(1.0)

    # Convert PPM to PNG
    try:
        from PIL import Image
        if os.path.exists(ppm_gears):
            img = Image.open(ppm_gears)
            img.save(png_gears)
            img.save(art_gears)
            print(f"[TEST] Saved benchmark screendump:\n  {png_gears}\n  {art_gears}")
    except Exception as e:
        print(f"[WARN] PIL conversion failed: {e}")

    # Save log file if captured
    if log_lines:
        full_log_text = "".join(log_lines)
        with open(log_out, "w") as f:
            f.write(full_log_text)
        with open(art_log, "w") as f:
            f.write(full_log_text)
        print(f"[TEST] Saved empirical log file:\n  {log_out}\n  {art_log}")
    else:
        print("[WARN] Did not capture empirical log delimiter in serial output")

    print("[TEST] Empirical test sequence finished!")
else:
    print("[ERROR] Kernel boot timeout!")

try:
    s.sendall(b'{"execute": "quit"}\n')
    s.close()
except: pass

proc.terminate()
try: proc.wait(timeout=2)
except: proc.kill()
