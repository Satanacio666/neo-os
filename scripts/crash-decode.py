#!/usr/bin/env python3
"""NeoOS fault forensics (P0.6 v2).

Decodes the last fault from the serial log: full ESR/ISS syndrome decode, maps
ELR_EL1 to the compiled .HC function (from the C seed "[JIT] ..." map and the
self-hosted compiler's "[HCF] name 0xaddr" map), and disassembles around the
faulting PC via the QEMU monitor.

Usage:
  scripts/crash-decode.py                # analyze the current serial log
  scripts/crash-decode.py --induce       # force a REPL (recoverable) null write
  scripts/crash-decode.py --gate         # assert recovery + kernel-panic-halt
"""
import argparse
import os
import re
import socket
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import neo_uart
except Exception:  # pragma: no cover
    neo_uart = None

LOG = os.environ.get("NEO_SERIAL_LOG", "/tmp/neo-os-serial.log")
MON = os.environ.get("NEO_MON_SOCK", "/tmp/neo-os-mon.sock")
UART_IN = os.environ.get("NEO_UART_IN_SOCK", "/tmp/neo-os-uart-in.sock")

MARK_RECOVERED = "<<<EXC:RECOVERED>>>"
MARK_KERNEL = "<<<BSOD:KERNEL>>>"
MARK_DOUBLE = "<<<BSOD:DOUBLE>>>"
MARK_FALLBACK = "<<<BSOD:FALLBACK>>>"

EC_TABLE = {
    0x00: "Unknown", 0x01: "Trapped WFI/WFE", 0x07: "SVE/SIMD/FP access",
    0x0E: "Illegal Execution state", 0x18: "Trapped MSR/MRS",
    0x20: "Instruction Abort (lower EL)", 0x21: "Instruction Abort (same EL)",
    0x22: "PC Alignment fault", 0x24: "Data Abort (lower EL)",
    0x25: "Data Abort (same EL)", 0x26: "SP Alignment fault",
    0x2C: "FP/SIMD exception", 0x3C: "BRK (breakpoint)",
}

# DFSC/IFSC fault-status codes (ARMv8 DDI 0487, ESR fault status field).
FAULT_STATUS = {
    0x00: "Address size fault, level 0", 0x01: "Address size fault, level 1",
    0x02: "Address size fault, level 2", 0x03: "Address size fault, level 3",
    0x04: "Translation fault, level 0", 0x05: "Translation fault, level 1",
    0x06: "Translation fault, level 2", 0x07: "Translation fault, level 3",
    0x09: "Access flag fault, level 1", 0x0A: "Access flag fault, level 2",
    0x0B: "Access flag fault, level 3",
    0x0D: "Permission fault, level 1", 0x0E: "Permission fault, level 2",
    0x0F: "Permission fault, level 3",
    0x10: "Synchronous external abort", 0x14: "Synchronous external abort, not on walk",
    0x21: "Alignment fault",
}


def read_log():
    try:
        return open(LOG, "rb").read().decode("utf-8", "replace")
    except OSError:
        return ""


def log_size():
    try:
        return os.path.getsize(LOG)
    except OSError:
        return 0


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


def decode_esr(esr_hex):
    esr = int(esr_hex, 16)
    ec = (esr >> 26) & 0x3F
    lines = [f"EC 0x{ec:02X} ({EC_TABLE.get(ec, '?')})"]
    if ec in (0x24, 0x25):  # Data Abort
        wnr = (esr >> 6) & 1
        fsc = esr & 0x3F
        lines.append(f"WnR = {wnr} ({'WRITE' if wnr else 'READ'})")
        lines.append(f"DFSC = 0x{fsc:02X} ({FAULT_STATUS.get(fsc, 'reserved')})")
        isv = (esr >> 24) & 1
        if isv:
            lines.append(f"ISV=1 SAS={(esr >> 22) & 3} SRT={(esr >> 16) & 0x1F} "
                         f"SF={(esr >> 15) & 1} AR={(esr >> 14) & 1}")
    elif ec in (0x20, 0x21):  # Instruction Abort
        fsc = esr & 0x3F
        lines.append(f"IFSC = 0x{fsc:02X} ({FAULT_STATUS.get(fsc, 'reserved')})")
    return lines


def parse_map(text):
    """Return [(addr, size, name)] from both the C seed and self-host maps."""
    funcs = []
    for m in re.finditer(r"\[JIT\] Compiled function '([^']+)' to RAM at (0x[0-9A-Fa-f]+) \((\d+) instrs, (\d+) bytes\)", text):
        funcs.append((int(m.group(2), 16), int(m.group(4)), m.group(1)))
    for m in re.finditer(r"\[HCF\] (\S+) (0x[0-9A-Fa-f]+)", text):
        funcs.append((int(m.group(2), 16), 0, m.group(1)))
    funcs.sort()
    return funcs


