#!/usr/bin/env python3
"""Decode the last NeoOS fault from the serial log + QEMU monitor.

Reads the guest exception dump (ELR_EL1/FAR_EL1/ESR_EL1), maps ELR to the
compiled .HC function that contains it (from the JIT compile map), and asks the
QEMU monitor to disassemble the instructions around the faulting PC.

Usage:
  scripts/crash-decode.py            # analyze current serial log
  scripts/crash-decode.py --induce   # force a null-deref, then analyze
"""
import argparse
import os
import re
import socket
import sys
import time

LOG = os.environ.get("NEO_SERIAL_LOG", "/tmp/neo-os-serial.log")
MON = os.environ.get("NEO_MON_SOCK", "/tmp/neo-os-mon.sock")
UART_IN = os.environ.get("NEO_UART_IN_SOCK", "/tmp/neo-os-uart-in.sock")

EC_TABLE = {
    0x00: "Unknown", 0x01: "Trapped WFI/WFE", 0x07: "SVE/SIMD/FP access",
    0x0E: "Illegal Execution state", 0x18: "Trapped MSR/MRS",
    0x20: "Instruction Abort (lower EL)", 0x21: "Instruction Abort (same EL)",
    0x22: "PC Alignment fault", 0x24: "Data Abort (lower EL)",
    0x25: "Data Abort (same EL)", 0x26: "SP Alignment fault",
    0x2C: "FP/SIMD exception", 0x3C: "BRK (breakpoint)",
}


def read_log():
    try:
        return open(LOG, "rb").read().decode("utf-8", "replace")
    except OSError:
        return ""


def last_of(pattern, text):
    m = None
    for m in re.finditer(pattern, text):
        pass
    return m.group(1) if m else None


def find_fault(text):
    elr = last_of(r"ELR_EL1[^\n]*?(0x[0-9A-Fa-f]+)", text)
    far = last_of(r"FAR_EL1[^\n]*?(0x[0-9A-Fa-f]+)", text)
    esr = last_of(r"ESR_EL1[^\n]*?(0x[0-9A-Fa-f]+)", text)
    if not elr:
        elr = last_of(r"Synchronous Exception at (0x[0-9A-Fa-f]+)", text)
    if not elr:
        elr = last_of(r"Last Fault PC:\s*(0x[0-9A-Fa-f]+)", text)
    return elr, far, esr


def parse_map(text):
    funcs = []
    for m in re.finditer(r"Compiled function '([^']+)' to RAM at (0x[0-9A-Fa-f]+) \((\d+) instrs", text):
        funcs.append((int(m.group(2), 16), int(m.group(3)) * 4, m.group(1)))
    funcs.sort()
    return funcs


def containing(funcs, addr):
    # Return (name, base, size, offset, inside) for the function range containing
    # addr, or the nearest preceding named function with inside=False.
    best = None
    for a, s, n in funcs:
        if a <= addr:
            best = (n, a, s, addr - a, addr < a + s)
        if a <= addr < a + s:
            return best
    return best


def monitor(cmd):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(MON)
        s.sendall((cmd + "\n").encode())
        time.sleep(0.4)
        s.settimeout(0.6)
        data = b""
        try:
            while True:
                d = s.recv(4096)
                if not d:
                    break
                data += d
        except socket.timeout:
            pass
        s.close()
        return data.decode("utf-8", "replace")
    except OSError as e:
        return f"(monitor unavailable: {e})"


def induce():
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(UART_IN)
        for ch in "*(U64*)0 = 42;\r":
            s.sendall(ch.encode())
            time.sleep(0.005)
        s.close()
        time.sleep(2)
    except OSError as e:
        print(f"could not induce crash: {e}", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--induce", action="store_true")
    args = ap.parse_args()
    if args.induce:
        induce()

    text = read_log()
    elr, far, esr = find_fault(text)
    print("=== NeoOS crash decode ===")
    if not elr:
        print("No fault found in the serial log.")
        return 1
    addr = int(elr, 16)
    print(f"ELR_EL1 (faulting PC) : {elr}")
    if esr:
        ec = (int(esr, 16) >> 26) & 0x3F
        print(f"ESR_EL1               : {esr}  -> EC 0x{ec:02X} ({EC_TABLE.get(ec, '?')})")
    if far:
        print(f"FAR_EL1 (fault addr)  : {far}")

    f = containing(parse_map(text), addr)
    if f:
        name, a, s, off, inside = f
        if inside:
            print(f"Faulting function     : {name}  (0x{a:X} + 0x{off:X}, size {s})")
        else:
            print("Faulting function     : <top-level / JIT scratch code — not a named function>")
            print(f"  nearest preceding   : {name} @ 0x{a:X} (size {s})")
    else:
        print("Faulting function     : <outside compiled .HC ranges>")

    print("\n--- disassembly around ELR (QEMU monitor) ---")
    out = monitor(f"xp /14i {elr}")
    lines = [l for l in out.splitlines() if re.match(r"^\s*0x[0-9a-f]+:", l)]
    print("\n".join(lines) if lines else "(no disassembly)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
