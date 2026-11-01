#!/usr/bin/env python3
"""Run the golden JIT test battery against the live NeoOS guest over UART."""
import argparse
import json
import os
import re
import socket
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CASES = os.path.join(ROOT, "tests", "jit_golden", "cases.json")
IN_SOCK = os.environ.get("NEO_UART_IN_SOCK", "/tmp/neo-os-uart-in.sock")
LOG = os.environ.get("NEO_SERIAL_LOG", "/tmp/neo-os-serial.log")
# CAMADA 3: WAIT 2.5 s era curto para comandos LONGOS (definicoes de funcao/
# struct, 68-76 chars: fn_recursion_local, f64_local_array_assign,
# neg_global_redecl_overflow) — o guest ainda estava compilando quando o script
# desistia e lia got=None. 4.0 s + SETTLE 0.8 da' margem medida. NAO mascara: um
# caso que realmente falha devolve um valor ERRADO (got!=expect), nao None.
WAIT = float(os.environ.get("NEO_WAIT", "4.0"))
SETTLE = float(os.environ.get("NEO_SETTLE", "0.8"))
VALUE_RE = re.compile(r"-->\s*[^()\n]*\(0x([0-9A-Fa-f]+)\)")


def log_size():
    try:
        return os.path.getsize(LOG)
    except OSError:
        return 0


def read_from(offset):
    try:
        with open(LOG, "rb") as fh:
            fh.seek(offset)
            return fh.read().decode("utf-8", "replace")
    except OSError:
        return ""


# CAMADA 3 (01-11): 0.004 s entre caracteres saturava o bridge/UART e o guest
# perdia caracteres de comandos longos -> got=None FALSO (medido: f1_member_arr_var
# devolve 0x1E correto quando enviado com calma). 0.008 e' o ritmo medido estavel.
# 0.008 ainda saturava em LOTE (medido: 108/111). O PL011 tem FIFO de 16 B e o
# guest drena entre ticks do shell; 0.012 e' o ritmo medido estavel em sequencia.
CHAR_DELAY = float(os.environ.get("NEO_CHAR_DELAY", "0.012"))

def send(text):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(IN_SOCK)
    for ch in text:
        s.sendall(ch.encode())
        time.sleep(CHAR_DELAY)
    s.close()


def wait_for_shell(timeout=90):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if "DolDocShell active" in read_from(0):
            return True
        time.sleep(1)
    return False


def run_cmd(cmd):
    start = log_size()
    send(cmd + "\r")
    deadline = time.time() + WAIT
    last_len = -1
    stable = time.time()
    while time.time() < deadline:
        time.sleep(0.1)
        cur = log_size()
        if cur != last_len:
            last_len = cur
            stable = time.time()
        elif time.time() - stable > SETTLE:
            break
    return read_from(start)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json")
    ap.add_argument("--no-shell-wait", action="store_true")
    args = ap.parse_args()

    cases = json.load(open(CASES))["cases"]
    if not args.no_shell_wait and not wait_for_shell():
        print("ERROR: shell never became active (check the VM/UART bridge)", file=sys.stderr)
        return 2

    results = []
    passed = failed = known_fail = known_pass = 0
    for c in cases:
        # CAMADA 3: retry quando got=None. got=None significa que o guest NAO
        # respondeu com um valor -- a causa MEDIDA e' perda de caracteres na
        # entrada serial (comando truncado), nao o compilador. Um caso legitimo
        # nunca devolve None; entao reenviar e' correto, nao mascaramento.
        got_digits = None
        for attempt in range(5):
            last_out = ""
            for cmd in c["cmds"]:
                last_out = run_cmd(cmd)
            m = None
            for m in VALUE_RE.finditer(last_out):
                pass
            got_digits = m.group(1).upper() if m else None
            if got_digits is not None:
                break
            time.sleep(1.0)   # deixa o shell/bridge assentarem antes de reenviar
        expect_digits = c["expect"].upper().replace("0X", "")
        got = ("0x" + got_digits) if got_digits else None
        expect = "0x" + expect_digits
        ok = (got_digits is not None and got_digits == expect_digits)
        known = c.get("known", False)
        if known:
            status = "KNOWN-PASS" if ok else "known-fail"
            known_pass += ok
            known_fail += (not ok)
        else:
            status = "PASS" if ok else "FAIL"
            passed += ok
            failed += (not ok)
        results.append({"name": c["name"], "expect": expect, "got": got, "ok": ok, "known": known})
        flag = " " if ok else " <--"
        print(f"[{status:>10}] {c['name']:<24} expect={expect:<18} got={got}{flag}")

    total = passed + failed
    print(f"\n=== {passed}/{total} passed, {failed} failed | known: {known_fail} failing, {known_pass} passing ===")
    if args.json:
        json.dump({"passed": passed, "failed": failed, "known_fail": known_fail,
                   "known_pass": known_pass, "results": results}, open(args.json, "w"), indent=2)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
