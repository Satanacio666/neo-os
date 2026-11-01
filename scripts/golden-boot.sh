#!/usr/bin/env bash
# Golden boot regression gate for NeoOS.
#
# Boots once, asserts the boot-log invariants, then runs the ENTIRE regression
# battery with a SINGLE in-guest command (`selftest`, apps/SelfTest.HC) framed by
# a sentinel — no per-case UART round trips. Self-host stays a second command.
set -u
# P0-7.0 audit root fix: without pipefail a failing left-hand command in a pipeline
# (e.g. the census script) was masked by the trailing `tail -1`, so the gate could
# never fail on it. Fail the whole pipeline on any stage's non-zero exit.
set -o pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG=/tmp/neo-os-serial.log
SHOT="${1:-/tmp/golden-boot.png}"
SENTINEL='<<<NEO-DONE:selftest>>>'

fail=0
check() { if [ "$2" = "$3" ]; then echo "  [PASS] $1 = $3"; else echo "  [FAIL] $1: expected $2 got $3"; fail=1; fi; }

echo "== rebuilding =="
( cd "$ROOT" && make all >/tmp/golden-boot-build.log 2>&1 ) || { echo "BUILD FAILED"; exit 2; }

echo "== booting =="
"$ROOT/scripts/run-viewer-vm.sh" restart >/dev/null 2>&1
# P0.4/harness: boot medido em ~41s neste host (TCG aarch64). 40s era 1s curto
# demais -> o gate falhava 'shell active' mesmo com o boot perfeito. 60s de margem.
# CAMADA 2/01-11: com o SMP simetrico (o vigia rodando de verdade no core 1 em
# paralelo) o boot variou para ~60-70s em rodadas medidas -> margem subiu para
# 120s. Nao mascara nada: se o boot nao chegar em 120s, a falha e' real.
for i in $(seq 1 120); do grep -q 'DolDocShell active' "$LOG" 2>/dev/null && break; sleep 1; done

count() { rg -c "$1" "$LOG" 2>/dev/null || echo 0; }
check "shell active"        1 "$(count 'DolDocShell active')"
# P0.2: a frase tambem aparece como NOME DE FASE na timeline do BOOTSTAGE (uma
# vez a mais). Conta-se a LINHA do boot ([KERNEL-INIT] prefixo), nao a repeticao.
check "all 34 subsystems"   1 "$(count '\[KERNEL-INIT\] ✦ ALL 34 HOLYC SUBSYSTEMS')"
check "exceptions"          0 "$(count 'Synchronous Exception')"
check "undefined identifiers" 0 "$(count 'undefined identifier')"
check "compiler internal errors" 0 "$(count 'COMPILER.HC\] internal error')"
check "C JIT errors"        0 "$(count '\[JIT\] Error')"
check "unresolved forward refs" 0 "$(count 'unresolved reference')"

# ---------------------------------------------------------------------------
# P7.0: the peephole optimizer must have run on every module Compiler.HC compiles.
pline="$(grep -a '\[PEEPHOLE\] runs=' "$LOG" 2>/dev/null | tail -1)"
pruns="$(printf '%s' "$pline" | sed -n 's/.*runs=\([0-9]*\).*/\1/p')"
prt="$(printf '%s' "$pline" | sed -n 's/.*roundtrips=\([0-9]*\).*/\1/p')"
if [ "${pruns:-0}" -ge 30 ] && [ "${prt:-0}" -gt 0 ]; then
    echo "  [PASS] $pline (peephole optimizer active)"
else
    echo "  [FAIL] peephole: ${pline:-<none>} (want runs>=30 and roundtrips>0)"
    fail=1
fi
# RASTER: is printed by RasterTile.HC's boot self-check (Stage 5), i.e. in $LOG.
raline="$(grep -a 'RASTER: ' "$LOG" 2>/dev/null | tail -1)"
if printf '%s' "$raline" | grep -aq 'PASS'; then
    echo "  [PASS] $raline (single rasterizer boot check)"
else
    echo "  [FAIL] rasterizer: ${raline:-<none>} (want RASTER: PASS)"
    fail=1
