#!/usr/bin/env python3
"""Compare two NeoOS framebuffer screenshots and report the % of changed pixels.

Usage:
  scripts/screenshot-diff.py baseline.png current.png [--threshold 0.05]
  scripts/screenshot-diff.py --save-baseline baseline.png   # grab a fresh one via the viewer

Exit code: 0 if the difference is within the threshold, 1 if it exceeds it.
"""
import argparse
import base64
import json
import sys
import urllib.request

try:
    from PIL import Image, ImageChops
except ImportError:
    print("Pillow required: pip install pillow", file=sys.stderr)
    sys.exit(2)

VIEWER = "http://localhost:4000/api/neo-os/stream"


def grab(path):
    for line in urllib.request.urlopen(VIEWER, timeout=12):
        line = line.decode("utf-8", "replace")
        if line.startswith("data: "):
            obj = json.loads(line[6:])
            open(path, "wb").write(base64.b64decode(obj["png"]))
            return True
    return False


def diff(a, b):
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        print(f"size differs: {ia.size} vs {ib.size}")
        return 1.0
    d = ImageChops.difference(ia, ib).convert("L")
    changed = sum(1 for p in d.getdata() if p > 16)
    return changed / (ia.size[0] * ia.size[1])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("baseline", nargs="?")
    ap.add_argument("current", nargs="?")
    ap.add_argument("--threshold", type=float, default=0.05)
    ap.add_argument("--save-baseline", metavar="PATH")
    args = ap.parse_args()

    if args.save_baseline:
        ok = grab(args.save_baseline)
        print(("saved baseline " + args.save_baseline) if ok else "failed to grab")
        return 0 if ok else 1

    if not (args.baseline and args.current):
        ap.error("need baseline and current (or --save-baseline PATH)")

    frac = diff(args.baseline, args.current)
    status = "OK" if frac <= args.threshold else "CHANGED"
    print(f"screenshot diff: {frac*100:.2f}% pixels changed (threshold {args.threshold*100:.0f}%) -> {status}")
    return 0 if frac <= args.threshold else 1


if __name__ == "__main__":
    sys.exit(main())
