import subprocess
import socket
import json
import time
import os
import threading

qmp_sock_path = "/tmp/qmp_neo_holyc.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
ppm_output = "/home/carlos/.gemini/antigravity/scratch/neo-os/phase1_live.ppm"
png_output = "/home/carlos/.gemini/antigravity/scratch/neo-os/phase1_live.png"

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

print("[TEST] Launching QEMU AArch64...")
proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=False, bufsize=0)

# Connect to QMP
s = None
for attempt in range(20):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(qmp_sock_path)
        break
    except Exception:
        time.sleep(0.3)

if not s:
    print("[TEST] Error: Could not connect to QMP")
    proc.kill()
    exit(1)

greeting = s.recv(1024)
s.sendall(b'{"execute": "qmp_capabilities"}\n')
res = s.recv(1024)
print("[TEST] QMP Connected.")

kernel_ready = False
log_lines = []

def reader_thread():
    global kernel_ready
    while True:
        line = proc.stdout.readline()
        if not line:
            break
        decoded = line.decode('utf-8', errors='replace')
        log_lines.append(decoded)
        print(f"[QEMU] {decoded.strip()}")
        if "Interactive Shell and Multitasking operational" in decoded:
            kernel_ready = True

t = threading.Thread(target=reader_thread, daemon=True)
t.start()

print("[TEST] Waiting for NeoOS kernel boot...")
start_t = time.time()
while not kernel_ready and (time.time() - start_t) < 25:
    time.sleep(0.2)

if not kernel_ready:
    print("[TEST] Timeout waiting for kernel ready!")
else:
    print("[TEST] >>> NeoOS Kernel Shell is live! Testing HolyC 2.0 Engine <<<")
    time.sleep(1.0)

    commands = [
        b"clear\n",
        # 1. Multi-argument function
        b"I64 add4(I64 a, I64 b, I64 c, I64 d) { return a + b + c + d; }\n",
        b"add4(10, 20, 30, 40);\n",
        # 2. Unary and shift operators
        b"(1 << 8) + (1024 >> 2);\n",
        b"-(~15);\n",
        b"!0 + !5;\n",
        # 3. Dynamic Lua table
        b"auto win = { width = 800, height = 600 };\n",
        b"win.width + win.height;\n",
        # 4. Struct definition & sizeof
        b"class Point { I64 x; I64 y; };\n",
        b"sizeof(Point);\n",
        b"Point pt;\n",
        b"pt.x = 42;\n",
        b"pt.y = 58;\n",
        b"pt.x + pt.y;\n",
        # 5. Format string statement (HolyC style)
        b"\"HolyC 2.0 Live! Score: %d, Result: %d\\n\", 999, pt.x + pt.y;\n"
    ]

    for c in commands:
        proc.stdin.write(c)
        proc.stdin.flush()
        time.sleep(0.5)

    time.sleep(1.5)

    # Take screenshot
    print("[TEST] Capturing framebuffer screenshot via QMP...")
    qmp_cmd = json.dumps({"execute": "screendump", "arguments": {"filename": ppm_output}}) + "\n"
    s.sendall(qmp_cmd.encode('utf-8'))
    resp = s.recv(2048)
    print(f"[TEST] Screendump response: {resp.decode('utf-8', errors='replace').strip()}")

    time.sleep(0.5)

    # Convert to PNG using Pillow
    if os.path.exists(ppm_output):
        from PIL import Image
        img = Image.open(ppm_output)
        img.save(png_output)
        print(f"[TEST] Saved screenshot to {png_output}")

s.close()
proc.kill()
print("[TEST] Done.")
