import subprocess
import socket
import json
import time
import os
import threading

qmp_sock_path = "/tmp/qmp_neo_shell.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
ppm_output = "/home/carlos/.gemini/antigravity/scratch/neo-os/interactive_shell.ppm"
png_output = "/home/carlos/.gemini/antigravity/scratch/neo-os/interactive_shell.png"

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

# Read stdout line by line until kernel starts
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
        print(f"[QEMU LOG] {decoded.strip()}")
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
    print("[TEST] >>> NeoOS Kernel Shell is live! <<<")
    time.sleep(1.0)

    commands = [
        b"clear\n",
        b"write sq.HC I64 sq(I64 x) { return x * x; } sq(12);\n",
        b"ls\n",
        b"cat sq.HC\n",
        b"run sq.HC\n",
        b"run fact.HC\n",
        b"factorial(6);\n",
        b"mouse 20 750 1\n"
    ]

    for c in commands:
        print(f"[TEST] Sending input: {c.decode('utf-8').strip()}")
        proc.stdin.write(c)
        proc.stdin.flush()
        time.sleep(0.6)

    time.sleep(1.5)

    print("[TEST] Dumping screen to PPM...")
    screendump_cmd = json.dumps({"execute": "screendump", "arguments": {"filename": ppm_output}}) + "\n"
    s.sendall(screendump_cmd.encode('utf-8'))
    res = s.recv(1024)
    print(f"[TEST] Screendump response: {res.decode('utf-8')}")

    time.sleep(0.5)
    if os.path.exists(ppm_output):
        try:
            from PIL import Image
            img = Image.open(ppm_output)
            img.save(png_output)
            print(f"[TEST] Successfully converted screendump to {png_output}")
        except Exception as e:
            print(f"[TEST] Conversion error: {e}")

try:
    s.sendall(b'{"execute": "quit"}\n')
    s.close()
except:
    pass

try:
    proc.stdin.close()
    proc.terminate()
    proc.wait(timeout=3)
except:
    proc.kill()

print("[TEST] Finished QEMU run.")
