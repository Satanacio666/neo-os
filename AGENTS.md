# NeoOS Master Sovereign Directives & Explicit Execution Order (`AGENTS.md`)

> [!CRITICAL]
> **IRONCLAD ALWAYS-ON WORKSPACE RULE**: This file codifies every explicit order, architectural law, and verification standard issued by the project architect across Prompts #1–#301. Every agent operating in this repository must obey these 20 explicit ordered mandates without shortcuts, stubs, or excuses.

---

## 0. START HERE — current state, canonical docs, and the exact workflow

> **Entry point for any agent that has only container access and no prior context.** Read this first.
> (The 20 mandates in §1–§20 below are the standing law; some name modules that were later dissolved — the
> canonical, current truth is always `docs/00`–`docs/04`, not the mandate text.)

**Repository:** `/home/user/neo-os` (git repo, branch `main`). **Delivery bundle:** `/home/user/project/neo-os.bundle`.
(`/home/user/project/neo-os-docs/` is a **stale pre-consolidation doc dump — ignore it**; the canonical docs are
in `/home/user/neo-os/docs/`.)

### Canonical documentation — exactly 5 files (never add/rename `docs/*.md`)
- `docs/00-MASTER-PLAN.md` — vision, invariants (§2), the P0→P10 ladder (§3), the P7→P11 priority plan (§11).
- `docs/01-REALITY-AUDIT.md` — verified claim-by-claim reality of the code (what is REAL/PARTIAL/STUB/MISSING).
- `docs/02-TASKLIST.md` — the per-phase task list **and the execution runbooks** (P7 blueprint, §P7.0–§P7.8).
- `docs/03-IDEAS-AND-RESEARCH.md` — ideas and research.
- `docs/04-CONTRADICTIONS-DECISIONS-OPEN-QUESTIONS.md` — contradictions + every decision `D1…D33` + open questions.

### Current state (2026-10)
- **P0–P6 ✅ DONE. P7.0 ✅ DONE. P7.0-audit ✅ DONE** (D29 + D30 root-fixed, golden gate hardened).
- **NEXT STEP = P7.1** — HolyGL GL 1.3 surface completion + GL conformance. Complete one-shot runbook:
  `docs/02-TASKLIST.md` §"P7.1 — HolyGL GL 1.3 surface completion (one-shot runbook)".
- Frozen gate (must stay green): `GOLDEN BOOT: PASS`, `SELFTEST 99/99`, `PARITY 68/68 (0 diff)`, `CENSUS 181`,
  `SELF-HOST: PASS`, `DETERMINISM: PASS (0xD28836F)`, `RENDER: PASS (0xD28836F)`.
- The 4 detailed read-only audit reports (P1/P3/P4/P5-P7.0 findings) are archived at
  `docs/research/neo-audit/*.md`.

### Build / run / test — the only sanctioned loop
```bash
cd /home/user/neo-os
make all                                    # build BOOTAA64.EFI + disk.img + redsea.img
./scripts/run-viewer-vm.sh restart          # boot QEMU (VNC :5900, UART socket, log below)
sleep 40; grep -a 'DolDocShell active' /tmp/neo-os-serial.log   # wait for the shell
python3 scripts/neo_uart.py --sentinel '<<<NEO-DONE:selftest>>>' --timeout 175 'selftest'
bash scripts/golden-boot.sh                 # THE gate -> must print "GOLDEN BOOT: PASS"
```
- UART log: `/tmp/neo-os-serial.log`. Drive the REPL by sending lines to the socket (see `scripts/uart-repl.py`).
- **Screenshots are mandatory** for any visual change; `golden-boot.sh` saves `/tmp/golden-boot.png` from the
  dev-server stream. Never verify visuals from a host desktop.
- Do **not** start the dev server (port 4000); it is already running. Do **not** restart the VM if the sandbox
  memory watchdog killed it — ask the user.

### Persist after every green step
```bash
git add -A && git commit -m "<phase>: <what + why>"
git bundle create /home/user/project/neo-os.bundle --all     # refresh the delivery bundle
```

### Hard invariants (full list in `docs/00` §2)
1. **Golden hash bit-exact:** `RENDER: PASS (0xD28836F)`, identical on 1 vs 4 cores.
2. **Census:** `CENSUS: PASS (181)` — no `.HC`→C runtime call count may increase.
3. **No new `.c`** (only `boot/main.c`, `boot/uefi/*`, `boot/seed/*`, `boot/runtime/*`).
4. **5-doc rule:** `ls docs/*.md` is exactly `00`–`04`.
5. **No cross-module struct access** — use accessors (`HolyGL*`, `GfxDevice*`, `DolDoc*`), never `g_hgl.*` etc.
6. **≤8 args per call.** No stubs/mocks/placeholders. No forward declarations.
7. **Max 2 agents in parallel; audit agents are READ-ONLY.** One merge/dissolve per commit; never leave the tree red.

---

