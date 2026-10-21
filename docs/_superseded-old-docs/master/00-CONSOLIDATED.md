# NeoOS — Consolidated Master Plan (v2, re-elaborated, compiler-first)

> The single authoritative document. Consolidates the entire project: vision, history,
> audit, designs, decisions, **every priority**, methodology, and **everything missing**.
> Supersedes `04-plan.md` (which this re-elaborates) and the old `docs/*.md`.

---

## 0. Vision & end goals

1. **Self-hosting** — everything in HolyC; C only for the UEFI bootstrap (`boot/main.c` + `boot/uefi`).
2. **A perfect unified render pipeline** — HolyGL as an *API with backends* (soft NEON×SMP → GPU → remote), one tile pipeline, **no scalar fallback** (AArch64 mandates NEON).
3. **A real TempleOS-model DolDoc** — CDoc/CTree, per-char attributes, the full two-letter tag set, macros/forms/sprites/anchors/links/trees, **windows-as-documents**.
4. **A unified shell** — documents emit *Actions*; the shell executes; **no cycles**.
5. **One HolyGL-max benchmark** — 40 phases, real NEON/Gouraud/texture/Z/SDF.
6. **Run anything at max native performance** — porting ladder (native → recompiled → WASM → emulation) + `HolyPort` (SDL/raylib-like) + a C→HolyC / LLVM→HolyC toolchain.
7. **Scale down** — the same `Surface`/tile abstractions → an **MCU cluster** (future).
8. **No unnecessary C.**

---

## 1. Current state (green checkpoint)

- **Boot:** reaches `DolDocShell`; "ALL 32 HOLYC SUBSYSTEMS"; **0 exceptions**; **0 undefined** symbols.
- **Golden gate:** `scripts/golden-boot.sh` → **PASS**; **52/52** JIT tests.
- **Compiler (C JIT `jit_arm64.c`):** frame-based locals, `&function`, forward-struct two-pass, read-path late-binding, `#include`, inline `asm { … }`, block comments, unresolved-symbol diagnostic.
- **`Compiler.HC` (self-host target):** works for ints/arrays/structs/control-flow/function-pointers/`Main`; **no F64**.
- **C pruned** to 9 bootstrap `.c` (+ `boot/uefi`); orphans (`Lexer.HC`, `WasmJit.HC`) deleted.
- **Viewer + harness** working. **Persisted:** commit + `neo-os.bundle` + `neo-os-src.tar.gz` + `neo-os-docs/` in the project workspace.

---

## 2. History (chronological)

1. **Clone/run** — built, booted headless (32 subsystems), built the `/neo-os` browser viewer (VNC→SSE→canvas + UART panel).
2. **Compiler fix #1** — frame-based locals (recursion corruption: `f(5)` 5→15). Root cause: dormant frame machinery never wired up.
3. **C pruning** — deleted 23 dead `.c` + 24 orphan `.h`; empty dirs; other-arch CRTs; hardened Makefile.
4. **Deep audit + research** — 5 explorers over 51 `.HC` + 27 `.md`; Tavily research (TempleOS DolDoc spec, Zig, IMGUI).
5. **Execution (lost)** — L0 brace fix, L1.1 `&function`, L1.2 forward structs, L1.3 reorder, L1.4 diagnostic, harness.
6. **THE RESET** — sandbox wiped `/home/user/neo-os` + `/tmp` + toolchain; **project + viewer survived**.
7. **Recovery** — re-cloned baseline, reinstalled toolchain, re-applied **every** fix, verified golden gate PASS.
8. **Design brainstorm** — HolyGL-as-API; Unified Tile Pipeline; run-anything ladder; MCU cluster; new priority order.
9. **P0 done** — harness + **crash-decoder** + **screenshot-diff** + gdbstub flag.
10. **P1 progress** — C pruning, `#include`, orphan tokenizer removal, block comments, inline `asm`.
11. **Docs** — `docs/master/*` set + consolidated plan + tarball.

---

## 3. Audit (consolidated)

### 3.1 Bad practices
- **Cycles:** `DolDoc→Shell`, `WM→Shell`, `Shell→WM`, `WM↔Compositor`.
- **`Compiler.HC` dead at boot** (loaded, compiled, never called until `run`).
- **Parallel C/.HC modules** (kheap, symbols, virtio_blk, redsea, hal_platform) — two sources of truth.
- **Shadowed `.HC` allocator** (`KMalloc`/`KFree` never called).
- **Not actually pure HolyC** (`.HC` calls C: `doldoc_printf`, `kmalloc`, `memcpy`, `gfx_*`, `timer_*`).
- **Duplication:** 3 tokenizers (now 1 orphan removed), 4 rasterizers, 3 fonts, 2 damage systems, 2 presents, `StdLib≡Table` (unused), PascalCase+snake aliases, duplicate globals (`g_kernel_booting`×~20, GIC/timer bases, `top_print_doldoc`).
- **Correctness:** `&function`→0 (fixed); no forward structs (fixed); no `#include` (fixed); `g_doc_dirty_mask` `(1<<r)` undefined ≥31; fnptr params typed `U64`; `%d` for 64-bit ×~40; `g_widget_target` pointer smuggled via decimal text; **VirtioGpu truncated commands**; `timer_get_uptime_ms` undefined (fixed).
- **Dead work:** ~60 zero-caller fns; write-only tile map / `g_osc_mem_buf` / most of `CGfxBackendState`; cosmetic SMP-tiled/Gouraud; mock TrueType; Morphic halos print-only; fake WM FPS/"4 Cores"; uptime wraps at 999 s.
- **Docs:** claim nonexistent features (`jittest` 7/7 — true only after fix; auto-bench; `GetMemoryMap`; preemptive sched; SMP rendering; Lua); reference deleted C; doc-vs-doc conflicts (tile 16/32/64, phases 6/16/40, grid 6144/3072/16384, repo URL).