fi
# P7.4 F1: the per-core raster context is private to RasterTile.HC. No other
# module may name g_rctx (it is threaded as an explicit argument instead).
if [ "$(grep -rl 'g_rctx' "$ROOT/apps" "$ROOT/boot" 2>/dev/null | grep -vc 'RasterTile.HC')" -eq 0 ]; then
    echo "  [PASS] g_rctx is private to RasterTile.HC"
else
    echo "  [FAIL] g_rctx referenced outside RasterTile.HC"
    grep -rl 'g_rctx' "$ROOT/apps" "$ROOT/boot" 2>/dev/null | grep -v 'RasterTile.HC'
    fail=1
fi

echo "== in-guest SELFTEST (one command, apps/SelfTest.HC) =="
out="$(python3 "$ROOT/scripts/neo_uart.py" --sentinel "$SENTINEL" --timeout 120 'selftest' 2>/dev/null || true)"
if ! printf '%s' "$out" | grep -aq "$SENTINEL"; then
    echo "  [FAIL] selftest did not finish (no sentinel — fault or hang)"
    grep -aE "internal error|EXC #" "$LOG" 2>/dev/null | tail -2
    fail=1
else
    line="$(printf '%s\n' "$out" | grep -a 'SELFTEST: ' | tail -1)"
    res="${line##*SELFTEST: }"; res="${res%% *}"       # "74/74"
    a="${res%%/*}"; b="${res##*/}"
    if [ -n "$a" ] && [ "$a" = "$b" ] && [ "$a" -ge 101 ] 2>/dev/null; then
        echo "  [PASS] SELFTEST = $res"
    else
        echo "  [FAIL] SELFTEST = ${res:-<none>} (want a==b and a>=101)"
        printf '%s\n' "$out" | grep -a '\[SELFTEST\] FAIL' | head -5
        fail=1
    fi
    pline="$(printf '%s\n' "$out" | grep -a 'engine parity:' | tail -1)"
    if printf '%s' "$pline" | grep -aq '0 diff'; then
        echo "  [PASS] $pline"
    else
        echo "  [FAIL] parity: ${pline:-<none>} (want 0 diff)"
        fail=1
    fi
    tline="$(printf '%s\n' "$out" | grep -a 'TWINS: ' | tail -1)"
    if printf '%s' "$tline" | grep -aq '5/5'; then
        echo "  [PASS] $tline (twin-liveness)"
    else
        echo "  [FAIL] twin-liveness: ${tline:-<none>} (want 5/5)"
        fail=1
    fi
    sline="$(printf '%s\n' "$out" | grep -a 'SYMS: ' | tail -1)"
    if printf '%s' "$sline" | grep -aq '0 unresolved'; then
        echo "  [PASS] $sline"
    else
        echo "  [FAIL] symbol audit: ${sline:-<none>} (want 0 unresolved)"
        fail=1
    fi
    hline="$(printf '%s\n' "$out" | grep -a 'HALCACHE: ' | tail -1)"
    if printf '%s' "$hline" | grep -aq 'PASS'; then
        echo "  [PASS] $hline (HalFlushCache coherency)"
    else
        echo "  [FAIL] hal-cache: ${hline:-<none>} (want PASS)"
        fail=1
    fi
    fline="$(printf '%s\n' "$out" | grep -a 'FSRT: ' | tail -1)"
    if printf '%s' "$fline" | grep -aq 'PASS'; then
        echo "  [PASS] $fline (RedSea.HC round-trip)"
    else
        echo "  [FAIL] fs round-trip: ${fline:-<none>} (want PASS)"
        fail=1
    fi
    kline="$(printf '%s\n' "$out" | grep -a 'KERNEL: ' | tail -1)"
    if printf '%s' "$kline" | grep -aq 'KERNEL:'; then
        echo "  [PASS] $kline"
    else
        echo "  [FAIL] kernel report: ${kline:-<none>} (want KERNEL: line)"
        fail=1
    fi
    tkline="$(printf '%s\n' "$out" | grep -a 'TICK: ' | tail -1)"
    if printf '%s' "$tkline" | grep -aq 'PASS'; then
        echo "  [PASS] $tkline (hardware timer IRQ)"
    else
        echo "  [FAIL] timer tick: ${tkline:-<none>} (want TICK: PASS)"
        fail=1
    fi
    scline="$(printf '%s\n' "$out" | grep -a 'SCHED: ' | tail -1)"
    if printf '%s' "$scline" | grep -aq 'PASS'; then
        echo "  [PASS] $scline (preemptive scheduling)"
    else
        echo "  [FAIL] preemption: ${scline:-<none>} (want SCHED: PASS)"
        fail=1
    fi
    bline="$(printf '%s\n' "$out" | grep -a 'BSOD: ' | tail -1)"
    if printf '%s' "$bline" | grep -aq 'PASS'; then
        echo "  [PASS] $bline (kernel-fault vs REPL boundary)"
    else
        echo "  [FAIL] bsod boundary: ${bline:-<none>} (want BSOD: PASS)"
        fail=1
    fi
    mline="$(printf '%s\n' "$out" | grep -a 'SMP: ' | tail -1)"
    if printf '%s' "$mline" | grep -aq 'PASS'; then
        echo "  [PASS] $mline (secondary-core dispatch)"
    else
        echo "  [FAIL] smp dispatch: ${mline:-<none>} (want SMP: PASS)"
        fail=1
    fi
    ovline="$(printf '%s\n' "$out" | grep -a 'SOVEREIGN: ' | tail -1)"
    if printf '%s' "$ovline" | grep -aq 'PASS'; then
        echo "  [PASS] $ovline (.HC owns kmalloc/kfree/symbols_*)"
    else
        echo "  [FAIL] sovereign handover: ${ovline:-<none>} (want SOVEREIGN: PASS)"
        fail=1
    fi
    rdline="$(printf '%s\n' "$out" | grep -a 'RENDER: ' | tail -1)"
    if printf '%s' "$rdline" | grep -aq 'PASS'; then
        echo "  [PASS] $rdline (golden-frame hash)"
    else
        echo "  [FAIL] render golden-frame: ${rdline:-<none>} (want RENDER: PASS)"
        fail=1
    fi
    psline="$(printf '%s\n' "$out" | grep -a 'PTRSCALE: ' | tail -1)"
    if printf '%s' "$psline" | grep -aq 'PASS'; then
        echo "  [PASS] $psline (global-pointer element width)"
    else
        echo "  [FAIL] pointer element width: ${psline:-<none>} (want PTRSCALE: PASS)"
        fail=1
    fi
    a2line="$(printf '%s\n' "$out" | grep -a 'ARRAY2D: ' | tail -1)"
    if printf '%s' "$a2line" | grep -aq 'PASS'; then
        echo "  [PASS] $a2line (multidimensional array indexing)"
    else
        echo "  [FAIL] 2D array indexing: ${a2line:-<none>} (want ARRAY2D: PASS)"
        fail=1
    fi
    ps2line="$(printf '%s\n' "$out" | grep -a 'PTRSCALE2: ' | tail -1)"
    if printf '%s' "$ps2line" | grep -aq 'PASS'; then
        echo "  [PASS] $ps2line (struct-member pointer element width)"
    else
        echo "  [FAIL] struct-member pointer width: ${ps2line:-<none>} (want PTRSCALE2: PASS)"
        fail=1
    fi
    hcline="$(printf '%s\n' "$out" | grep -a 'KHEAP: ' | tail -1)"
    if printf '%s' "$hcline" | grep -aq 'PASS'; then
        echo "  [PASS] $hcline (heap: split/coalesce, no overlap)"
    else
        echo "  [FAIL] heap stress: ${hcline:-<none>} (want KHEAP: PASS)"
        fail=1
    fi
    txline="$(printf '%s\n' "$out" | grep -a 'TEXTURE: ' | tail -1)"
    if printf '%s' "$txline" | grep -aq 'PASS'; then
        echo "  [PASS] $txline (textures: nearest/linear/perspective/blend)"
    else
        echo "  [FAIL] texture pipeline: ${txline:-<none>} (want TEXTURE: PASS)"
        fail=1
    fi
    glline="$(printf '%s\n' "$out" | grep -a 'GL: ' | tail -1)"
    if printf '%s' "$glline" | grep -aq 'PASS'; then
        echo "  [PASS] $glline (GL 1.3 matrix stacks + clear/colour/flush)"
    else
        echo "  [FAIL] holygl surface: ${glline:-<none>} (want GL: PASS)"
        fail=1
    fi
    clipline="$(printf '%s\n' "$out" | grep -a 'CLIP: ' | tail -1)"
    if printf '%s' "$clipline" | grep -aq 'PASS'; then
        echo "  [PASS] $clipline (near-plane Sutherland-Hodgman clipper)"
    else
        echo "  [FAIL] near-plane clipper: ${clipline:-<none>} (want CLIP: PASS)"
        fail=1
    fi
    nml="$(printf '%s\n' "$out" | grep -a 'NEONMEM: ' | tail -1)"
    if printf '%s' "$nml" | grep -aq 'PASS'; then
        echo "  [PASS] $nml (NEON fill/blit/blend bit-exact vs scalar)"
    else
        echo "  [FAIL] NEON memory kernels: ${nml:-<none>} (want NEONMEM: PASS)"
        fail=1
    fi
    tline="$(printf '%s\n' "$out" | grep -a 'TILE: ' | tail -1)"
    if printf '%s' "$tline" | grep -aq 'PASS'; then
        echo "  [PASS] $tline (tiled scene: pixel/Z-identical to immediate, no gaps)"
    else
        echo "  [FAIL] tiled scene: ${tline:-<none>} (want TILE: PASS)"
        fail=1
    fi
    m3line="$(printf '%s\n' "$out" | grep -a 'MATH3DPAR: ' | tail -1)"
    if printf '%s' "$m3line" | grep -aq 'PASS'; then
        echo "  [PASS] $m3line (parallel vertex transform == scalar reference)"
    else
        echo "  [FAIL] parallel vertex transform: ${m3line:-<none>} (want MATH3DPAR: PASS)"
        fail=1
    fi
    gcfline="$(printf '%s\n' "$out" | grep -a 'GPUCFG: ' | tail -1)"
    if printf '%s' "$gcfline" | grep -aq 'PASS'; then
        echo "  [PASS] $gcfline (5 GPU config knobs: read/write/clamp/restore + 1v4 tiles)"
    else
        echo "  [FAIL] GPU config plane: ${gcfline:-<none>} (want GPUCFG: PASS)"
        fail=1
    fi
    telline="$(printf '%s\n' "$out" | grep -a 'TELEMETRY: ' | tail -1)"
    if printf '%s' "$telline" | grep -aq 'PASS'; then
        echo "  [PASS] $telline (profiler+HUD merge, percentiles, spikes, PMU probe)"
    else
        echo "  [FAIL] telemetry: ${telline:-<none>} (want TELEMETRY: PASS)"
        fail=1
    fi
    fxline="$(printf '%s\n' "$out" | grep -a 'EFFECTS: ' | tail -1)"
    if printf '%s' "$fxline" | grep -aq 'PASS'; then
        echo "  [PASS] $fxline (harmonic springs + dual-Kawase NEON blur parity)"
    else
        echo "  [FAIL] effects: ${fxline:-<none>} (want EFFECTS: PASS)"
        fail=1
    fi
    lyline="$(printf '%s\n' "$out" | grep -a 'LAYOUT: ' | tail -1)"
    if printf '%s' "$lyline" | grep -aq 'PASS'; then
        echo "  [PASS] $lyline (Slate two-pass VBOX/HBOX/GRID/SPLIT layout)"
    else
        echo "  [FAIL] layout: ${lyline:-<none>} (want LAYOUT: PASS)"
        fail=1
    fi
    spline="$(printf '%s\n' "$out" | grep -a 'SPRING: ' | tail -1)"
    if printf '%s' "$spline" | grep -aq 'PASS'; then
        echo "  [PASS] $spline (universal harmonic physics: motions/transitions/overshoot)"
    else
        echo "  [FAIL] spring physics: ${spline:-<none>} (want SPRING: PASS)"
        fail=1
    fi
    glline="$(printf '%s\n' "$out" | grep -a 'GLASS: ' | tail -1)"
    if printf '%s' "$glline" | grep -aq 'PASS'; then
        echo "  [PASS] $glline (glass SDF + refraction + chromatic aberration + rim)"
    else
        echo "  [FAIL] glass material: ${glline:-<none>} (want GLASS: PASS)"
        fail=1
    fi
    trline="$(printf '%s\n' "$out" | grep -a 'TRANS: ' | tail -1)"
    if printf '%s' "$trline" | grep -aq 'PASS'; then
        echo "  [PASS] $trline (elastic transition suite: Fade/Pop/Drop/Slide/Fly/Zoom)"
    else
        echo "  [FAIL] transitions: ${trline:-<none>} (want TRANS: PASS)"
        fail=1
    fi
    fntline="$(printf '%s\n' "$out" | grep -a 'FONTS: ' | tail -1)"
    if printf '%s' "$fntline" | grep -aq 'PASS'; then
        echo "  [PASS] $fntline (fonts: bitmap + vector + AA atlas)"
    else
        echo "  [FAIL] fonts: ${fntline:-<none>} (want FONTS: PASS)"
        fail=1
    fi
    d3line="$(printf '%s\n' "$out" | grep -a '3D: ' | tail -1)"
    if printf '%s' "$d3line" | grep -aq 'PASS'; then
        echo "  [PASS] $d3line (3D transform + perspective + Z + lighting)"
    else
        echo "  [FAIL] 3D pipeline: ${d3line:-<none>} (want 3D: PASS)"
        fail=1
    fi
    gline="$(printf '%s\n' "$out" | grep -a '3D-GEARS: ' | tail -1)"
    if printf '%s' "$gline" | grep -aq 'PASS'; then
        echo "  [PASS] $gline (procedural involute gears mesh)"
    else
        echo "  [FAIL] 3D gears: ${gline:-<none>} (want 3D-GEARS: PASS)"
        fail=1
    fi
    shline="$(printf '%s\n' "$out" | grep -a 'SHADING: ' | tail -1)"
    if printf '%s' "$shline" | grep -aq 'PASS'; then
        echo "  [PASS] $shline (per-fragment Blinn-Phong)"
    else
        echo "  [FAIL] shading: ${shline:-<none>} (want SHADING: PASS)"
        fail=1
    fi
    svline="$(printf '%s\n' "$out" | grep -a 'SHADERVM: ' | tail -1)"
    if printf '%s' "$svline" | grep -aq 'PASS'; then
        echo "  [PASS] $svline (fragment-shader VM: NEON quad, derivatives, masking)"
    else
        echo "  [FAIL] shader vm: ${svline:-<none>} (want SHADERVM: PASS)"
        fail=1
    fi
    mshline="$(printf '%s\n' "$out" | grep -a 'MESH: ' | tail -1)"
    if printf '%s' "$mshline" | grep -aq 'PASS'; then
        echo "  [PASS] $mshline (OBJ mesh: parse + quad triangulation + render)"
    else
        echo "  [FAIL] mesh: ${mshline:-<none>} (want MESH: PASS)"
        fail=1
    fi
    ddline="$(printf '%s\n' "$out" | grep -a 'DOLDOC: ' | tail -1)"
    if printf '%s' "$ddline" | grep -aq 'PASS'; then
        echo "  [PASS] $ddline (CDoc/CTree + full two-letter tag set)"
    else
        echo "  [FAIL] doldoc: ${ddline:-<none>} (want DOLDOC: PASS)"
        fail=1
    fi
    shline="$(printf '%s\n' "$out" | grep -a 'SHELL: ' | tail -1)"
    if printf '%s' "$shline" | grep -aq 'PASS'; then
        echo "  [PASS] $shline (O(1) registry + action protocol)"
    else
        echo "  [FAIL] shell: ${shline:-<none>} (want SHELL: PASS)"
        fail=1
    fi
    hpline="$(printf '%s\n' "$out" | grep -a 'HEAPINT: ' | tail -1)"
    if printf '%s' "$hpline" | grep -aq 'PASS'; then
        echo "  [PASS] $hpline (no out-of-bounds heap writes across the whole battery)"
    else
        echo "  [FAIL] heap integrity: ${hpline:-<none>} (want HEAPINT: PASS)"
        fail=1
    fi