def containing(funcs, addr):
    """(name, base, size, offset, inside) for the range containing addr.
    Functions without a recorded size extend to the next function's base."""
    best = None
    for i, (a, s, n) in enumerate(funcs):
        end = a + s if s > 0 else (funcs[i + 1][0] if i + 1 < len(funcs) else a + 0x400)
        if a <= addr:
            best = (n, a, end - a, addr - a, addr < end)
        if a <= addr < end:
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


def send_raw(text):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(UART_IN)
    for ch in text:
        s.sendall(ch.encode())
        time.sleep(0.005)
    s.close()


def analyze(text):
    print("=== NeoOS crash decode ===")
    markers = []
    if MARK_RECOVERED in text:
        markers.append("RECOVERED")
    if MARK_KERNEL in text:
        markers.append(f"KERNEL x{text.count(MARK_KERNEL)}")
    if MARK_DOUBLE in text:
        markers.append(f"DOUBLE x{text.count(MARK_DOUBLE)}")
    if MARK_FALLBACK in text:
        markers.append("FALLBACK")
    if markers:
        print("Telemetry markers     : " + ", ".join(markers))

    elr, far, esr = find_fault(text)
    if not elr:
        print("No fault found in the serial log.")
        return 1
    addr = int(elr, 16)
    print(f"ELR_EL1 (faulting PC) : {elr}")
    if esr:
        for line in decode_esr(esr):
            print(f"ESR_EL1               : {esr}  -> {line}")
    if far:
        print(f"FAR_EL1 (fault addr)  : {far}")

    f = containing(parse_map(text), addr)
    if f:
        name, a, s, off, inside = f
        if inside:
            print(f"Faulting function     : {name}  (0x{a:X} + 0x{off:X}, size {s})")
        else:
            print("Faulting function     : <top-level / JIT scratch code>")
            print(f"  nearest preceding   : {name} @ 0x{a:X} (size {s})")
    else:
        print("Faulting function     : <outside compiled .HC ranges>")

    print("\n--- disassembly around ELR (QEMU monitor) ---")
    out = monitor(f"xp /14i {elr}")
    lines = [l for l in out.splitlines() if re.match(r"^\s*0x[0-9a-f]+:", l)]
    print("\n".join(lines) if lines else "(no disassembly)")
    return 0


def gate():
    """P0.6 panic gate: recovery must work; a kernel panic must render ONCE then halt."""
    if neo_uart is None:
        print("neo_uart unavailable; cannot run the gate.")
        return 2
    fails = []
    if not neo_uart.wait_for("DolDocShell active", 90):
        print("FAIL: guest did not boot")
        return 2

    # 1) Recoverable user fault (REPL): must recover, shell stays alive.
    out = neo_uart.run("*(U64*)0 = 42;", wait=4)
    if MARK_RECOVERED not in out:
        fails.append("recoverable REPL fault did not emit <<<EXC:RECOVERED>>>")
    out2 = neo_uart.run("2 + 2;", wait=3)
    if "--> 4" not in out2:
        fails.append("shell not responsive after recovery")

    # 2) Unrecoverable kernel fault: BSOD once, then the core halts (log silent).
    out3 = neo_uart.run("kpanic", wait=6)
    n_kernel = out3.count(MARK_KERNEL)
    if n_kernel != 1:
        fails.append(f"<<<BSOD:KERNEL>>> appeared {n_kernel}x (want exactly 1)")
    if "ROYAL BLUE KERNEL PANIC" not in out3:
        fails.append("BSOD screen text missing")
    time.sleep(1)
    before = log_size()
    try:
        send_raw("2 + 2;\r")
    except OSError:
        pass
    time.sleep(2)
    if log_size() != before:
        fails.append("core did not halt after panic (serial still active)")

    print("=== P0.6 panic gate ===")
    for f in fails:
        print(f"  [FAIL] {f}")
    if not fails:
        print("  [PASS] recovery ok; kernel panic rendered once and halted")
        print("PANIC GATE: PASS")
        return 0
    print("PANIC GATE: FAIL")
    return 1


def induce():
    try:
        send_raw("*(U64*)0 = 42;\r")
        time.sleep(2)
    except OSError as e:
        print(f"could not induce crash: {e}", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--induce", action="store_true")
    ap.add_argument("--gate", action="store_true")
    args = ap.parse_args()
    if args.gate:
        return gate()
    if args.induce:
        induce()
    return analyze(read_log())


if __name__ == "__main__":
    sys.exit(main())
