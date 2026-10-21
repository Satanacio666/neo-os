# NeoOS — Reality, Consolidation Matrix & Complete Tasklist (v3)

> Written as if new to the project, after mining the original 25 docs (`docs/*.md`),
> the directives (`AGENTS.md`, `SKILL.md`, `.agents/skills/...`), and the live code.
> Consolidates the *entire* earlier vision. Supersedes all prior plans.

---

## 0. Reality check — what this project IS

- **Target:** AArch64 bare-metal, Ring-0 (EL1), single address space (SASOS), UEFI-booted.
- **Substrate:** a small **C bootstrap** (`boot/main.c` + vendored `boot/uefi/*`) plus a **C JIT compiler** (`compiler/jit_arm64.c` + `lexer.c` + `table.c`) that compiles **36 HolyC `.HC` files** at boot into native machine code.
- **Runtime:** boots to a HolyC **DolDoc shell**; 32 subsystems; 0 exceptions; 0 undefined symbols.
- **Vision (from the docs):** everything in **HolyC** except the bootstrap; a **self-hosting compiler**; a **unified document/render continuum** where the shell, window manager, and compositor are *dissolved into DolDoc*; a **HolyGL** graphics engine (2D+3D, NEON tiled raster); a single **HolyGL-max benchmark**.
- **Current compiler truth:** the **C JIT** compiles everything today. **`Compiler.HC`** (the Stage-2 self-host target) is now feature-complete for **ints, arrays, structs, pointers, function pointers, control flow, F64 (literals/locals/params/returns/arithmetic/comparisons/conversions), and inline `asm{}`** — but it is **not hardened** (unbounded fixed buffers) and **crashes on large modules** (Render.HC), so it cannot yet compile the whole OS.

---

## 1. Systems inventory (live files + responsibility)

| System | Files (live) | Responsibility |
|---|---|---|
| **Bootstrap C** | `boot/main.c`, `boot/uefi/*` | UEFI entry, GOP, memory map, seeds C symbols, loads KernelInit.HC |
| **Compiler** | `compiler/jit_arm64.c`, `lexer.c`, `table.c`; `apps/Compiler.HC`, `apps/TestJitP0.HC` | JIT compiler (C) + Stage-2 self-host compiler (HolyC) |
| **Kernel core** | `HalPlatform.HC`, `KHeap.HC`, `Symbols.HC`, `Sched.HC`, `Smp.HC`, `Gic.HC`, `Timer.HC`, `Exceptions.HC` | HAL, heap, symbols, scheduler, SMP, interrupts, timer, faults |
| **Drivers** | `VirtioBlk.HC`, `RedSea.HC`, `Keyboard.HC`, `Mouse.HC`, `VirtioInput.HC`, `VirtioGpu.HC` | storage, FS, input, GPU |
| **Rendering** | `Render.HC`, `GfxBackend.HC`, `RasterTile.HC`, `HolyGL.HC`, `Math3D.HC`, `Physics3D.HC`, `Gears3D.HC`, `FontMono.HC`, `FontVector.HC`, `Compositor.HC` | canvas, device, raster, 3D, math, fonts, damage/theme |
| **Documents/UI** | `DolDoc.HC`, `WM.HC`, `Shell.HC`, `ShaderEditor.HC` | document model, windows, shell, shader IDE |
| **Benchmark** | `HolyBenchmark.HC`, `BenchCpu.HC`, `BenchReport.HC`, `Profiler.HC`, `PerfOverlay.HC` | benchmark + telemetry |
| **Boot orchestration** | `KernelInit.HC` | topological load of all modules |

---

## 2. Consolidation Matrix (per system) — from the docs, reconciled with code

### 2.1 DELETE (dead/duplicate) — *already done in this project*
- `apps/Table.HC` (dup of `StdLib.HC`), `apps/StdLib.HC` (unused), `apps/Lexer.HC` (3rd tokenizer), `apps/WasmJit.HC` (toy), `apps/Bench.HC`, `apps/HolyBenchmark3D.HC`, `apps/HolyGLTest.HC`.
- Demos: `apps/Showcase.HC`, `Menu.HC`, `Top.HC`, `calc.HC`, `fact.HC`, `Filer.HC`, `Editor.HC`, `SmpDemo.HC`.
- C/GUI legacy: `gui/*.c`, `drivers/gpu/*.c`, `drivers/input/*.c`, `kernel/arch/aarch64/{exceptions,gic,smp,timer}.c`, `kernel/bench/*`, `kernel/math/*`, `kernel/physics/*`, `kernel/sched/sched.c`, `boot/uefi/crt_{riscv64,x86_64}.c` + their linker scripts, Lua (`compiler/lua*`).