fi

# ---------------------------------------------------------------------------
# D5 (ONDA 4) — INVARIANTES DO SISTEMA IMUNOLOGICO (VERIFICADAS APOS o selftest).
# Antes desta adicao, uma regressao que acendesse o vigia (SYMBOL FAULT) ou
# corrompesse uma pilha (CANARY VIOLATION) PASSAVA em silencio: o gate nao olhava
# essas linhas. O selftest precisa ter RODADO antes, porque OVERFLOW/ERRCHAN/
# HEAPINT sao impressos por ele (colocar isto antes do selftest dava falso FAIL).
#
# CUIDADO MEDIDO: alguns destes sintomas sao PRODUZIDOS DE PROPOSITO pelos testes
# sinteticos (b3_healthlog_drop_counted, b9_watchdog_stall_detected). Contar a
# ocorrencia crua daria FALSO FAIL. A regra correta: contamos o EXCESSO sobre o
# Esperado pelo teste sintetico.
# ---------------------------------------------------------------------------
check "OVERFLOW invariant present"  1 "$(count 'OVERFLOW: PASS')"
check "ERRCHAN invariant present"   1 "$(count 'ERRCHAN: PASS')"
check "HEAPINT invariant present"   1 "$(count 'HEAPINT: PASS')"
# BURACOS DO GATE (estudo-de-deadcode N-1..N-10 + D-5): rotulos PRODUZIDOS a cada
# boot e nunca verificados. PARITY cai de 92/92 sem ninguem notar (a paridade dos
# motores C-JIT x Compiler.HC); PROFILER e' o teste que existia e nunca era chamado.
check "PARITY 92/92 agree"         1 "$(count 'PARITY: 92/92')"
# CAMADA 3 (IDEA-4): o funil unico Present() foi escolhido e anunciado. Sem esta
# linha, um backend quebrado/nao-inicializado passava em silencio.
check "PRESENT backend chosen"    1 "$(count '\[PRESENT\] backend=')"
# P0.2 (low-level): o watchdog de estagio publicou a timeline do boot e nao
# detectou travamento. Se o boot travar, a mensagem [BOOTSTAGE] BOOT LENTO diz
# exatamente ONDE — e o gate falha por ela (nao por silencio).
check "BOOTSTAGE timeline published" 1 "$(count '\[BOOTSTAGE\] timeline:')"
check "PROFILER invariant present" 1 "$(count 'PROFILER: PASS')"
# Efeitos/camadas declarados no boot: passam a ser verificados (antes: so' assumidos).
check "GLASS invariant present"    1 "$(count 'GLASS: PASS')"
check "TRANS invariant present"    1 "$(count 'TRANS: PASS')"
check "EFFECTS invariant present"  1 "$(count 'EFFECTS: PASS')"

