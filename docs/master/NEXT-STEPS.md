# NEXT STEPS — NeoOS (with the fixed checklist)

> Based on the entire session's discoveries. Companion to `SKILL.md` and `01-VERIFIED-TRUTH.md`.

## Current state
- **GOLDEN BOOT: PASS** (shell, 32 subsystems, 0 exceptions, 0 undefined, 52/52 JIT tests).
- **P0 harness: DONE.** **P1 hardening: DONE.** **P1 flip: BLOCKED** by a JIT codegen bug.
- Tree clean; committed + bundled; project zip at `/neo-os.zip`.

## The single most important next action
**Fix the JIT codegen bug** that corrupts `g_hc_local_count` (→30836) + the heap when `Compiler.HC` compiles `Render.HC`. Everything below P1 depends on this.

### Immediate checklist (A — the blocker)
- [ ] **A1.** Disassemble the JIT-generated code for `HcAddLocalTyped` / `HcSafeCopy` / `g_hc_local_names[g_hc_local_count*32]` (crash-decoder + QEMU monitor `xp /Ni`).
- [ ] **A2.** Identify the miscompiled instruction (array-index scaling, global read, or the bounded-copy loop).
- [ ] **A3.** Fix `compiler/jit_arm64.c` codegen.
- [ ] **A4.** Verify: `Compiler.HC` compiles `Render.HC` with **0 heap corruption**; self-test 7/7; golden gate PASS.
- [ ] **A5.** Handle **>8-arg calls** (spill to stack or hard-error).

### Then (B — complete the compiler)
- [ ] **B1.** `#include` inside `Compiler.HC`.
- [ ] **B2.** Diagnostics (`file:line`, type errors).
- [ ] **B3.** Fix `auto` (tokenizes but isn't consumed → hang).
- [ ] **B4.** Global forward cell (`symbols_lookup_or_reserve`).
- [ ] **B5.** **Parity harness**: compile all **34 modules** with both engines, diff.

### Then (C — flip + retire)
- [ ] **C1.** Flip `KInitLoad` → `CompilerCompileAndRun`.
- [ ] **C2.** Flip **module-by-module** (Render → FontMono → … → Shell); golden gate after each.
- [ ] **C3.** Unify to one tokenizer + one `TOK_*` enum (enums already identical 0–70).
- [ ] **C4.** **Stage-2 blob**: pre-compile `Compiler.HC`; embed in `boot/main.c`.
- [ ] **C5.** Retire `jit_arm64.c`/`lexer.c`/`table.c` + dead `jit_run_self_tests`.
- [ ] **C6.** Retire bootstrap C (`kheap/symbols/hal_platform/virtio_blk/redsea`).

### Then the levels (P2–P8)
- [ ] **P2 Bootstrap minimization:** C → `boot/main.c` + `boot/uefi` only; `GetMemoryMap`.
- [ ] **P3 Kernel:** one allocator/table/HAL; arm timer + register IRQ; real scheduler (`cpu_switch_context`); SMP queues; exception `x3`; dedupe globals.
- [ ] **P4 Rendering:** `GfxDevice`; one tiled NEON rasterizer (real Z/textures/SDF/shader); `Fonts.HC`; fix VirtioGpu lengths; delete ~60 dead fns.
- [ ] **P5 DolDoc:** CDoc/CTree + per-char attrs + full tag set; `$WIN$` dissolves WM; dissolve Compositor; delete char grid; fix `g_doc_dirty_mask`.
- [ ] **P6 Shell:** action protocol; command registry; break cycles; shell-as-CDoc.
- [ ] **P7 Benchmark:** one real 40-phase suite; merge profilers.
- [ ] **P8 Future:** GPU provider; `HolyPort` + C→HolyC; `Surface` + `remote` → MCU cluster.

## How to verify each step
`scripts/golden-boot.sh` green · `run Compiler.HC` self-test 7/7 · manual UART/QEMU check · commit + bundle.

## Guardrails (do not violate)
C only for `boot/main.c` + `boot/uefi` · no unbounded compiler buffers · no JIT miscompiles · no UI cycles · persist after every green step · never leave the tree red.
