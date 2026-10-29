#!/usr/bin/env python3
"""P0.4 — Guarda-Corpo do build contra o erro E4 (file_edit que TRUNCA).

Compara cada apps/*.HC (e .c seeds) com o tamanho e o delta de chaves { vs }
registrados no HEAD do git. Se qualquer arquivo encolheu mais que 20% ou mudou
o delta de chaves vs o HEAD, ABORTA com rc=1 antes de o build gerar imagem
corrompida (o sintoma classico do file_edit: '1 replacement' + 77 KB perdidos
+ chaves desbalanceadas + make all falsamente verde).

Uso: scripts/check-source-sanity.py   (chamado no inicio de make all)
"""
import os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def git_bytes_head(path):
    """Tamanho do arquivo no HEAD (git cat-file). None se nao houver."""
    try:
        out = subprocess.run(["git", "-C", ROOT, "cat-file", "-s", "HEAD:" + path],
                             capture_output=True, text=True, timeout=10)
        if out.returncode == 0:
            return int(out.stdout.strip())
    except Exception:
        pass
    return None

def git_blob_head(path):
    try:
        out = subprocess.run(["git", "-C", ROOT, "show", "HEAD:" + path],
                             capture_output=True, text=True, timeout=15)
        if out.returncode == 0:
            return out.stdout
    except Exception:
        pass
    return None

def check():
    fail = 0
    targets = []
    # todos os .HC em apps/ + os C seeds com guardas
    for d in ["apps"]:
        if not os.path.isdir(os.path.join(ROOT, d)):
            continue
        for fn in sorted(os.listdir(os.path.join(ROOT, d))):
            if fn.endswith(".HC"):
                targets.append(os.path.join(d, fn))
    for d in ["boot/seed", "boot/runtime"]:
        for fn in ["jit_arm64.c", "jitcache.c"]:
            p = os.path.join(d, fn)
            if os.path.exists(os.path.join(ROOT, p)):
                targets.append(p)

    for rel in targets:
        full = os.path.join(ROOT, rel)
        cur_size = os.path.getsize(full)
        head_size = git_bytes_head(rel)
        head_blob = git_blob_head(rel)

        # (a) tamanho: nunca < 80% do HEAD
        if head_size is not None and cur_size < int(head_size * 0.8):
            print(f"[SOURCE-SANITY] FAIL {rel}: {cur_size}B < 80% do HEAD ({head_size}B) — truncamento!")
            fail = 1
        # (b) delta de chaves == HEAD
        if head_blob is not None:
            cur = open(full, encoding="utf-8", errors="replace").read()
            head_delta = head_blob.count("{") - head_blob.count("}")
            cur_delta = cur.count("{") - cur.count("}")
            if cur_delta != head_delta:
                print(f"[SOURCE-SANITY] FAIL {rel}: delta {{}}-{{}} {head_delta}->{cur_delta} (chaves desbalanceadas vs HEAD)")
                fail = 1

    # summary
    if fail:
        print("[SOURCE-SANITY] ABORTADO — corrigir antes de gerar imagem (rc=1)")
        sys.exit(1)
    print(f"[SOURCE-SANITY] PASS ({len(targets)} arquivos: tamanho>=80% e chaves == HEAD)")

if __name__ == "__main__":
    check()