# SYMBOL FAULT nao tem teste sintetico que o produza -> qualquer ocorrencia e'
# anomala (foi assim que o REPL do usuario acendeu 17 x num boot).
check "no SYMBOL FAULT"          0 "$(count '\[WATCHDOG\] SYMBOL FAULT')"
# CANARY VIOLATION idem (o B5 testa o CICLO, nao imprime a violacao no boot normal).
check "no CANARY VIOLATION"      0 "$(count 'CANARY VIOLATION')"
# TIMER DRIFT: o B11 testa a funcao PURA e nao imprime o alerta -> 0 esperado.
check "no TIMER DRIFT"           0 "$(count '\[TIMER\] DRIFT')"
# CAMADA 0.5 (IDEA-9): SOVEREIGN existe -> a fronteira C<->HolyC esta' provada
# (o HolyC assumiu kmalloc/kfree/symbols_*/uart). Sem esta linha, uma regressao no
# handover passava em silencio.
check "SOVEREIGN handover proven" 1 "$(count 'SOVEREIGN: PASS')"
# SMP real: os secundarios abrem IRQ e tomam tick (o contador e' impresso em SMPIRQ:).
check "SMPIRQ present"            1 "$(count 'SMPIRQ:')"

# Sintomas com teste sintetico: o numero observado nao pode EXCEDER o esperado.
hlog="$(count '\[HEALTHLOG\] DROP')"
b3="$(count 'b3_healthlog_drop_counted')"
if [ "${hlog:-0}" -le "${b3:-0}" ]; then
    echo "  [PASS] HEALTHLOG DROP dentro do esperado ($hlog <= $b3, teste B3)"
