# NEXT STEPS — NeoOS P1 self-hosting push

> Canonical, current plan. Supersedes the older P0/P1 notes in this file. Read with
> `P1-DELEGATION.md` (the authoritative delegation spec), `SKILL.md`, `01-VERIFIED-TRUTH.md`
> and `P2-P6-MIGRATION-SPECS.md`.

## Current state (verified)

- **Golden gate PASS** with the self-hosting flip **OFF**; tree clean at commit `1a99159`
  (plus the docs commit `a937748`).
- The C JIT boots the whole OS: DolDoc shell, **32 subsystems banner**, 0 exceptions, 0 undefined,
  52/52 JIT golden cases (now 67 cases after Agent B's B3 edge-case expansion).
- **`Compiler.HC` compiles 19 modules with 0 heap corruption**; `RenderInit` runs; `FontMono`
  compiles. Boot reaches **Stage 5 (Math3D)**.
- The earlier `g_hc_local_count`→30836 / heap-corruption bug (compiling `Render.HC`) is **fixed**;
  do not regress the §6 fixes.

## The single blocker

**`apps/Math3D.HC` (496 lines) hangs `Compiler.HC`.**

The serial log shows `[KERNEL-INIT] Compiling Math3D.HC (… bytes)...` and then nothing — the hang is
inside `Compiler.HC` (lexer/parser/codegen), **not** in Math3D's own execution. Candidate constructs
to bisect (delegation §8):

- `F64` structs + `->` member access on struct pointers (`CVec3`/`CVec4`, `Math3D.HC:10-25`).
- `F64 m[16]` array member (`CMat4`, `Math3D.HC:23-25`; used `:267-411`).
- `(F64)k` cast expressions (`Math3D.HC:97,98,238,243`).
- `#define` macros.
- chained member arithmetic `a->y*b->z - a->z*b->y` (`Math3D.HC:56-58`).

Fix it with the proven recipe (delegation §5): reproduce minimally → bisect the source → instrument
`HcLexNext`/`HcParseStatement`/`HcParsePrimary`/`HcResolveLValue` to find the token where `g_hc_pos`
stops advancing → fix the general path (never special-case a module) → verify (minimal repro,
`CompilerSelfTest()` 7/7, `golden-boot.sh` PASS) → remove instrumentation → commit + bundle.

**Diagnose it without a full boot** with Agent B's harness:
`scripts/p1-flip-test.sh` (boots with the flip ON, waits for `Compiling <module>` lines, declares a
hang on serial silence, dumps the last module + `crash-decode.py`, then reverts the flip).

## P1 Definition of Done (exact — delegation §0)

P1 is DONE only when **all** of these hold:

1. `apps/KernelInit.HC` sets `g_hc_ready = 1` right after `Compiler.HC` loads and routes all later
   modules through `CompilerCompileAndRun` (the flip, §9).
2. `scripts/golden-boot.sh` prints `GOLDEN BOOT: PASS` **with the flip ON**.
3. `CompilerSelfTest();` (over UART) reports **7/7**.
4. All **34** modules compile+run under `Compiler.HC` with **0** synchronous exceptions, **0** heap
   corruption, **0** undefined identifiers.
5. `scripts/p1-parity.sh` shows both engines agree (same module set compiled, same key globals) for
   all 34 modules. *(Delegation §0/§1 call this `scripts/compile-parity.sh`; that file does not exist —
   Agent B's B2 delivers `scripts/p1-parity.sh`.)*
6. Stage-2 blob embedded in `boot/main.c`; `compiler/jit_arm64.c` + `lexer.c` + `table.c` retired
   (or provably dead) without breaking the gate.

## Critical path (in order — delegation §4)

1. **Fix the `Math3D.HC` hang** in `Compiler.HC` (current blocker).
2. **March the module tail** (§8) one module at a time — each exposes one more codegen/parser bug.
3. **Flip module-by-module**, running the golden gate after each.
4. **Parity harness** — both engines, all 34 modules, diff (`scripts/p1-parity.sh`).
5. **Stage-2 blob** — pre-compile `Compiler.HC`, embed in `boot/main.c`.
6. **Retire the C JIT** (`jit_arm64.c`/`lexer.c`/`table.c`) + dead `jit_run_self_tests`.

### Module tail (compile order — delegation §8)

- **Current blocker:** `Math3D.HC`.
- **Then, in order:** `RasterTile.HC`, `HolyGL.HC`, `Physics3D.HC`, `Gears3D.HC`, `Profiler.HC`,
  `PerfOverlay.HC`, `BenchCpu.HC`, `BenchReport.HC`, `Compositor.HC`, `DolDoc.HC`, `WM.HC`,
  `Shell.HC`, `ShaderEditor.HC`, `HolyBenchmark.HC`.
- **Already compiling under `Compiler.HC` (19):** HalPlatform, Timer, Gic, Exceptions, KHeap,
  Symbols, Compiler, Render, FontMono, FontVector, Sched, Smp, VirtioBlk, RedSea, Keyboard, Mouse,
  VirtioInput, VirtioGpu, GfxBackend.

## The flip (exact — delegation §9)

`apps/KernelInit.HC` today: `I64 g_hc_ready = 0;` (L9); `I64 res = jit_compile_and_run(kinit_load_buf);`
(L25); `jit_compile_and_run("DolDocShellEventLoop();");` (L104). Flip:

```c
// L25 region:
I64 res;
if (g_hc_ready) { res = CompilerCompileAndRun(kinit_load_buf); } else { res = jit_compile_and_run(kinit_load_buf); }
// after KInitLoad("Compiler.HC"); add:
g_hc_ready = 1;
```

Prefer flipping **one module at a time** to isolate the first break, then expand. Revert the flip to
green before committing unless the whole P1 DoD above is met. The uncommitted `hcrun` shell command
(`Shell.HC:707-723`) compiles a single file through `CompilerCompileAndRun` and is a faster,
edit-free alternative once it lands.

## Agent split (delegation §11/§12)

- **Agent A** — compiler critical path: edits `apps/*.HC`, `compiler/*`, `kernel/symbols/*`,
  `boot/*`; owns the VM/build; fixes Math3D, marches the tail, flips, retires the C JIT.
- **Agent B** — verification + migration specs: owns `docs/master/*`, `tests/jit_golden/*`, and new
  `scripts/p1-*.sh`; **no** `.HC`/`compiler`/`kernel`/`boot` edits, **no** VM.
  Delivered: `scripts/p1-flip-test.sh` (B1), `scripts/p1-parity.sh` (B2),
  `tests/jit_golden/cases.json` +15 edge cases (B3), `docs/master/P2-P6-MIGRATION-SPECS.md` (B4),
  this file (B5).

## Then the levels (P2–P6) — specs in `P2-P6-MIGRATION-SPECS.md`

- **P2 Bootstrap minimization:** C → `boot/main.c` + `boot/uefi` only; `GetMemoryMap`.
- **P3 Kernel:** one allocator/table/HAL; arm timer + register IRQ; real scheduler
  (`cpu_switch_context`); SMP queues; exception `x3`; **dedupe globals** (start with
  `g_kernel_booting`, redeclared in 14 files).
- **P4 Rendering:** `GfxDevice` (GfxBackend+VirtioGpu, fix truncated virtio lengths); one tiled NEON
  rasterizer (real Z/textures/SDF/shader VM) from Render+RasterTile+HolyGL; `Fonts.HC`.
- **P5 DolDoc:** CDoc/CTree + per-char attrs + full tag set; `$WIN$`/`$SPLIT$` dissolve WM; dissolve
  Compositor; delete char grid; fix `g_doc_dirty_mask`.
- **P6 Shell:** action executor over a CDoc; real command registry; break cycles; shell-as-CDoc.

## How to verify each step

`scripts/golden-boot.sh` green · `run Compiler.HC` self-test 7/7 · `scripts/p1-parity.sh` PASS ·
`scripts/audit-symbols.sh` clean · `scripts/run-jit-golden.py` all non-known pass · commit + bundle
under `flock -w 900 /tmp/neo-os-vm.lock`.

## Guardrails (do not violate)

C only for `boot/main.c` + `boot/uefi` · no unbounded compiler buffers (caps raise `g_hc_error`) ·
no JIT miscompiles / no module special-casing · no UI cycles (`DolDoc⇄Shell`, `WM⇄Shell`,
`WM⇄Compositor`, `DolDoc⇄Compositor` stay broken) · golden gate PASS after every committed change ·
never leave the tree red · persist after every green step (`git commit` + `git bundle`).