### 3.2 Typing
No implicit-int. But: `%d`×40 for 64-bit; `U64↔pointer` (Virtio*/KHeap); fnptr-as-`U64`; colors as `I64`; `int` truncation in the compiler; signature mismatches (`SmpSecondaryWorker(U32)`→`U64` slot; `TimerTick()` as `fn(data)`; `ExceptionsHandleSync` raw vector); `Compiler.HC` maps `F64`→int.

### 3.3 Forward refs / stubs
Working: forward calls + forward globals (SIC). Fixed: `&function`, forward structs, `#include`. Broken: forward fnptr *values*, `case` constants (compile-time). Runtime forward refs: `Keyboard→VirtioInputPoll`, `Mouse→VirtioInputPoll`, `Sched→SmpPrintDolDoc`, `Compositor→wm_set_dirty`/`doldoc_*`, `GfxBackend→gpu_config_open`. Stub emissions: `symbols_unresolved_trap`→0; 3 literal-0 sites in `jit_arm64.c`; `Compiler.HC` `blr` to 0. No TODO markers.

### 3.4 Every `.HC` classified
CORE: HalPlatform, Symbols, Sched, Smp, Timer, Exceptions, RedSea, KHeap(telemetry), Math3D, Shell. DRV: Gic, Keyboard, Mouse, VirtioInput, VirtioBlk, VirtioGpu. DOC/REN: DolDoc, WM, Render, GfxBackend, RasterTile, HolyGL, Gears3D, FontMono, FontVector, Compositor(merge), ShaderEditor. CMP: Compiler, TestJitP0. BENCH: HolyBenchmark(keep), Profiler, PerfOverlay, BenchCpu. DEAD: Lexer(deleted), WasmJit(deleted), Table, StdLib, Bench, HolyBenchmark3D, HolyGLTest. DEMO: calc, fact, SmpDemo, Editor, Filer, Top, Showcase, Menu.

---

## 4. Designs (consolidated)

- **DolDoc = the model.** Real TempleOS model (CDoc/CTree, per-char attrs, `TX CR SR CU TB CL PB PL LM RM HD FO ID FD/BD/FG/BG PT WW UL IV BK SX SY CM AN LK BT DA MA SP FI`). Everything is a CDoc; every node can carry an Action.
- **Shell = action executor + REPL.** Documents return Actions; shell executes; no cycles. Shell output *is* a CDoc.
- **WM = layout policy**; windows are documents (`$WIN`/`$SPLIT`); Compositor dissolves into Render.
- **HolyGL = API with backends** (soft/virtio/native/remote). **Unified Tile Pipeline:** tile job = universal unit; SIMD = kernel shape, SMP = core count, GPU = a provider; all at once; no fallback. One canvas/device/damage/present; bin-then-raster; real Z/textures/SDF/shader VM; deterministic per tile.
- **Self-hosting:** compiler as a document; boot as a document; DolDoc reference is a DolDoc.
- **Run anything:** porting ladder + `HolyPort` + C→HolyC. **Cluster:** `Surface` + `remote` provider; RISC-V backend; distributed docs; tile rendering across nodes.
- **Steal from:** Emacs, Oberon, HyperCard, Smalltalk Morphic, Self, Plan 9, Web, Shadertoy/SDF, Zig.

---

## 5. Decisions

1. Compiler endgame = **true self-hosting** (finish `Compiler.HC`, retire the C compiler).
2. Priority order = **compiler-first**, then pipeline, DolDoc, shell, benchmark, self-host-everything, future.
3. **No unnecessary C.**
4. HolyGL = **API with backends**.
5. **One Unified Tile Pipeline**; no scalar fallback.
6. DolDoc on the **real TempleOS model**; windows-as-documents.
7. Documents emit Actions; shell executes; break cycles.
8. Debug **manually + protocol-driven** (UART + QEMU) for every change.
9. **Persist** (commit + bundle) after every green step.

---

## 6. THE PRIORITIES (re-elaborated, compiler-first)

