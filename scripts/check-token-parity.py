#!/usr/bin/env python3
"""Verify apps/Compiler.HC's TOK_* defines match boot/seed/tok.h (NEO_TOKENS).

The C lexer derives its `token_type_t` enum from boot/seed/tok.h via the
NEO_TOKENS X-macro. apps/Compiler.HC cannot #include a C header, so it keeps a
hand-written matching `#define TOK_*` block. This check fails on any drift so the
two engines' token numbering can never diverge silently.

Exit 0 = identical, 1 = drift (details printed).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOK_H = ROOT / "boot" / "seed" / "tok.h"
HC = ROOT / "apps" / "Compiler.HC"


def parse_tok_h():
    text = TOK_H.read_text()
    return {name: int(val) for name, val in re.findall(r"X\(\s*(TOK_\w+)\s*,\s*(\d+)\s*\)", text)}


def parse_hc():
    text = HC.read_text()
    # Only the first (primary) define block matters; aliases reuse other names.
    return {name: int(val) for name, val in re.findall(r"#define\s+(TOK_\w+)\s+(\d+)\b", text)}


def main():
    ref = parse_tok_h()
    hc = parse_hc()
    if not ref:
        print("check-token-parity: no NEO_TOKENS entries found in boot/seed/tok.h")
        return 1

    problems = []
    for name, val in ref.items():
        if name not in hc:
            problems.append(f"missing in Compiler.HC: {name} = {val}")
        elif hc[name] != val:
            problems.append(f"value mismatch: {name} tok.h={val} Compiler.HC={hc[name]}")

    extra = sorted(set(hc) - set(ref))
    if extra:
        # Not a failure: Compiler.HC may define convenience aliases (TOK_NUM, ...).
        print(f"note: {len(extra)} non-primary TOK_* alias(es) in Compiler.HC (ignored): {extra}")

    if problems:
        print(f"check-token-parity: FAIL — {len(problems)} drift(s):")
        for p in problems:
            print(f"  - {p}")
        return 1

    print(f"check-token-parity: PASS — {len(ref)} tokens identical in tok.h and Compiler.HC")
    return 0


if __name__ == "__main__":
    sys.exit(main())