## 1. Bare-Metal AArch64 Ring-0 (EL1) Single Address Space Sovereignty
- Everything runs in **ARMv8-A EL1 (Ring 0)** inside a **1:1 flat physical identity-mapped address space (`VA == PA`)**.
- Zero Ring-3 isolation, zero `SVC` syscall overhead, zero address-space context-switch TLB flushes.

## 2. 100% Pure `.HC` Sovereignty & Zero C Expansion
- **No new `.c` files may ever be created.**
- **Zero Stubs, Zero Placeholders, Zero Mock Data**: Every function in every `.HC` file must implement the real, complete algorithm.
- **Zero Trivial Wrapper Files**: Consolidate redundant 1-line wrapper files (`Bench.HC`, `HolyBenchmark3D.HC`, `GpuConfig.HC`, `Top.HC`, `Gears.HC`, `HolyGLTest.HC`, `calc.HC`, `fact.HC`) into their canonical modules.
- **Zero Forward Declarations**: Order functions topologically or dispatch via the Symbol Indirect Cell (SIC) table.

## 3. Real Hardware Portability via `HalPlatform.HC`
- Never hardcode QEMU `virt` MMIO addresses (`0x08000000`, `0x09000000`, `0x0A000000`) or timer frequencies (`62500000`) inside drivers (`Gic.HC`, `Timer.HC`, `Virtio*.HC`, `Keyboard.HC`). Query `HalPlatform.HC` globals (`g_hal_*`).
- `HalFlushCache(addr, size)` must execute both `__dc_civac` AND `__ic_ivau` + `dsb sy; isb`.

## 4. Sovereign Physical Heap Allocator (`KHeap.HC`)
- `KHeap.HC` must manage the entire multi-megabyte physical kernel heap directly (never a 64 KB toy sub-pool inside C `kmalloc`), protected by `smp_spin_lock`/`smp_spin_unlock`, accurately updating `peak_used`, and bound to global `kmalloc`/`kfree`.

## 5. Unified Symbol Indirect Cell (SIC) & Container Library (`Symbols.HC`, `Table.HC`, `StdLib.HC`)
- Unify the duplicated DJB2 hash tables across `Symbols.HC`, `Table.HC`, and `StdLib.HC`.
- `Symbols.HC` must own `symbols_lookup` and `symbols_register` with canonical case-folding (`snake_case` $\leftrightarrow$ `CamelCase`) and never wipe live kernel symbols during self-tests.

## 6. Complete Lexical Analyzer (`Lexer.HC`)
- Unify `TOK_*` constants between `Lexer.HC` and `Compiler.HC`.
- Support IEEE-754 `F64` literals (`TOK_FLOAT`), `/* ... */` block comments, active `#define`/`#include` macro expansion, and dynamic arena string literals (no 63-char truncation).

## 7. Production Stage-2 Self-Hosting Compiler (`Compiler.HC`)
- Emit code into the persistent executable JIT pool (`EfiLoaderCode`) without overwriting index 0 on subsequent runs.
- Fix `HcParseLogOr` so `CBNZ` (`0xB5000000`) is not overwritten with `CBZ` (`0xB4000000`).
- Dynamically compute function stack frame sizes (`>15` locals).
- Support `class`/`struct` member offsets (`.` and `->`), width-aware loads/stores (`U8`/`U16`/`U32`/`I64`), multi-dimensional arrays, `for`/`switch`/`break`/`continue`, `F64` scalar FP + hardware `FSQRT` (`0x1E61C000`), AArch64 NEON 4-lane (`V0.4S`) intrinsics, and linear-scan register allocation.

## 8. Non-Fatal Ring-0 Fault Recovery & Royal Blue BSOD (`Exceptions.HC`)
- Call `ExceptionsDecodeClass(ec)` (fixing undefined `ExceptionsGetEcDesc`), use a re-entrancy guard instead of hanging at `total_exceptions > 1`, validate `ELR_EL1` before dereferencing, unwind user JIT faults cleanly to `ShellRecover()`, and render a Royal Blue BSOD on fatal kernel faults.

## 9. Real Interrupts, Hardware Generic Timer & Context-Switching Scheduler (`Gic.HC`, `Timer.HC`, `Sched.HC`)
- `Gic.HC`: Never disable PPIs `< 32` (such as Timer IRQ 27) in `GicHardwareIrqHandler`.
- `Timer.HC`: Program `CNTP_TVAL_EL0` and `CNTP_CTL_EL0` in hardware; remove hardcoded `62500000` Hz check in self-test.
- `Sched.HC`: Implement real AArch64 register/stack context switching (`__cpu_switch_to`) in `TaskYield` and safe zombie stack reaping in `TaskExit`.

## 10. Real Tickless Multi-Core SMP (`Smp.HC`, `SmpDemo.HC`)
- Boot cores 1–3 via PSCI `CPU_ON` into `WFE`/`SEV` tickless workers; remove synchronous Core-0 execution from `SmpDispatch`; remove all fake heartbeats (`100 + i*25`) and synthetic load formulas.