### P0 — Observability & Debug Harness ✅ COMPLETE
`run-viewer-vm.sh` (+ gdbstub flag), `uart-bridge.mjs`, `uart-repl.py`, `run-jit-golden.py` + `cases.json`, `golden-boot.sh`, `audit-symbols.sh`, **`crash-decode.py`**, **`screenshot-diff.py`**.

### P1 — THE COMPILER *(the root; do fully first)*
**P1.A — Complete `Compiler.HC` (self-hosting HolyC compiler).**
Working: ints, arithmetic/bitwise/compare, `if/for/while/do/switch`, arrays, structs (`.`/`->`), function pointers, `sizeof`, `Main` entry.
Gaps, ordered:
1. **F64 (floats)** — the #1 gap.
   - Lexer: float literals (`3.5`, `.5`, `1e10`) → `TOK_FLOAT` + IEEE-754 bits.
   - Codegen: FP regs D0–D7; `fadd/fsub/fmul/fdiv/fcmp/fmov`; `scvtf/fcvtzs`; FP literal pool.
   - Types: F64 params/returns/locals; FP comparisons/branches.
2. **Inline asm** in `Compiler.HC` (mirror `asm { … }`).
3. **Diagnostics** (`file:line`, type errors).
4. **Module test**: compile a real module (e.g. `Timer.HC`) with `Compiler.HC`; diff vs `jit_arm64.c`.
5. **Flip boot** to `Compiler.HC`; **retire `jit_arm64.c`/`lexer.c`/`table.c`.**
**P1.B — Retire the C bootstrap runtime** (kheap/symbols/hal_platform/virtio_blk/redsea) once `.HC` versions are boot-load-bearing.
**P1.C — Compiler cleanup**: unify to ONE `TOK_*` enum (C enum + `Compiler.HC` defines); complete the single tokenizer.

### P2 — Unified Tile Pipeline (HolyGL spine)
Tile job + provider interface + work-stealing scheduler; SIMD tile kernel (real Z-buffer, perspective-correct textures, SDF, fragment-shader VM); one canvas/device/damage/present; delete 4 rasterizers/3 fonts/2 damages; fix VirtioGpu command lengths; determinism test (1 vs N cores).

### P3 — DolDoc (real TempleOS model)
CDoc/CTree + per-char attributes; full two-letter tag set + flags/args; links-with-types, anchors, macros, forms, trees, word-wrap, cursor movement; reactive cells; RedSea persistence; **windows-as-documents**.

### P4 — Shell
Action protocol; command registry (replace the 300-line if/else); shell buffer as a CDoc; break all cycles; fold `top`/`edit`/`filer` in; delete those apps.

### P5 — Benchmark
Consolidate HolyBenchmark + HolyBenchmark3D + Bench + BenchReport into ONE 40-phase suite; real NEON/Gouraud/texture/Z-interp; SDF shadertoy phases; merge Profiler+PerfOverlay; `/BENCH_REPORT.TXT`; BenchCpu real SIMD + PMU.

### P6 — Self-hosting everything
Boot as a document; only `boot/main.c` + `boot/uefi` in C.

### P7 — Future
GPU provider (virtio-gpu 3D / native); `HolyPort` + C→HolyC toolchain; `Surface` + `remote` provider → **MCU cluster** (RISC-V backend + distributed runtime).

---

## 7. Methodology
Golden gate after every change (`golden-boot.sh`); manual UART (`uart-repl.py`) + QEMU monitor/VNC/gdbstub; `crash-decode.py` for faults; `audit-symbols.sh` for symbols; `screenshot-diff.py` for visual regressions. Persist after every green step.

---

## 8. Everything missing (the complete gap list)
**Compiler:** F64 in `Compiler.HC` (lexer+codegen); inline asm in `Compiler.HC`; diagnostics; module-compile parity; flip boot; retire C compiler; one `TOK_*` enum.
**Bootstrap C to retire:** kheap.c, symbols.c, hal_platform.c, virtio_blk.c, redsea.c.
**Pipeline:** tile job + providers + SIMD kernel + real Z/texture/SDF/shader; unify canvas/device/damage/present; delete duplicates; fix VirtioGpu.
**DolDoc:** CDoc/CTree; per-char attrs; full tag set; macros/forms/sprites/anchors/links/trees; reactive cells; persistence; windows-as-docs.
**Shell:** action protocol; registry; shell-as-doc; break cycles; fold apps.
**Benchmark:** consolidate + real NEON/Gouraud/texture/Z/SDF; merge profilers.
**Typing:** `%d`→`%lld`; fnptr types; duplicate globals; `g_doc_dirty_mask`.
**Dead code:** ~60 render fns; `Table`/`StdLib`/`Bench`/`HolyBenchmark3D`/`HolyGLTest`; write-only state.
**Demos to remove:** calc, fact, SmpDemo, Editor, Filer, Top, Showcase, Menu.
**Docs:** supersede old contradictory `.md`; correct README claims.
**Future:** GPU, HolyPort, C→HolyC, cluster.

---

## 9. Persistence & process
Work inside the persisted workspace or commit + bundle after every green step; never rely on `/tmp` or paths outside the project; re-verify with `golden-boot.sh`.
