#!/usr/bin/env python3
"""
capture_framebuffer.py - Pure Hardware Framebuffer Dump
Directly queries QEMU's internal virtual display memory via QEMU Monitor (HMP).
Zero interaction with host X11/Wayland windows. Zero desktop capture. Zero privacy exposure.
"""

import socket
import sys
import time
import os
from PIL import Image

OUT_PPM = "/tmp/neo_framebuffer.ppm"
OUT_PNG = sys.argv[1] if len(sys.argv) > 1 else "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/framebuffer_clean.png"
SOCK_PATH = "/tmp/qemu-hmp.sock"

def main():
    if not os.path.exists(SOCK_PATH):
        print(f"[ERROR] QEMU Monitor socket not found at {SOCK_PATH}")
        sys.exit(1)

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect(SOCK_PATH)
    except Exception as e:
        print(f"[ERROR] Failed to connect to {SOCK_PATH}: {e}")
        sys.exit(1)

    time.sleep(0.1)
    try:
        s.recv(4096)
    except socket.timeout:
        pass

    if os.path.exists(OUT_PPM):
        try:
            os.remove(OUT_PPM)
        except OSError:
            pass

    # Dump the active 1024x768 hardware framebuffer directly from display device ramfb0 head 0
    cmd = f"screendump {OUT_PPM} ramfb0 0\n"
    s.sendall(cmd.encode())
    time.sleep(0.4)

    if not os.path.exists(OUT_PPM):
        # Fallback to default display head if device ID not specified
        cmd_fallback = f"screendump {OUT_PPM}\n"
        s.sendall(cmd_fallback.encode())
        time.sleep(0.4)

    s.close()

    if os.path.exists(OUT_PPM):
        im = Image.open(OUT_PPM)
        im.save(OUT_PNG)
        print(f"[FRAMEBUFFER] Successfully dumped {im.size[0]}x{im.size[1]} raw GPU framebuffer to: {OUT_PNG}")
    else:
        print("[ERROR] screendump failed to generate PPM file")
        sys.exit(1)

if __name__ == "__main__":
    main()