else
    echo "  [FAIL] HEALTHLOG DROP anormal: $hlog ocorrencias, so' $b3 do teste B3"; fail=1
fi
wstall="$(count '\[WATCHDOG\] STALLED')"
b9="$(count 'b9_watchdog_stall_detected')"
if [ "${wstall:-0}" -le "${b9:-0}" ]; then
    echo "  [PASS] WATCHDOG STALLED dentro do esperado ($wstall <= $b9, teste B9)"
else
    echo "  [FAIL] WATCHDOG STALLED anormal: $wstall ocorrencias, so' $b9 do teste B9"; fail=1
fi

echo "== .HC -> C runtime census =="
census_out="$("$ROOT/scripts/census-c-runtime.sh")"; census_rc=$?
printf '%s\n' "$census_out" | tail -1
if [ "$census_rc" -ne 0 ]; then
    echo "  [FAIL] census-c-runtime.sh rc=$census_rc (count changed / over budget)"
    fail=1
fi

echo "== compiler self-host =="
"$ROOT/scripts/self-host-test.sh" || fail=1

echo "== determinism (1 vs N cores) =="
detout="$("$ROOT/scripts/determinism-gate.sh" 2>&1)"; detrc=$?
printf '%s\n' "$detout" | grep -aE 'RENDER hash|DETERMINISM' || true
if [ "$detrc" -eq 0 ]; then
    echo "  [PASS] golden-frame hash is byte-identical on 1 vs N cores"
