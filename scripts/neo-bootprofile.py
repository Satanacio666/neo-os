#!/usr/bin/env python3
"""P2.1 — Perfil de boot do NeoOS: tempo por módulo HolyC.

O boot recompila 157 KB de HolyC + 34 módulos a cada inicialização, de forma
serial. Este perfil responde: *onde* está o custo, e portanto se o cache de JIT
no ESP (P2) compensa e o que ele precisa cobrir.

Boota o QEMU com a UART num socket, carimba cada linha com o instante de chegada
e produz a tabela `módulo -> ms`, além dos marcos do boot e do clock do cluster
grande (medição à prova de throttle, P0.3).

Uso: python3 scripts/neo-bootprofile.py [--timeout 300] [--raw /tmp/perfil-raw.txt]
"""
import os
import re
import select
import signal
import socket
import subprocess
import sys
import time

def find_firmware():
    """Acha o firmware UEFI AArch64 — o caminho muda por distro.

    Medido: Alpine tem em /usr/share/AAVMF/QEMU_EFI.fd; Debian/Ubuntu em
    /usr/share/qemu-efi-aarch64/QEMU_EFI.fd. Sem isso o QEMU não boota e o erro
    que aparece é "SHELL NAO APARECEU" (foi o que travou o CI no GitHub).
    """
    import os
    for p in (os.environ.get("NEO_QEMU_BIOS", ""),
              "/usr/share/AAVMF/QEMU_EFI.fd",
              "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd",
              "/usr/share/edk2/aarch64/QEMU_EFI.fd",
              "/usr/share/qemu/edk2-aarch64-code.fd"):
        if p and os.path.exists(p):
            return p
    raise SystemExit("firmware UEFI AArch64 nao encontrado (instale aavmf ou qemu-efi-aarch64)")


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UART = "/tmp/neo-profile-uart.sock"


def big_clock():
    try:
        cur = int(open("/sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq").read())
        mx = int(open("/sys/devices/system/cpu/cpu4/cpufreq/cpuinfo_max_freq").read())
        return cur, mx
    except Exception:
        return 0, 0


def clock_line(tag):
    cur, mx = big_clock()
    if not mx:
        return "clock %s: indisponível" % tag
    pct = 100.0 * cur / mx
    flag = "" if pct >= 80 else "   <-- THROTTLE: medicao NAO confiavel"
    return "clock %s: %.2f de %.2f GHz (%.0f%%)%s" % (tag, cur / 1e6, mx / 1e6, pct, flag)