### 2.2 MERGE (cohesive modules)
| Fuse into | Sources | Why |
|---|---|---|
| **one font manager** (`Fonts.HC`) | `FontMono.HC` + `FontVector.HC` | two font engines, same glyphs |
| **one device** (`GfxDevice.HC`) | `GfxBackend.HC` + `VirtioGpu.HC` | two device/present paths; fix truncated commands |
| **one telemetry** (`Telemetry.HC`) | `Profiler.HC` + `PerfOverlay.HC` | duplicate profiling |
| **one benchmark** (`HolyBenchmark.HC`) | `HolyBenchmark.HC` + `BenchReport.HC` + `BenchCpu.HC` | single 40-phase suite |
| **one renderer** (`HolyGL.HC`) | `Render.HC` + `RasterTile.HC` + `HolyGL.HC` (+ `GfxDevice.HC`) | 4 rasterizers → 1 tiled NEON pipeline |
| **one compiler** (`compiler/`) | `jit_arm64.c` + `lexer.c` + `table.c` → eventually `Compiler.HC` | one tokenizer, one `TOK_*` enum |

### 2.3 DISSOLVE (the radical plan from the docs)
- **`WM.HC` → DolDoc**: a window is a `$WIN,title=…,x=…,y=…,w=…,h=…$` node; titlebars/buttons become DolDoc markup. Delete `g_wm_wins[]`, the drag loop, hardcoded window 2/3.
- **`Compositor.HC` → DolDoc**: delete the compositor task/state; single-pass `DolDocRenderFrame()` over a Morton 64×64 tile journal.
- **`Shell.HC` → DolDoc**: the REPL becomes a `$REPL$` interactive cell node (docs' target) — *or* keep a thin shell that is an action executor over a CDoc (safer; see §5 L5).
- **Delete the character grid**: `g_doc_chars[16384]`, `g_doc_fg`, `g_doc_bg`, `g_hist_chars[131072]` → dynamic text runs.

### 2.4 RETIRE (after self-hosting)
- `compiler/jit_arm64.c` (3,739 LOC), `lexer.c` (534), `table.c` (81) — once `Compiler.HC` compiles the OS (see §3).
- Then the bootstrap runtime C: `kheap.c`, `symbols.c`, `hal_platform.c`, `virtio_blk.c`, `redsea.c` — once their `.HC` versions are boot-load-bearing.

---

## 3. The Bootstrap Paradox (and how to avoid it)

**The paradox (from `neo_os_grand_forensic_dossier_and_sovereign_blueprint.md` §3.6):**
`Compiler.HC` must be **compiled by something** before it can compile anything — including itself. Today the **C JIT** compiles `Compiler.HC` at boot. To retire the C JIT, `Compiler.HC` must exist as a **pre-compiled binary blob** embedded in the bootstrap. Circular unless resolved.

**The docs' resolution:** upgrade `Compiler.HC` with F64 + inline asm + includes (✅ F64 + asm now done), then **pre-compile `Compiler.HC` into a Stage-2 standalone binary** and decommission `jit_arm64.c`/`lexer.c`/`table.c`.

**The *real* hazards to design around (learned the hard way):**
1. **Compiler not hardened** — `HcOpPush` has **no bounds check** (`g_hc_op_stack[256]`); name buffers are fixed (`g_hc_local_names[2048]`, `save_s[256]`). Large modules overflow → heap corruption → crash (this is exactly why the flip failed on `Render.HC`). **Must bounds-check every buffer before the flip.**
2. **Pool exhaustion** — the code pool must hold *all* modules; too small a pool wraps and silently corrupts earlier code. (Raised to 4 MB + guard.)
3. **Load-order / forward refs** — a module compiled before its dependencies' symbols exist. The SIC late-binding helps; load order still matters.
4. **Two tokenizers/`TOK_*` enums** diverge — must unify.
5. **Self-compile loop** — must not have `Compiler.HC` depend on constructs only the C JIT supports.

**Ordering that avoids the paradox (safe):**
`C JIT` → compiles `Compiler.HC` → `Compiler.HC` compiles every module → *verify parity* → pre-compile `Compiler.HC` to a blob → `boot/main.c` loads the blob → retire the C JIT.

---

## 4. Parallelizable workstreams (multi-agent)

These touch mostly **disjoint files**, so they can proceed in parallel once the compiler is hardened:

| WS | Scope | Files | Depends on |
|---|---|---|---|
| **A. Compiler** | harden `Compiler.HC` (bounds), module test, flip, retire C | `Compiler.HC`, `KernelInit.HC`, `compiler/*` | — (root) |
| **B. Rendering unification** | one pipeline: `Render`+`GfxBackend`+`VirtioGpu`+`RasterTile`+`HolyGL`+`Fonts`+damage | `Render.HC`, `GfxBackend.HC`, `VirtioGpu.HC`, `RasterTile.HC`, `HolyGL.HC`, `Font*.HC`, `Compositor.HC` | compiler stable; independent of C/D |
| **C. DolDoc dissolution** | real CDoc/CTree, `$WIN$/$SPLIT$`, dissolve `WM`+`Compositor`(+`Shell` per decision) | `DolDoc.HC`, `WM.HC`, `Compositor.HC`, `Shell.HC` | WS B (renders through the pipeline) |
| **D. Kernel perfection** | HAL de-MMIO-hardcode, `GetMemoryMap`, heap, scheduler, SMP, vector ABI | `HalPlatform.HC`, `KHeap.HC`, `Symbols.HC`, `Sched.HC`, `Smp.HC`, `Gic.HC`, `Exceptions.HC` | independent |
| **E. Benchmark** | one 40-phase HolyGL-max suite; real NEON/Gouraud/texture/Z/SDF | `HolyBenchmark.HC`, `BenchCpu.HC`, `Profiler.HC`, `PerfOverlay.HC` | WS B |
| **F. Typing/dead-code sweep** | `%d`→`%lld`, fnptr types, dup globals, `g_doc_dirty_mask`, ~60 dead fns | many | independent |

**Agent rules:** each agent owns disjoint files; all must run `golden-boot.sh` + manual UART checks; the compiler (WS A) is the gate — no module merge may land while the compiler is unstable.

---

## 5. Complete Tasklist (every level, every system)

### L0 — Harness ✅ done
Golden boot, UART bridge/REPL, JIT battery, symbol audit, crash decoder, screenshot diff, gdbstub flag.

### L1 — Compiler (root)
- [x] Frame locals, `&function`, forward structs, read-path late-binding, `#include`, inline `asm{}`, block comments.
- [x] **F64** (literals, locals, params, returns, arithmetic, comparisons, conversions).
- [x] Unresolved-symbol diagnostic + 3 fixes.
- [ ] **Harden `Compiler.HC`**: bounds-check `HcOpPush` + every fixed buffer; no silent overflow.
- [ ] `#include` **inside `Compiler.HC`**; diagnostics (`file:line`).
- [ ] **Module parity test**: compile every `.HC` with `Compiler.HC`; diff vs C JIT.
- [ ] Unify to **one tokenizer + one `TOK_*` enum**.
- [ ] **Flip** `KInitLoad` → `Compiler.HC`; **retire** `jit_arm64.c`/`lexer.c`/`table.c`.
- [ ] Pre-compile `Compiler.HC` → Stage-2 blob; embed in `boot/main.c`; retire bootstrap C (`kheap/symbols/hal_platform/virtio_blk/redsea`).

### L2 — Kernel perfection
- [ ] HAL: remove hardcoded MMIO bases → discover from DTB/ACPI; `GetMemoryMap` instead of hardcoded layout.
- [ ] Heap: real free/reclaim; single source of truth (retire the shadowed `.HC` allocator or the C one).
- [ ] Symbols: single table; dedupe `g_kernel_booting`×20, GIC/timer bases, `top_print_doldoc`.
- [ ] Scheduler: verify cooperative vs preemptive claim; SMP bring-up correctness.
- [ ] Exceptions: correct vector ABI; one clean ESR/FAR/ELR dump (no infinite loop).

### L3 — Rendering unification (WS B)
- [ ] Merge `GfxBackend`+`VirtioGpu` → **`GfxDevice`**; fix truncated commands + `ATTACH_BACKING`.
- [ ] Merge `Compositor` damage/present into `Render` (one damage, one present).
- [ ] One **tiled NEON rasterizer** (promote `RasterTile`); delete the other 3.
- [ ] One **font** system (`Fonts.HC`); delete `FontMono` duplication.
- [ ] Real Z-buffer + perspective textures + SDF + fragment-shader VM; no `z_avg`.
- [ ] Delete ~60 dead fns + write-only state.

### L4 — DolDoc (WS C)
- [ ] **CDoc/CTree** model; per-char attributes; full two-letter tag set (`TX…SP`).
- [ ] `$WIN$`/`$SPLIT$`/`$BLUR$`/`$ELEV$`; **dissolve `WM.HC`**.
- [ ] Single-pass `DolDocRenderFrame()`; **dissolve `Compositor.HC`**; delete the char grid + window table + compositor state.
- [ ] Reactive cells (generalize `DolDocPatchTarget`); macros/forms/sprites/anchors/links/trees; RedSea persistence.
- [ ] DolDoc reference is a DolDoc (dogfood).

### L5 — Shell (WS C)
- [ ] Action protocol (docs emit, shell executes); command registry (kill the if/else ladder); break all cycles.
- [ ] Decide shell-as-document depth (full `$REPL$` vs thin executor over a CDoc).
- [ ] Fold `top`/`edit`/`filer` into shell-backed docs (already removed as apps).

### L6 — Benchmark (WS E)
- [ ] Consolidate into **one 40-phase HolyGL-max suite**; real NEON/Gouraud/texture/Z/SDF; merge profilers; `/BENCH_REPORT.TXT`.

### L7 — Docs & hygiene (WS F)
- [ ] Rewrite README/docs to the true inventory; supersede contradictory `docs/*.md`.
- [ ] Typing sweep; naming convention; single source of truth per module.

### L8 — Future
- [ ] GPU provider (virtio-gpu 3D / native); `HolyPort` + C→HolyC; `Surface` + `remote` → MCU cluster.

---

## 6. Invariants (never break)
1. **Golden gate green** after every change (`golden-boot.sh`).
2. **C only for the bootstrap**; nothing else in C without retiring something.
3. **No unbounded buffers** in the compiler.
4. **No cycles** in the document/UI stack.
5. **Persist** (commit + bundle) after every green step.
6. **Test manually** (UART + QEMU) — never trust a build alone.