## 11. Unified VirtIO Transport & Non-Corrupting RedSea FS (`Virtio*.HC`, `RedSea.HC`, `Keyboard.HC`, `Mouse.HC`)
- Shared 64-bit DMA queue setup (`addr >> 32`); dynamic resolution query in `VirtioGpu.HC`; signed `I32` relative mouse deltas and proper struct indexing in `VirtioInput.HC`; combined UART + VirtIO polling in `Keyboard.HC`; dynamic `next_alloc_lba` scanning on mount and safe cluster reallocation on file growth in `RedSea.HC`.

## 12. High-Resolution Canvas, Zero-RAM Scanout & VSync (`Render.HC`, `GfxBackend.HC`)
- Support arbitrary high resolutions dynamically; fix `U32*` pointer scaling in `gfx_swap_rect`; wire Zero-RAM direct VRAM mode and `CNTVCT_EL0` VSync pacing directly into `Render.HC`; propagate `GfxBackend.HC` settings to `RasterTile.HC`.

## 13. Dynamic Semantic Theme & KolibriOS Skin Engine (`CThemePalette`)
- Zero raw `#define COLOR_* 0xFF...` macros in apps. Route all styling through a central runtime-switchable `CThemePalette` (`Mocha`, `Latte`, `Tokyo Night`, `Nord`, `TempleOS CGA`, `Cyberpunk OLED`) with KolibriOS `SKIN_PARAMS` metrics.

## 14. Complete Scalable Bézier & TrueType Typography (`FontVector.HC` + `FontMono.HC`)
- Merge into one typography engine with full 95-glyph printable ASCII quadratic Bézier outlines + TrueType `cmap`/`loca`/`glyf` contour rasterization across multiple font faces and arbitrary sizes (`8pt`–`72pt`).

## 15. Abolish the `128x48` Terminal Grid — True Post-DOM `CDocNode` + OmniTape + Morton Continuum (`DolDoc.HC`)
- Remove `g_doc_chars[6144]` and character-grid snapping. Render directly from the `CDocNode` scene graph / `OmniTape` arena with fluid word-wrapping, Flexbox (`$ROW$`, `$COL$`, `$CARD$`), pixel scrolling, dynamic Morton $64\times 64$ dirty tiles, recursive `$EQ$` math, real-data `$GRAPH$` oscilloscopes, rotating 3D `$SP$` meshes, and `Alt+Click` Morphic Halos.

## 16. Dissolve the Separation of `WM.HC`, `Compositor.HC`, `Shell.HC`, and `DolDoc.HC`
- Unify into a single spatial scene graph (`g_root_doc`):
  - Windows are dynamic `DOC_NODE_WINDOW` (`$WIN$`) subtrees (arbitrary $N$ windows, Acme/Oberon `$ROW$` titlebars, KolibriOS `g_win_tile_map` $O(1)$ hit-testing/occlusion, hardware scissor clipping).
  - The Shell is an inline `DOC_NODE_REPL` (`$REPL$`) node backed by a dynamic command registry (`shell_register_cmd`) and direct HolyC JIT execution.

## 17. Native Real-Time Shadertoy Engine Inside DolDoc (`$SHADER$` & `ShaderEditor.HC`)
- First-class `DOC_NODE_SHADER` (`$SHADER$`) evaluating per-pixel procedural HolyC fragment shaders in $4\times 1$ SIMD quads (`iTime`, `iResolution`, `iMouse`, `FastSinRad`/`FastCosRad`, SDFs), with a live split-pane IDE in `ShaderEditor.HC`.

## 18. Unified 3D Pipeline & 40-Phase Benchmark (`Math3D.HC`, `RasterTile.HC`, `HolyGL.HC`, `Gears3D.HC`, `Physics3D.HC`, `HolyBenchmark.HC`, `PerfOverlay.HC`, `Profiler.HC`)
- Single canonical `Math3D.HC` (hardware `FSQRT`), 16-bit Z-buffered incremental Pineda `RasterTile.HC`, full `HolyGL.HC` integration, real `Gears3DRender()`, unified `PerfOverlay.HC`+`Profiler.HC` HUD, and all 5 engines $\times$ 8 variations in `HolyBenchmark.HC`.

## 19. The Flagship Master Showcase Document (`Showcase.HC`)
- One unified high-resolution document simultaneously displaying multiple scalable fonts/sizes, live theme switching, real-time Shadertoy `$SHADER$` canvas, rotating 3D `$SP$` gears/meshes, nested `$EQ$` math, live `$GRAPH$` telemetry oscilloscopes, reactive `$SL$`/`$CB$`/`$BT$` controls, and an inline `$REPL$`.

## 20. Empirical QEMU Framebuffer Verification Protocol
- Verify all visual output exclusively via QEMU `screendump` framebuffer captures and real mathematical/hardware assertions.
