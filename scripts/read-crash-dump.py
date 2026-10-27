#!/usr/bin/env python3
"""
read-crash-dump.py — P7.2 — le o crash dump cru gravado pelo NeoOS.

O dump vai para setores CRUS no fim da midia, FORA da FAT (ver boot/runtime/
blockio.c e o alvo `disk:` do Makefile). Um caminho de falha nao pode alocar
nem montar estrutura de diretorio: se o panic vier de heap corrompido, um logger
FAT travaria e apagaria o rastro.

Uso:
    python3 scripts/read-crash-dump.py build/disk.img
    python3 scripts/read-crash-dump.py /dev/sdX          # pendrive montado no PC

Layout assumido (do Makefile):
    LBA 0 .. 131071        FAT32 (64 MB)  — invisivel para este script
    LBA 131072 ..          zona de crash (4 MB)
"""

import struct
import sys

CRASH_ZONE_LBA = 131072
SECTOR = 512
ZONE_OFFSET = CRASH_ZONE_LBA * SECTOR          # 64 MB
MAGIC = 0x4E454F21                             # "NEO!"

# magic, version, depois 9 u64, module_name[32], regs[31], text[128], stack[1024]
HDR = struct.Struct("<II" + "Q" * 9 + "32s" + "31Q" + "128s" + "1024s")

EC_NAMES = {
    0x00: "Unknown", 0x01: "WFI/WFE trap", 0x03: "SMC (AArch64)",
    0x07: "SMC (AArch32)", 0x0E: "Illegal Execution State",
    0x11: "SVC (AArch32)", 0x15: "SVC (AArch64)",
    0x18: "Trapped MSR/MRS (AArch64)", 0x20: "Instruction Abort (lower EL)",
    0x21: "Instruction Abort (same EL)", 0x22: "PC alignment fault",
    0x24: "Data Abort (lower EL)", 0x25: "Data Abort (same EL)",
    0x26: "SP alignment fault", 0x2C: "Trapped FP/SIMD",
    0x30: "Breakpoint (lower EL)", 0x31: "Breakpoint (same EL)",
    0x32: "Software Step (lower)", 0x33: "Software Step (same)",
    0x34: "Watchpoint (lower EL)", 0x35: "Watchpoint (same EL)",
    0x3C: "BRK instruction", 0x3F: "SError",
}

DFSC_NAMES = {
    0x04: "Translation fault, level 0", 0x05: "Translation fault, level 1",
    0x06: "Translation fault, level 2", 0x07: "Translation fault, level 3",
    0x09: "Access flag fault, level 1", 0x0B: "Access flag fault, level 2",
    0x0D: "Permission fault, level 1", 0x0F: "Permission fault, level 3",
    0x10: "Synchronous External Abort",
    0x14: "Synchronous External Abort (table walk, level 0)",
    0x21: "Alignment fault",
}


def hexdump(data, base=0, limit=256):
    out = []
    for off in range(0, min(len(data), limit), 16):
        chunk = data[off:off + 16]
        hexs = " ".join(f"{b:02x}" for b in chunk)
        text = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        out.append(f"  {base + off:08x}  {hexs:<47}  {text}")
    return "\n".join(out)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    path = sys.argv[1]
    try:
        with open(path, "rb") as f:
            f.seek(ZONE_OFFSET)
            blob = f.read(4096)
    except OSError as e:
        print(f"erro ao abrir {path}: {e}")
        return 1

    if len(blob) < HDR.size:
        print(f"zona de crash curta demais: {len(blob)} bytes (esperado >= {HDR.size})")
        print("a midia tem a zona reservada? veja o alvo `disk:` do Makefile.")
        return 1

    # ATENCAO: 'Q'*31 devolve 31 ITENS na tupla, nao uma lista. Fatiar e obrigatorio.
    fields = HDR.unpack_from(blob, 0)
    (magic, version, cntvct, esr, elr, far, spsr, sp, cel,
     heap, modidx, modname) = fields[:12]
    regs  = fields[12:43]      # 31 x u64 (x0..x30)
    text  = fields[43]
    stack = fields[44]

    if magic != MAGIC:
        print(f"sem crash dump nesta midia (magic=0x{magic:08X}, esperado 0x{MAGIC:08X}).")
        print("Se o NeoOS travou, o dump nao chegou a ser gravado.")
        return 2

    ec = (esr >> 26) & 0x3F
    iss = esr & 0x1FFFFFF
    dfsc = iss & 0x3F

    print("=" * 64)
    print("  NeoOS CRASH DUMP")
    print("=" * 64)
    print(f"  versao        : {version}")
    print(f"  CNTVCT_EL0    : {cntvct}")
    print(f"  CurrentEL     : EL{cel}")
    print()
    print(f"  ESR_EL1       : 0x{esr:016X}   EC=0x{ec:02X} {EC_NAMES.get(ec, '?')}")
    print(f"  ISS           : 0x{iss:08X}   DFSC/IFSC=0x{dfsc:02X} "
          f"{DFSC_NAMES.get(dfsc, '')}")
    print(f"  ELR_EL1 (PC)  : 0x{elr:016X}")
    print(f"  FAR_EL1 (addr): 0x{far:016X}")
    print(f"  SPSR_EL1      : 0x{spsr:016X}")
    print(f"  SP            : 0x{sp:016X}")
    print()
    print(f"  heap_base     : 0x{heap:016X}")
    if heap:
        delta = elr - heap
        inside = "DENTRO do heap (codigo JIT)" if 0 <= delta < (256 << 20) else "fora do heap"
        print(f"  PC - heap_base: 0x{delta:X}   -> {inside}")
    name = modname.split(b"\x00")[0].decode("ascii", "replace")
    print(f"  modulo ativo  : #{modidx} {name or '(nao registrado)'}")
    msg = text.split(b"\x00")[0].decode("ascii", "replace")
    if msg:
        print(f"  mensagem      : {msg}")
    print()
    print("  Pilha (1 KB a partir do SP):")
    print(hexdump(stack, base=sp, limit=256))
    print()
    print("  Registradores x0..x30 (do quadro capturado):")
    for i in range(0, 31, 4):
        row = "  ".join(f"x{i+j:<2}=0x{regs[i+j]:016X}" for j in range(4) if i + j < 31)
        print("   " + row)
    print("=" * 64)
    return 0


if __name__ == "__main__":
    sys.exit(main())