else
    echo "  [FAIL] determinism gate (rc=$detrc)"
    printf '%s\n' "$detout" | tail -3
    fail=1
fi

echo "== screenshot =="
rm -f "$SHOT"
# Take the framebuffer straight from QEMU's own monitor (no preview app / viewer
# needed — the Next.js preview server is intentionally disabled for RAM).
python3 - "$SHOT" <<'PY'
import socket, sys, os, time
shot = sys.argv[1]
mon = os.environ.get("NEO_MON_SOCK", "/tmp/neo-os-mon.sock")
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(8)
    s.connect(mon)
    time.sleep(0.3)
    s.sendall(("screendump " + shot + "\n").encode())
    time.sleep(1.5)
    s.close()
    if os.path.exists(shot) and os.path.getsize(shot) > 0:
        print("  saved", os.path.getsize(shot), "bytes ->", shot)
except Exception as e:
    print("  monitor screendump failed:", e)
PY
if [ -s "$SHOT" ]; then
    echo "  [PASS] screenshot captured"
else
    echo "  [FAIL] screenshot not captured"
    fail=1
fi

# BURACO FECHADO (01/11): o gate checava 'BSOD: PASS' (o panic DELIBERADO do
# SelfTestBsod) mas NAO checava se houvera um panic REAL. Um kernel que passa em
# tudo e morre DEPOIS do selftest era aprovado — medido: houve um boot em que o
# shell ativou, o corpus passou 173/173 e o kernel crashou (Instruction Abort,
# ELR=0x0) logo depois do prompt. Aqui se conta os panics REAIS: 'BSOD:KERNEL'
# aparece tanto no teste deliberado (que e' seguido de <<<EXC:RECOVERED>>>) quanto
# num panic fatal. A distincao: um panic fatal NAO tem recuperacao.
# Criterio: exatamente 1 ocorrencia de 'BSOD:KERNEL' (a deliberada) E ela deve ser
# seguida de recuperacao. Qualquer BSOD apos <<<NEO-DONE:selftest>>> e' FATAL.
bcount=$(count 'BSOD:KERNEL')
if [ "$bcount" -le 1 ]; then
    echo "  [PASS] no stray kernel panic (BSOD:KERNEL x$bcount, only the self-test one)"
else
    echo "  [FAIL] stray kernel panic: BSOD:KERNEL x$bcount (expected 1 = the self-test)"
    fail=1
fi
# E nenhum panic DEPOIS do corpus terminar (o shell deve continuar vivo).
aft="$(printf '%s\n' "$out" | sed -n '/NEO-DONE:selftest/,$p' | rg -c 'BSOD:KERNEL' 2>/dev/null | head -1)"
[ -z "$aft" ] && aft=0
if [ "$aft" -eq 0 ]; then
    echo "  [PASS] shell survives after the corpus (no panic post-selftest)"
else
    echo "  [FAIL] kernel panicked AFTER the corpus finished ($aft) — the shell did not survive"
    fail=1
fi

echo
if [ $fail -eq 0 ]; then echo "GOLDEN BOOT: PASS"; else echo "GOLDEN BOOT: FAIL"; fi
exit $fail
