# 06 — Decisions & Remaining TODO

## Decisions made
1. **Compiler endgame = true self-hosting.** Finish `Compiler.HC` (F64 + inline asm + `&function`), then retire `jit_arm64.c`/`lexer.c`/`table.c`. C remains only for `boot/main.c` + `boot/uefi`.
2. **Priority order = P0 harness → P1 compiler → P2 pipeline → DolDoc → Shell → Benchmark → Self-host → (GPU/cluster).**
3. **No unnecessary C.** Everything must be `.HC` except the minimal bootstrap; dead C gets pruned; shadowed `.HC` modules become the source of truth.
4. **HolyGL = an API with backends**, not just a rasterizer. Backends: `soft` (NEON×SMP) now; `virtio-gpu`/`native`/`remote` later.
5. **One Unified Tile Pipeline.** Tile job is the universal unit; SIMD = kernel shape, SMP = core count, GPU = a provider; they run **together**. **No scalar fallback** (AArch64 mandates NEON).
6. **DolDoc = the document/scene model**, implemented on the real TempleOS model (CDoc/CTree, per-char attributes, full tag set, macros/forms/sprites/anchors/links/trees).
7. **Documents emit Actions; the Shell executes.** Break the `DolDoc→Shell`, `WM→Shell`, `WM↔Compositor` cycles.
8. **Windows are documents**; the WM is a layout policy; the Compositor dissolves into Render.
9. **Debugging is manual + protocol-driven** (UART + QEMU monitor/VNC/gdbstub) for every change.
10. **Persistence:** commit + bundle into the project after every green step.
11. **Viewer** stays as the `/neo-os` route in the project (VNC→SSE→canvas + UART panel).

## Open design questions (to decide when reached)
- **Per-char attributes vs per-run** styling (authentic-but-heavy vs cheap-and-simple).
- **`$MA` macros: JIT'd HolyC vs an interpreted tag-language** (power vs sandboxing).
- **Shell-as-document scope** (whole shell vs output pane only).
- **Tile size** (32×32 vs 64×64) and **bin-then-raster vs raster-then-optimize**.
- **Fragment shaders**: tiny HolyC shader VM vs fixed-function for v1.
- **GPU scope**: software-first with a stubbed seam (recommended) vs GPU-first.
- **MCU target**: RISC-V vs Xtensa; and whole-OS vs render/compute offload (offload recommended).

## Remaining TODO (everything left)

### P0 (finish)
- [ ] Crash-decoder helper (monitor `info registers` + `xp` disasm around `ELR`).
- [ ] Screenshot-diff step in the golden gate.
- [ ] Optional gdbstub run target.

### P1 (compiler)
- [ ] `#include` support.
- [ ] Unify to ONE tokenizer + ONE `TOK_*` enum; delete `Lexer.HC` + `Compiler.HC`'s duplicate lexer.
- [ ] Inline asm (`asm { … }`).
- [ ] Add F64 codegen to `Compiler.HC`; compile a real module end-to-end.
- [ ] Flip boot to `Compiler.HC`; retire `jit_arm64.c`/`lexer.c`/`table.c`.
- [ ] Re-apply the C pruning (23 dead `.c` + 24 orphan `.h`; remove empty dirs, `boot/build`, riscv/x86 CRTs).

### P2 (pipeline)
- [ ] Tile job struct + provider interface + work-stealing scheduler.
- [ ] SIMD tile kernel (real Z-buffer, perspective-correct textures, SDF, shader VM).
- [ ] Unify canvas/device/damage/present; delete 4 rasterizers / 3 fonts / 2 damages.
- [ ] Fix VirtioGpu command lengths + ATTACH_BACKING.
- [ ] Determinism test (1 core vs N cores).

### P3 (DolDoc)
- [ ] CDoc/CTree + per-char attributes.
- [ ] Full two-letter tag set + flags/args.
- [ ] Links-with-types, anchors, macros, forms, trees, word-wrap, cursor movement.
- [ ] Reactive cells; RedSea document persistence.
- [ ] Windows-as-documents (`$WIN`/`$SPLIT`).

### P4 (shell)
- [ ] Action protocol; command registry (replace the 300-line if/else).
- [ ] Shell buffer as a CDoc.
- [ ] Break all cycles.
- [ ] Fold `top`/`edit`/`filer` into shell; delete those apps.

### P5 (benchmark)
- [ ] Consolidate HolyBenchmark + HolyBenchmark3D + Bench + BenchReport.
- [ ] Real NEON/Gouraud/texture/Z-interp; SDF shadertoy phases.
- [ ] Merge Profiler + PerfOverlay; write `/BENCH_REPORT.TXT`.
- [ ] BenchCpu real SIMD + PMU counters.

### P6 (self-hosting)
- [ ] Boot as a document; finish self-hosting; retire remaining bootstrap C.

### P7 (future)
- [ ] GPU provider; `HolyPort`; C→HolyC/LLVM→HolyC; `Surface` + `remote` provider; MCU cluster.

### Hygiene / docs
- [ ] Supersede the old contradictory `docs/*.md` (this `docs/master/` set is authoritative).
- [ ] Fix typing: `%d`→`%lld`; fnptr types; duplicate globals; `g_doc_dirty_mask` shift.
- [ ] Remove demos (calc/fact/SmpDemo/Showcase/Menu/Editor/Filer/Top).
