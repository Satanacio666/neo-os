# NeoOS — New Tasklist & Priorities (v6)

> Consolidated after the compiler deep-fix round. Includes the full master plan
> (DolDoc, renderer, shell) and every remaining task. P1 is the gate.

---

## The FontMono problem (precise, current blocker)
`Compiler.HC` **hangs** compiling `FontMono.HC` → `FontMonoSelfTest`:
- Stuck on a **`[` (TOK_LBRACKET)** token that no handler consumes → `HcParseStatement` re-enters forever.
- The **declaration path is entered** (struct found), the **`&` path is reached**, `HcResolveLValue` runs — yet `[0]` is left unconsumed.
- Fixed one cause: `HcFindFunc`'s `symbols_lookup` fallback returned globals too → `&global_array` was mistaken for `&function`. The `&` path now uses `HcResolveLValue`.
- **Still hangs** → a second bug in the `&global_array[i]` / struct-pointer-local family.
- Minimal repro: `I64 a[4]; I64 Main() { I64 *p = &a[0]; return 1; }` → spins.
- **It is a compiler parser bug** (the C JIT compiles FontMono fine).

---

## Merge / dissolve status — planned, gated behind P1
**Not done yet (intentional):** you can't safely merge/dissolve modules until the self-hosting compiler compiles+runs them all.
| Merge/dissolve | Target | When |
|---|---|---|
| `FontMono.HC` + `FontVector.HC` + Render glyphs | **`Fonts.HC`** | P4 |
| `GfxBackend.HC` + `VirtioGpu.HC` | **`GfxDevice.HC`** | P4 |
| `Render.HC` + `RasterTile.HC` + `HolyGL.HC` | one tiled rasterizer | P4 |
| `Profiler.HC` + `PerfOverlay.HC` | one telemetry | P7 |
| `HolyBenchmark.HC` + `BenchCpu.HC` + `BenchReport.HC` | one suite | P7 |
| `WM.HC` | DolDoc `$WIN$` nodes | P5 |
| `Compositor.HC` | DolDoc single-pass | P5 |
| `jit_arm64.c` + `lexer.c` + `table.c` | **`Compiler.HC`** | P1 |
| bootstrap `kheap/symbols/hal_platform/virtio_blk/redsea.c` | their `.HC` twins | P2 |

---

## The master plan (unchanged — the target)
- **DolDoc = the real TempleOS model:** `CDoc/CTree` of entries + per-char binary attributes; full two-letter tag set (`TX CR SR CU TB CL PB PL LM RM HD FO ID FD/BD/FG/BG PT WW UL IV BK SX SY CM AN LK BT DA MA SP FI`); links-with-types, anchors, macros, forms, trees, word-wrap; **windows are documents** (`$WIN$`/`$SPLIT$`); **reactive cells** (generalize `DolDocPatchTarget`); RedSea persistence; the DolDoc reference is a DolDoc.
- **One renderer:** HolyGL is the only renderer; one **tiled NEON rasterizer** (real Z-buffer, perspective textures, SDF, fragment-shader VM); one **font system**; one damage; one present. Compositor dissolves into DolDoc.
- **Shell = action executor over a CDoc:** documents emit `Action`s; the shell executes; **no cycles**; command registry (kill the if/else ladder).
- **Everything HolyC:** C only for `boot/main.c` + `boot/uefi`; retire the rest.
- **Endgame:** run anything at native speed (`HolyPort` + C→HolyC), then scale to an MCU cluster (`Surface` + `remote` provider).

---

## THE NEW TASKLIST

### P1 — Finish the compiler (self-hosting flip) — IN PROGRESS
- [ ] **Fix the FontMono `[`-hang** (bisect the minimal repro `I64 a[4]; I64 *p=&a[0];`).
- [ ] Continue **module-by-module** (FontMono → FontVector → Sched → Smp → drivers → Math3D → RasterTile → HolyGL → … → Shell), fixing each codegen bug.
- [ ] Verify **`DolDocShellEventLoop` comes up** under `Compiler.HC`.
- [ ] **Parity harness** — both engines, all 34 modules, diff.
- [ ] **Unify tokenizer** (one `TOK_*` enum; already numerically identical 0–70).
- [ ] **Stage-2 blob** — pre-compile `Compiler.HC`, embed in `boot/main.c`.
- [ ] **Retire** `jit_arm64.c`/`lexer.c`/`table.c` + dead `jit_run_self_tests`.

### P2 — Minimal bootstrap
- [ ] C → `boot/main.c` + `boot/uefi` only.
- [ ] Retire `kheap.c`/`symbols.c`/`hal_platform.c`/`virtio_blk.c`/`redsea.c`.
- [ ] `GetMemoryMap` instead of hardcoded layout.

### P3 — Kernel correctness
- [ ] One allocator · one symbol table · one HAL.
- [ ] Arm the timer (`CNTP_TVAL_EL0`) + register the timer IRQ.
- [ ] Real scheduler (`cpu_switch_context` + run queues); SMP queues (drop local fallback).
- [ ] Exception `vectors.S` `x3` fix; clean ESR/FAR/ELR dump.
- [ ] Dedupe globals.

### P4 — Rendering unification
- [ ] `GfxDevice` (Render+GfxBackend+VirtioGpu+damage/present); fix VirtioGpu command lengths.
- [ ] One tiled NEON rasterizer (real Z/textures/SDF/shader VM).
- [ ] `Fonts.HC` (FontMono+FontVector); delete ~60 dead fns.

### P5 — DolDoc (real model + dissolution)
- [ ] CDoc/CTree + per-char attrs; full tag set; delete the char grid.
- [ ] `$WIN$`/`$SPLIT$`; **dissolve WM.HC**; **dissolve Compositor.HC**.
- [ ] Reactive cells; persistence; fix `g_doc_dirty_mask`.

### P6 — Shell
- [ ] Action protocol; command registry; **break all cycles**; shell buffer = a CDoc.

### P7 — Benchmark
- [ ] One real 40-phase HolyGL-max suite; merge profilers; `/BENCH_REPORT.TXT`.

### P8 — Self-hosting everything
- [ ] Boot as a document; only `boot/main.c` + `boot/uefi` in C.

### P9 — GPU provider
- [ ] virtio-gpu 3D (virgl/Venus) + native GPU drivers.

### P10 — Run anything + cluster
- [ ] `HolyPort` + C→HolyC/LLVM→HolyC; `Surface` + `remote` → MCU cluster (RISC-V).

### Cross-cutting
- [ ] **Typing sweep:** `%d`→`%lld`, fnptr types, dup globals, dirty-mask.
- [ ] **Docs:** rewrite to the verified truth.

---

## All priorities at a glance
| Pri | System | Status |
|---|---|---|
| P0 | Harness | ✅ done |
| **P1** | **Compiler (self-host)** | 🔴 33/34 modules; FontMono `[`-hang |
| P2 | Minimal bootstrap | ⬜ |
| P3 | Kernel | ⬜ |
| P4 | Rendering unification (fonts/device/rasterizer) | ⬜ |
| P5 | DolDoc (real model + dissolve WM/Compositor) | ⬜ |
| P6 | Shell | ⬜ |
| P7 | Benchmark | ⬜ |
| P8 | Self-hosting everything | ⬜ |
| P9 | GPU provider | ⬜ |
| P10 | HolyPort + cluster | ⬜ |

**The single next action: P1 — fix the FontMono `[`-hang, then continue module-by-module.**
