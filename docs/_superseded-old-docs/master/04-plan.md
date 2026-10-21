# 04 — Priority Plan (P0 → P7)

Built by **dependency: the thing everything else stands on goes first.** Every step must pass
`scripts/golden-boot.sh` and a manual UART/QEMU check before the next.

## Roots
| System | Needed by | Status |
|---|---|---|
| Observability/debug harness | every step | ✅ rebuilt (P0) |
| Compiler | every `.HC` (incl. pipeline & DolDoc) | core fixes ✅; self-hosting pending |
| Unified Tile Pipeline (HolyGL) | DolDoc, shell, WM, benchmark | not started |

---

## P0 — Observability & Debug Harness ✅ COMPLETE
- `run-viewer-vm.sh` (VNC + monitor socket + bidirectional UART; `NEO_DEBUG=1` → gdbstub `-s -S`), `uart-bridge.mjs`, `uart-repl.py`.
- `run-jit-golden.py` + `tests/jit_golden/cases.json` (50 cases).
- `golden-boot.sh` (boot asserts + battery + screenshot).
- `audit-symbols.sh` (zero-emission + undefined/late-bound audit).
- **`crash-decode.py`** — reads ELR/FAR/ESR, maps ELR to the compiled `.HC` function, disassembles around the faulting PC via the QEMU monitor. *Verified with an induced null-write.*
- **`screenshot-diff.py`** — baseline save + % pixels changed. *Verified (0.00% drift between frames).*

## P1 — Compiler correctness & capability (in progress)
**Done (re-applied & verified):**
- Frame-based locals (recursion-safe) ✅
- `&function` support ✅
- Forward-struct two-pass (`parse_struct_def` + `prescan_struct_defs`) ✅
- Read-path late-binding for forward globals ✅
- Unresolved-symbol diagnostic + 3 fixes (`strcat`, `timer_get_uptime_ms`, `doldoc_register_holyc`) ✅
- Bare `*q;` deref-read statement fix ✅
- `WM.HC`-before-`Shell.HC` reorder; DolDoc brace fix; Makefile hardening ✅

**Remaining:**
- `#include` support.
- **Unify to ONE tokenizer + ONE `TOK_*` enum** (delete `Lexer.HC` + `Compiler.HC`'s duplicate lexer).
- Inline asm (`asm { … }`).
- **Self-hosting:** add F64 codegen to `Compiler.HC`; compile a real module end-to-end; flip boot; retire `jit_arm64.c`/`lexer.c`/`table.c`.
- Re-apply the C pruning (dead `.c`/`.h`) so the tree is HolyC-only + bootstrap.

## P2 — The Unified Tile Pipeline (HolyGL spine)
- Define the **tile job** + **provider interface** + **one work-stealing scheduler**.
- Write the **SIMD tile kernel once** (NEON): rasterize (real Z-buffer, perspective-correct), shade (textures + a small fragment-shader VM), blend, tile-local buffers.
- Unify: one canvas, one device (SW now; GPU seam stubbed), one damage, one present; **delete** the 4 rasterizers / 3 fonts / 2 damages.
- **Exit:** triangle, textured quad, SDF glyph, shaded mesh all render through one path across cores; deterministic.

## P3 — DolDoc (document/scene model)
- CDoc/CTree + per-char attributes + full two-letter tag set + reactive cells + macros + forms + trees + word-wrap.
- Renders **only** through P2. Windows-as-documents (`$WIN`/`$SPLIT`).
- **Exit:** a doc with text/link/button/slider/form/tree/3D-scene/shader renders and responds.

## P4 — Shell (interaction layer)
- Action protocol (docs emit, shell executes); command registry (use the existing dead one); shell-as-document; **break all cycles**.
- **Exit:** shell output *is* a CDoc; no `DolDoc→Shell`/`WM→Shell` calls remain.

## P5 — Benchmark (HolyGL-max)
- One 40-phase suite exercising every node/primitive; real NEON/Gouraud/texture/Z.
- **Exit:** stable numbers, tiles/sec scales with cores, report to RedSea.

## P6 — Self-hosting (endgame)
- Boot as a document; finish `Compiler.HC`; retire the bootstrap compiler C; only `boot/main.c` + `boot/uefi` remain.

## P7 — Future (explicitly deferred)
- GPU provider (virtio-gpu 3D / native drivers).
- `HolyPort` platform layer + C→HolyC / LLVM→HolyC toolchain (run decompiled games).
- `Surface` + `remote` provider → **MCU cluster** (RISC-V backend + distributed runtime).

---

## Sequencing rationale
P0 protects everything (the lens). P1 is the root that builds every `.HC` and the gateway to deleting bootstrap C. P2 is the spine all visuals need. P3–P5 layer on it. P6 is the strategic end state. P7 is future research.