def main():
    timeout = 300
    raw_path = "/tmp/perfil-raw.txt"
    argv = sys.argv[1:]
    for i, a in enumerate(argv):
        if a == "--timeout":
            timeout = int(argv[i + 1])
        if a == "--raw":
            raw_path = argv[i + 1]

    for pid in [p for p in os.listdir('/proc') if p.isdigit()]:
        try:
            if open('/proc/%s/cmdline' % pid, 'rb').read().startswith(b'qemu-system-aarch64'):
                os.kill(int(pid), signal.SIGKILL)
        except Exception:
            pass
    time.sleep(1.5)
    if os.path.exists(UART):
        os.unlink(UART)

    args = ["qemu-system-aarch64", "-M", "virt,gic-version=2",
            "-accel", "tcg,thread=single,tb-size=512", "-cpu", "cortex-a72",
            "-smp", "4", "-m", "1024", "-bios", find_firmware(),
            "-device", "ramfb", "-device", "virtio-gpu-device,xres=1024,yres=768",
            "-device", "virtio-keyboard-device", "-device", "virtio-tablet-device",
            "-device", "usb-ehci", "-device", "usb-kbd", "-device", "usb-tablet",
            "-net", "none",
            "-drive", "file=%s/build/disk.img,format=raw,id=disk,if=none" % ROOT,
            "-device", "virtio-blk-pci,drive=disk,bootindex=0",
            "-drive", "file=%s/build/redsea.img,format=raw,id=redsea,if=none" % ROOT,
            "-device", "virtio-blk-device,drive=redsea",
            "-display", "none",
            "-chardev", "socket,id=uart0,path=%s,server=on,wait=off" % UART,
            "-serial", "chardev:uart0"]

    qemu = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    uart = None
    t0 = time.time()
    while time.time() - t0 < 30:
        time.sleep(0.3)
        if os.path.exists(UART):
            try:
                uart = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                uart.connect(UART)
                uart.setblocking(False)
                break
            except Exception:
                uart = None
    if not uart:
        print("UART não conectou")
        qemu.send_signal(signal.SIGTERM)
        return 1

    # --- coleta com carimbo de tempo por linha ---
    stamp = time.time()
    lines = []          # (t, texto)
    pend = b""
    t_start = time.time()
    while time.time() - t_start < timeout:
        r, _, _ = select.select([uart], [], [], 0.05)
        if not r:
            continue
        try:
            chunk = uart.recv(65536)
        except Exception:
            continue
        if not chunk:
            break
        now = time.time() - t_start
        pend += chunk
        while b"\n" in pend:
            raw, pend = pend.split(b"\n", 1)
            txt = raw.decode(errors="replace").rstrip("\r").strip()
            if txt:
                lines.append((now, txt))
        if any("DolDocShell active" in t for _, t in lines):
            break
    qemu.send_signal(signal.SIGTERM)
    total = time.time() - t_start

    with open(raw_path, "w") as f:
        for t, txt in lines:
            f.write("%8.3f  %s\n" % (t, txt))

    # --- análise ---
    marcos = {
        "GOP FrameBufferBase": "firmware+UEFI pronto",
        "Compiling and Executing KernelInit.HC": "handover para HolyC",
        "ALL 34 HOLYC SUBSYSTEMS": "34 módulos compilados",
        "DolDocShell active": "shell ativa",
    }
    mod_start, mod_end = {}, {}
    re_start = re.compile(r"Compiling ([A-Za-z0-9_]+)\.HC \((\d+) bytes\)")
    re_end = re.compile(r"([A-Za-z0-9_]+)\.HC compiled, res = (-?\d+)")
    for t, txt in lines:
        m = re_start.search(txt)
        if m and m.group(1) not in mod_start:
            mod_start[m.group(1)] = (t, int(m.group(2)))
        m = re_end.search(txt)
        if m:
            mod_end[m.group(1)] = t

    ordem = sorted(mod_start.items(), key=lambda kv: kv[1][0])
    tabela = []
    for i, (nome, (t0m, tam)) in enumerate(ordem):
        t1m = mod_end.get(nome)
        if t1m is None:
            t1m = ordem[i + 1][1][0] if i + 1 < len(ordem) else total
        tabela.append((nome, tam, (t1m - t0m) * 1000.0))

    print("=" * 74)
    print("PERFIL DE BOOT — NeoOS (P2.1)")
    print("=" * 74)
    print(clock_line("inicio"))
    print(clock_line("fim"))
    print()
    print("MARCOS")
    for chave, rotulo in marcos.items():
        for t, txt in lines:
            if chave in txt:
                print("   %-28s %7.2f s   %s" % (rotulo, t, ""))
                break
    print("   %-28s %7.2f s   (fim da coleta)" % ("tempo total", total))
    print()

    soma = sum(d for _, _, d in tabela)
    print("MÓDULOS COMPILADOS NO BOOT (%d) — total %.2f s" % (len(tabela), soma / 1000.0))
    print("   %-24s %9s %9s %7s" % ("módulo", "bytes", "ms", "% do total"))
    for nome, tam, ms in sorted(tabela, key=lambda x: -x[2]):
        print("   %-24s %9d %9.1f %6.1f%%" % (nome, tam, ms, 100.0 * ms / soma if soma else 0))
    print()
    print("CONCLUSÃO P2.1")
    print("   soma dos módulos : %.2f s" % (soma / 1000.0))
    print("   boot total       : %.2f s" % total)
    print("   fatia dos módulos: %.0f%% do tempo total" % (100.0 * soma / 1000.0 / total))
    print("   raw com carimbos : %s" % raw_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
