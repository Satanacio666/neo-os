# NeoOS — 04 CONTRADICTIONS, DECISIONS & OPEN QUESTIONS

> Consolidation doc 5 of 5. Every **contradiction** found across the old docs (with both sides preserved and a
> verdict), every **decision** made, every **superseded** claim, and every **open question** still to decide.
> Nothing is dropped. Reality tags come from `01-REALITY-AUDIT.md`; the plan is `00-MASTER-PLAN.md`; tasks are
> `02-TASKLIST.md`; ideas are `03-IDEAS-AND-RESEARCH.md`.

---

## Part A — Contradictions in the old docs (both sides kept)

Each row: the conflicting claims (with sources), the verified reality, and the verdict/tag.

### A1. Lua: "zero Lua code" vs "Lua vendored then excised"
- **"Zero Lua":** `dossier.md §6`, `audit.md §7` — "Não há nenhuma integração Lua… zero código escrito."
- **"Vendored then excised":** `neo_os_grand_architecture_manifesto §3`, `neo_os_architecture_specification §7.2`,
  `task.md` Phase 5, `priority_implementation_plan §2`, `walkthrough §6`, `neo_os_consolidated_defect_record C18`
  — Lua 5.4.7 was vendored (`compiler/lua/`, 32 `.c`, ~13k LOC) then purged.
- **Reality:** both were true at different times. Today **[GONE]** — no Lua anywhere. `neo_os_consolidated_defect_record C18`
  marks the "Lua 100% functional" claims as corrected.
- **Verdict:** excised; the "zero Lua" doc is the *post-excision* truth.

### A2. Timer: 100 Hz vs 1 ms / 1000 Hz
- **100 Hz:** `consolidation_dossier §2`, `dossier.md §5`, `walkthrough`, `complete_render_stack §3`, `priority_implementation_plan §4`.
- **1 ms / 1000 Hz:** `neo_os_architecture_specification §3.3` (`cntfrq / 1000`), `03-design`.
- **Reality:** **[MISSING]** — the timer is **not armed for preemption** at all in the current tree. Whichever
  frequency was intended, neither is wired.
- **Verdict:** unresolved in docs; functionally moot until P3. `(from 01-REALITY-AUDIT §C)`

### A3. Symbol table buckets: 256 vs 1024 vs 4096
- **256:** `dossier.md §3` (DJB2, 256 buckets); `00-CONSOLIDATED §3.1` ("Symbols.HC 256").
- **1024:** `01-VERIFIED-TRUTH §2.2` (C `symbols.c`, 1024, live).
- **4096:** `neo_os_architecture_specification §5` (`SYMBOL_BUCKETS 4096`).
- **Reality:** C `symbols.c` = **1024** (live); `Symbols.HC` = 256 (fallback). **[PARTIAL]** two tables.
- **Verdict:** 4096 was a spec; 256 was the `.HC` fallback; 1024 is the live C table. `(from 01-REALITY-AUDIT §C)`

### A4. Tile size: 32×32 vs 64×64 vs 16×16
- **32×32:** `neo_os_architecture_specification §8` (`raster_tile.c 32x32`), `implementation_plan §4` (keep 32×32),
  `FUTURE roadmap §4.5` (32×32 tiles).
- **64×64:** `manifesto §7`, `POST_DOM §2.2`, `holygl… §6.2`, `doldoc_sovereign`, `ultimate_dom §3 Pillar 3`,
  `doldoc3 §1.2`, `shell_doldoc §5.1`.
- **16×16:** `neo_os_grand_consolidation_encyclopedia §6.3` (and `§3` "16x16 / 32x32 binning").
- **Reality:** `RasterTile.HC` is 64×64; docs conflict. `(from 01-REALITY-AUDIT §E)`
- **Verdict:** **[SUPERSEDED]** by master plan §10 open question 5 (decide at P4).

### A5. Benchmark: 16-phase vs 6-config; 3.0 s vs 15.0 s; 40 phases
- **16-phase matrix:** `walkthrough` (16 phases), `manifesto §4` (16 phases), `neo_os_architecture_specification §8`,
  `neo_os_grand_consolidation_encyclopedia §9.2` (a *different* 16-phase table!).
- **6-config 3.0 s suite:** `single_core_sovereign_master_audit §3`, `complete_render_stack §5` (6 phases × 3.0 s).
- **15.0 s / 60-frame guard:** `implementation_plan §5`, `holygl… §10.2`.
- **40 phases:** `SKILL.md Order 18`, `03-design`, `00-CONSOLIDATED §6 P5`, master plan §6 P7.
- **Reality:** **[MISSING]** — no real 40-phase suite; `HolyBenchmark.HC:59` uses `% 40` over 5 engines.
- **Verdict:** old matrices **[SUPERSEDED]** by master plan §11 ("the 16-phase and 6-phase matrices are superseded
  by the one 40-phase suite"). `(from 01-REALITY-AUDIT §G, 00-MASTER-CONSOLIDATED-PLAN §11)`

### A6. FPS: "43+ FPS" vs measured 5.4–13.5 FPS vs "40+ FPS"
- **43+ FPS:** `consolidation_dossier §2` ("GLXGears … a 43+ FPS"), `dossier` capabilities table.
- **5.4–13.5 FPS (measured):** `walkthrough` 16-phase table (winner 13.5 FPS), `neo_os_grand_consolidation_encyclopedia §9.2`.
- **40+ FPS:** `implementation_plan §3` ("must achieve 40+ FPS on a single host core"), `single_core…_audit`,
  `holygl… §4.3` ("40+ FPS on a single host core").
- **Reality:** all QEMU TCG numbers; **[PARTIAL]**. The 43+ was pre-optimization / different viewport; the 40+ is a target.
- **Verdict:** measured truth is the low range; "43+"/"40+" are aspirational or viewport-dependent.

### A7. File / LOC counts: 179/71,440 vs 215/75,143 vs 51 HC / 43 C
- **179 files / 71,440 LOC:** `neo_os_grand_forensic_dossier… §2` header.
- **215 files / 75,143 LOC:** same doc's table (self-contradiction!).
- **51 `.HC` / 43 `.c`:** `neo_os_grand_forensic_dossier… §2.1/§2.2`, `02-audit`.
- **"43 C modules / 31,635 LOC" vs "18/~8,490":** `02-audit §2.4` flags the former as wrong.
- **Reality:** today `apps/*.HC` = **36**; project C = **9** (+ vendored `boot/uefi`); asm = 5. **[GONE]/stale.**
- **Verdict:** all old counts stale. `(from 01-REALITY-AUDIT intro)`

### A8. Core count: single-core baseline vs 2C/4C
- **Single-core:** `single_core_sovereign_master_audit` (whole doc), `walkthrough` (pinned `taskset -c 0`),
  `complete_render_stack §1`, `exhaustive_architectural_post_mortem §1`.
- **2C/4C:** `walkthrough` 16-phase matrix includes 2C/4C rows; `manifesto §4` Engine B (dual-core SMP).
- **Reality:** SMP bring-up exists; per-core run queues absent; secondary workers often spin **[PARTIAL]**.
- **Verdict:** benchmark runs pinned to 1 host core; guest is 4 vCPUs. Not a contradiction so much as
  host-vs-guest framing (clarified in `complete_render_stack §1`).

### A9. Stage-2 compiler binary blob: required vs removed
- **Required:** `task.md` Phase 16 ("Pre-compile `Compiler.HC` into a Stage-2 standalone binary blob"),
  `FUTURE…ROADMAP` Task 5.4, `P1-DELEGATION §0` item 6, `01-VERIFIED-TRUTH §5` safe-order step 5.
- **Removed:** `docs/master/00-MASTER-CONSOLIDATED-PLAN §4` ("The 'Stage-2 blob' is REMOVED … the owner never asked
  for it … No blob"), §8 Option A.
- **Reality:** **[SUPERSEDED]** — no blob; the seed lives in `boot/seed/` (Option A, `708c92a`).
- **Verdict:** blob rejected. Any doc still requiring it is superseded.

### A10. `GetMemoryMap`: never called vs used
- **Never called:** `01-VERIFIED-TRUTH §2.2`, `audit.md`, `dossier.md §1`, `neo_os_consolidated_defect_record C3`.
- **Used:** `README.md` ("Memory map reported at boot via UEFI `GetMemoryMap`"), master plan P2.
- **Reality:** **[REAL]** now — `boot/main.c boot_probe_memory()` derives heap/JIT pool (P2a, `7199c3e`). The
  "never called" claim is **[GONE]**.
- **Verdict:** the old claim is stale (pre-P2a).

### A11. Compiler F64 / inline asm / `#include`: missing vs present
- **Missing:** `OUTSTANDING_DEFECTS CMP-01..03` (no F64, no asm, dead lexer), `forensic dossier §3.6`,
  `00-REALITY-AND-MASTER-PLAN §0` ("crashes on large modules").
- **Present:** `01-VERIFIED-TRUTH §2.1` ("F64 ✅ and inline `asm{}` ✅ are IMPLEMENTED; docs claiming they're missing
  are stale"), `04-plan`, `01-status-and-history`.
- **Reality:** **[REAL]** — F64 + asm + `#include` all present; `Compiler.HC` now self-hosts.
- **Verdict:** the "missing" docs are stale (pre-fix).

### A12. Scheduler: "cooperative + preemptive" vs stub
- **Claim:** `README.md` ("Cooperative + preemptive scheduler"), `consolidation_dossier §2`.
- **Reality:** `sched_tick()` was an empty stub; `cpu_switch_context` has zero callers; **[STUB]/[MISSING]**.
  `neo_os_consolidated_defect_record C1` lists this as **open**.
- **Verdict:** claim **[SUPERSEDED]** by verified truth.

### A13. "SMP-accelerated rendering" vs cosmetic
- **Claim:** `README.md` ("Rendering dispatched across 4 Cortex-A72 cores").
- **Reality:** `GFX_MODE_SMP_TILED` is a name string; `Smp.HC` has no render code; secondary cores ran
  `worker_math_stress`/`worker_mem_stress`, not the rasterizer **[STUB]**. `neo_os_consolidated_defect_record C2`.
- **Verdict:** claim **[SUPERSEDED]**.

### A14. "TrueType" vs mock
- **Claim:** `README.md` source tree (`font_ttf.c`, `stb_truetype.h`), `consolidation_dossier` ("TrueType Ubuntu Mono").
- **Reality:** `FontMono` parses only an SFNT header (`mock_ttf[64]`); no `font_ttf.c`/`stb_truetype.h` in the
  current tree **[STUB]**. `(from 01-VERIFIED-TRUTH §2.3)`
- **Verdict:** claim **[SUPERSEDED]**.

### A15. Zero-RAM default vs toggle
- **Default:** `README.md` ("Zero-RAM & Double-Buffered Dual Mode … by default"), `task.md` Phase 1.
- **Toggle:** `consolidation_dossier §1.1` ("O modo Zero-RAM não foi removido; continua disponível sob demanda …
  o modo padrão preserva a qualidade visual"), `neo_os_consolidated_defect_record P6` (double-buffer default for
  tear-free interactive).
- **Reality:** both modes exist; **[PARTIAL]**. The README "by default" vs the post-mortem "double-buffer default"
  are a genuine contradiction resolved toward **double-buffer default** (Zero-RAM opt-in via `zeroram on`).
- **Verdict:** resolved (P6): dual mode; double-buffer default.

### A16. Subsystem count: banner "32" vs 34 modules
- **Banner "32":** `README.md`, `01-status-and-history`, all master docs ("ALL 32 HOLYC SUBSYSTEMS").
- **34 modules:** `00-MASTER-CONSOLIDATED-PLAN §3` ("loads 34 modules — banner text is wrong"), `SKILL.md §4`,
  `P1-DELEGATION §8`.
- **Reality:** `KernelInit.HC` loads **34**; banner text is wrong. `(from 01-REALITY-AUDIT intro)`
- **Verdict:** banner bug; 34 is truth.

### A17. Repo URL: `Carlos-Pina` vs `Satanacio666`
- **`Carlos-Pina`:** `README.md` clone instructions.
- **`Satanacio666`:** `implementation_plan §5` push target; `01-status-and-history` clone URL; `02-audit §2.4`
  flags the conflict.
- **Verdict:** unresolved in docs; cosmetic.

### A18. DolDoc grid size: 6144 / 3072 / 16384 / 96×32 / 126×41
- **6144:** `SKILL.md Order 15` ("`g_doc_chars[6144]` … 128x48"), `task.md`.
- **3072:** `doldoc3 §6` ("`DOLDOC_CELLS = 3072` … 96×32").
- **16384:** `OUTSTANDING_DEFECTS DOC-01` (126×41), `FUTURE roadmap §2.1`, `forensic dossier §3.2`.
- **80×24:** `ultimate_dom §1` (generic VT100).
- **Reality:** today `g_doc_chars[16384]`, 126×41 **[STUB]**. `(from 01-REALITY-AUDIT §F)`
- **Verdict:** 16384 is current; older numbers stale.

### A19. "Validated on real hardware" vs QEMU TCG
- **Claim:** `README.md` ("JIT Self-Test Results (Live Hardware)", "Real hardware. Zero compromises"), `walkthrough`
  ("live host execution proofs").
- **Reality:** all runs are QEMU AArch64 TCG **[SUPERSEDED]**. `neo_os_consolidated_defect_record C10` corrects this.
- **Verdict:** QEMU TCG; "real hardware" is aspirational.

### A20. "No gambiarras (hacks)" vs hardcoded QEMU addresses
- **Claim:** `README.md` ("No gambiarras"), `SKILL.md Order 3`.
- **Reality:** hardcoded `0x09000000`/`0x08000000`/`0x0A000000` remain **[PARTIAL]**. `neo_os_consolidated_defect_record C11`.
- **Verdict:** acknowledged QEMU-virt bring-up; P3/P2 work.

### A21. Rasterizer / font / damage / present counts
- **"4 rasterizers / 3 fonts / 2 damage / 3 present":** `01-VERIFIED-TRUTH §2.3`, `00-CONSOLIDATED §3.1`, `SKILL.md §1`.
- **"2 rasterization backends":** `complete_render_stack §3.4` (Model A scanline / Model B tiled).
- **Reality:** **[PARTIAL]** — fragmentation real; counts vary by whether dead paths are counted.
- **Verdict:** "4/3/2/3" counts *all* paths incl. dead; "2" counts live models. Both preserved.

### A22. jit battery count: 50 / 52 / 65 / 67
- **50:** `01-status-and-history`, `04-plan`, `README.md` (`02-audit`).
- **52:** `01-VERIFIED-TRUTH`, `P1-DELEGATION §1`.
- **65/67:** `00-MASTER-CONSOLIDATED-PLAN §3` (67/67), `P2-P6-MIGRATION-SPECS §8` (67 after B3), `01-REALITY-AUDIT` (65/65).
- **Reality:** grew over time; current authoritative = **65/65** (master plan) / **67** (older flip-on count).
- **Verdict:** count evolved; not a real contradiction (just version drift).

### A23. Tile footprint: 24 KB vs 32 KB
- **24 KB (16 KB color + 8 KB Z):** `POST_DOM §2.2`, `ultimate_dom`, `manifesto §7`, `holygl… §6.2`.
- **16 KB tile only:** `shell_doldoc §5.1` ("Tile Size = 64×64×4 = 16 KB").
- **Reality:** depends whether the Z-buffer is counted. **[PARTIAL]**
- **Verdict:** 24 KB when color+Z; 16 KB color-only. Both correct with stated scope.

### A24. `Do` docs as "OmniTape implemented" vs "spec only"
- **"OmniTape implemented" (implied by specs):** `doldoc_sovereign`, `ultimate_dom`, `POST_DOM` describe it as architecture.
- **Reality:** `DolDoc.HC` is a **char grid**; no `CDoc`/`CTree`; no OmniTape buffer **[STUB]/[MISSING]**. Two
  conflicting `CMD_*` opcode tables exist (`doldoc_sovereign §3.1` vs `ultimate_dom §4`).
- **Verdict:** spec only; opcode tables conflict (reconcile at P5).

### A25. `$SP` meaning: 3D mesh vs bitmap sprite
- **3D mesh:** `01-VERIFIED-TRUTH §2.4` ("`$SP` is repurposed to render a 3D mesh, not a bitmap sprite"),
  `doldoc3 §5` (`SPT_MESH`).
- **Bitmap sprite:** `doldoc3 §5.1` (`SPT_BITMAP`), TempleOS `$SP` sprites.
- **Reality:** repurposed to 3D **[PARTIAL]**.
- **Verdict:** current = 3D mesh; TempleOS parity wants both.

### A26. Benchmark "3.0 s" vs "15.0 s" phase duration
- **3.0 s:** `single_core…_audit §3`, `complete_render_stack §5`, `neo_os_consolidated_defect_record P3`.
- **15.0 s + 60-frame guard:** `implementation_plan §5`, `holygl… §10.2`.
- **Reality:** **[MISSING]** (no real suite).
- **Verdict:** conflicting targets; decide at P7.

### A27. Zero-RAM buffer "3.14 MB" vs "3.0 MiB"
- **3.14 MB:** `README.md`, `manifesto §6/§7`.
- **3.0 MiB:** `neo_os_consolidated_defect_record C8` (1024×768×4 = 3,145,728 B ≈ 3.0 MiB).
- **Verdict:** rounding; **[SUPERSEDED]** (C8 corrected the rounding).

### A28. "Dual-tier: precompiled AOT C + JIT HolyC" vs "C is only the bootstrap"
- **Dual-tier:** `manifesto §3` (Tier 1 C, Tier 2 HolyC).
- **C only bootstrap:** master plan §1/§2.
- **Reality:** **[PARTIAL]** — C is confined to `boot/` but still the live runtime. `(from 01-REALITY-AUDIT §A)`
- **Verdict:** dual-tier is the current *de facto* state; "C only bootstrap" is the target (P2).

### A29. P2 exit "no project runtime `.c`" vs its own "Irreducible C keeps a block/FS reader"
- **Exit claim:** `02-TASKLIST` old P2.6 — "`SRCS_C` = `boot/main.c` + `boot/seed/*` + `boot/uefi/*`; 0 `.HC`→C runtime calls".
- **Irreducible claim:** same doc, "Irreducible C" list — keep "the smallest allocator + symbol table +
  block/FS reader that `Compiler.HC` needs *before* any `.HC` module can run".
- **Reality (verified `92a5878`):** the C FS/block stack (`boot/main.c:307-321` → C `redsea.c` → C
  `virtio_blk.c`) loads *every* `.HC` module, so those C files **cannot** be deleted while modules come from
  the disk through the C FS. The two claims are mutually exclusive.
- **Verdict:** the exit claim was wrong. P2 is rewritten (doc 02) around a **bootstrap image** that gives the
  seed the `.HC` sources without a filesystem; only then can C `redsea.c`/`virtio_blk.c` be deleted. The seed
  floor is `boot/main.c` + `boot/seed/*` + `boot/runtime/{kheap,symbols}.c` + vendored `boot/uefi/*`.

---

## Part B — Superseded / retired claims (do NOT act on)

| Superseded claim | Source(s) | Superseded by |
|---|---|---|
| Stage-2 binary blob | `task.md` Ph16, `FUTURE…ROADMAP` 5.4, `P1-DELEGATION §0.6` | master plan §4 (no blob; Option A) |
| `scripts/compile-parity.sh` | `P1-DELEGATION §0/§1` | real tool `scripts/p1-parity.sh` |
| 16-phase benchmark matrix | `walkthrough`, `manifesto §4`, `encyclopedia §9.2` | one 40-phase suite (master plan §11) |
| 6-config 3.0 s suite | `single_core…_audit §3`, `complete_render_stack §5` | one 40-phase suite |
| Old C boot sequence (`kheap_init`→`smp_init`→…) | `dossier.md §1` | `KernelInit.HC` 6-stage `.HC` load |
| 32 MB fixed heap / 4 MB JIT / 4 MB stack | `consolidation_dossier`, `manifesto` | `GetMemoryMap`-derived (P2a) |
| "Compiler.HC has no F64/asm/#include" | `OUTSTANDING_DEFECTS CMP-01..03` | F64+asm+#include present; self-hosting |
| "Windows dissolved into DolDoc" | many specs | **[MISSING]** — WM owns 8 windows; P5 target |
| "Shell IS a CDoc" | specs | **[MISSING]** — if/else ladder; P6 target |
| "Preemptive scheduler" | `README.md` | stub; P3 target |
| "SMP rendering" | `README.md` | cosmetic; P4 target |
| "TrueType font" | `README.md` | mock SFNT; P4 target |
| Lua "100% functional" | `walkthrough`, `consolidation_dossier`, `encyclopedia` | excised (C18) |
| Ring-0 embeddings "running in Ring 0" | `manifesto §14` | research only (C19) |
| Physical mobile SoC bring-up | `manifesto §12–13` | QEMU-only (C20) |
| "Validated on real hardware" | `README.md` | QEMU TCG (C10) |
| `179/71,440` and `215/75,143` file/LOC counts | forensic dossier | 36 `.HC` / 9 C (today) |
| `jittest`/auto-bench at boot | `README.md` | `jittest` fixed→true; auto-bench false |
| `GetMemoryMap` never called | `audit.md`, `dossier.md` | used (P2a) |
| `timer_get_uptime_ms` undefined | `02-audit §2.1` | fixed in P1 |
| `&function`→0; no forward structs | `audit.md §1` | fixed in P1 |

---

## Part C — Decisions made (resolved)

`(from docs/master/06-decisions-and-todo §"Decisions", 00-CONSOLIDATED §5, 03-design, 00-MASTER-CONSOLIDATED-PLAN, SKILL.md)`

1. **Compiler endgame = true self-hosting**; retire `jit_arm64.c`/`lexer.c`/`table.c`; C only for `boot/main.c` + `boot/uefi`.
2. **Priority order = compiler-first:** P0 harness → P1 compiler → P2 bootstrap → P3 kernel → P4 render → P5 DolDoc → P6 shell → P7 benchmark → P8 self-host → P9 GPU → P10 run-anything/cluster.
3. **No unnecessary C**; dead C pruned; shadowed `.HC` modules become source of truth.
4. **HolyGL = an API with backends** (soft NEON×SMP now; virtio-gpu/native/remote later).
5. **One Unified Tile Pipeline**; tile job = universal unit; SIMD = kernel shape, SMP = core count, GPU = provider; **no scalar fallback** (AArch64 mandates NEON).
6. **DolDoc = the real TempleOS model** (CDoc/CTree, per-char attrs, full tag set, macros/forms/sprites/anchors/links/trees); **windows are documents**.
7. **Documents emit Actions; the Shell executes**; break all cycles.
8. **Windows are documents**; WM = layout policy; Compositor dissolves into Render/DolDoc.
9. **Debugging is manual + protocol-driven** (UART + QEMU monitor/VNC/gdbstub) for every change.
10. **Persistence:** commit + bundle after every green step; never rely on `/tmp`.
11. **Viewer stays** as the `/neo-os` route (VNC→SSE→canvas + UART panel).
12. **Seed compiler = Option A** (C seed confined to `boot/seed/`); **no binary blob**.
13. **Lua permanently excised** (Phase 5) for pure HolyC sovereignty.
14. **Zero-RAM + double-buffered dual mode**; double-buffer default for tear-free interactive; Zero-RAM opt-in.
15. **Golden gate green after every change**; self-host gate required too.
16. **Bootstrap = seed compiler substrate only** (allocate + symbols + compile + obtain `.HC` bytes); the
    seed has **no FS and no OS block driver**. `.HC` sources reach the seed from the FAT32 ESP via the **UEFI
    firmware's own FAT driver** (`EFI_SIMPLE_FILE_SYSTEM_PROTOCOL`; `boot/seed/seed_fs.c`) — **DONE**.
    C `redsea.c`/`virtio_blk.c`/`hal_platform.c` are **deleted**; `boot/runtime/` = `{kheap.c, symbols.c}`
    (the frozen seed substrate). C seed = 6 files. `.HC`→C census = 159 (all seed). Rejected alternatives:
    embedding `.HC` source in the EFI image; a raw TOC'd disk region.

---

## Part D — Open questions (decide at the stage boundary)

`(from 00-MASTER-CONSOLIDATED-PLAN §10, 06-decisions-and-todo §"Open design questions", 03-design)`

1. **P5 — Per-char attributes vs per-run styling** (authentic-but-heavy vs cheap-and-simple).
2. **P5 — `$MA` macros:** JIT'd HolyC vs an interpreted tag language (power vs sandboxing).
3. **P6 — Shell-as-document scope:** whole shell vs output pane only.
4. **P4 — Tile size** (32×32 vs 64×64) and **bin-then-raster vs raster-then-optimize**.
5. **P4 — Fragment shaders:** tiny HolyC shader VM vs fixed-function for v1.
6. **P9 — GPU scope:** software-first with a stubbed seam (recommended) vs GPU-first.
7. **P10 — MCU target:** RISC-V vs Xtensa; whole-OS vs render/compute offload (offload recommended).
8. **P7 — Benchmark phase model:** 40 real phases vs relabel; 3.0 s vs 15.0 s per phase.
9. **P2.2 — Bootstrap source of the `.HC` files:** **RESOLVED — UEFI SimpleFS.** The seed reads the `.HC`
   sources from the FAT32 ESP via the firmware's own `EFI_SIMPLE_FILE_SYSTEM_PROTOCOL` (no custom FS, no
   block driver, no blob; `main.c` never calls `ExitBootServices`). Rejected: embedding the `.HC` source in
   the EFI image; a raw TOC'd disk region + seed sector reader.

---

## Part E — Defect registers consolidated (open items only)

`(from neo_os_consolidated_defect_record §9, OUTSTANDING_DEFECTS, 01-VERIFIED-TRUTH §3, audit.md §5)`

Still **open** (deliberately not fixed):
- Preemptive task switching (`sched_tick` stub; `cpu_switch_context` zero callers) — C1.
- `GetMemoryMap` integration — **now fixed** (P2a); keep for completeness — C3.
- Hardcoded QEMU `virt` MMIO addresses (needs FDT) — C11.
- Full C→`.HC` migration — **P2 DONE**: project C = **6** (`boot/main.c`,
  `boot/seed/{lexer,table,jit_arm64,seed_fs}.c`, `boot/runtime/{kheap,symbols}.c`). The C FS/block/HAL are
  gone; the seed reads `.HC` from the FAT32 ESP via the UEFI firmware's FAT driver. Remaining C is the frozen
  seed substrate (allocator + symbol table + compiler).
- **P2.7 compiler-only bootstrap — DONE.** Parser bug fixed (function after a top-level statement; commit
  `95ece53`). The "`KHeap.HC` codegen corruption" was misattributed: the real bug was **pointer-element array
  indexing** in `HcResolveLValue` — `CSymbol *g_sym_buckets[256]` (in `Symbols.HC`) strided by the pointee
  struct size (92) instead of 8, so `SymInit()` clobbered the C-heap. Fixed (register element width for all
  global arrays; only use the pointee struct size when no width is registered). The C JIT now compiles **only**
  `Compiler.HC`; the seed compiles **1** module, not 7. Gate green.
- **P3 kernel correctness — DONE.** Hardware timer IRQ (EL1 virtual timer PPI 27), preemptive scheduling
  (trap-frame switch through the IRQ vector), SMP (cores 1–3 online via PSCI), kernel faults → BSOD / REPL
  faults unwind, UEFI memory-map discovery, and the **sovereign handover** (`.HC` KHeap/Symbols own
  `kmalloc`/`kfree`/`symbols_*` via SIC hot-patch). The C seed allocator/symbol table remain the *bootstrap*
  floor (frozen at handover), not the runtime owner. `SOVEREIGN/TICK/SCHED/BSOD/SMP` gates green. Residual
  (not blocking): SMP per-core **run queues** (workers are job-mailbox based), tickless idle, `.HC` ownership
  of the C JIT seed.
- **P4.0 render gate — DONE.** Decision: the P4 regression/determinism gate is a **frozen golden-frame hash**
  (`0x7E9DE351`, 32-bit FNV-1a over the whole back buffer) rendered by `RenderGoldenScene()` with IRQs masked
  so no preemptive writer can perturb it; asserted as `RENDER: PASS` in `golden-boot.sh`. Measured with the
  new in-guest `renderbench` (`13063 tri/s, 9122 Kpix/s, 72 Mpix/s`). The render fragmentation the plan targets
  is unchanged (two Z-buffers, four triangle paths, three damage/present trackers); the 43-function dead list
  and write-only state are recorded in doc 2 §P4.0 to drive P4.8.
- **P4.1 unified device — DONE.** Decision: `GfxBackend.HC` + `VirtioGpu.HC` are merged into one
  `apps/GfxDevice.HC` with a single target resolver (`GfxDeviceTarget`), one damage tracker, and one present
  (`GfxPresent`); the virtio-gpu transport lives in the same file. The **truncated command bug is fixed**
  (`RESOURCE_CREATE_2D` 40, `TRANSFER_TO_HOST_2D` 56) — verified live (device active, flushes return 0,
  `render gpu` presents without fault). Write-only knobs and dead `gl*`/`virtio_gpu_*` aliases deleted
  (symbols 1330 → 1310). Virtio-gpu stays **2D**; virgl/Venus 3D is deferred to P9.
- **P4.2 one rasterizer + Compiler.HC root fix — DONE.** Decision: the single rasterizer uses exact **integer**
  Pineda edges (not 16.16 — exact at integer coords) + top-left rule + per-pixel Z interpolation over one
  full-screen 16-bit Z-buffer. The blocker was **not** the rasterizer but a self-hosted compiler bug: a global
  **pointer**'s pointee width was never registered, so indexed use fell back to an 8-byte element stride/width
  (`U16*` read `0xFFFF` as `-1`; `U32*` stores went to the wrong address). Fixed at the root in `Compiler.HC`
  (register pointee width for global pointers; bare pointer use stays 8 bytes) — **option A**, no
  function-splitting workarounds. The `& 0xFFFF` mask and `RasterPut`/`RasterPutZ` shims were removed. Locked
  in by `SelfTestPtrScale` (`PTRSCALE: PASS`) and `RasterBootCheck` (`RASTER: PASS`). RENDER golden hash
  re-baselined `0x7E9DE351 → 0xD28836F`. **p4.2b NEON span — DONE (Option 2).** Decision: the 8-pixel span
  uses 128-bit NEON for the biased edge coverage, 8-lane depth compare and masked Z/framebuffer stores, but
  keeps the depth numerator/division **exact 64-bit** (8 scalar `SDIV`/block). Rejected Option 1 (16-bit DDA
  Z stepping) because truncated stepping drifts between adjacent triangles' spans and would re-introduce mesh
  Z-fighting. Parameters cross via a `CRasterSpan` descriptor in `X0`; words assembled from
  `scripts/raster_span.s`. Measured `renderbench` 2075 → 9262 tri/s (4.46×); `RENDER` hash bit-identical
  (`0xD28836F`); `RASTER: PASS`.
- RedSea in-place sector allocation / reclaim / dynamic `next_alloc_lba` — open (→ RedSea v2, doc 03 §9.5).
- Tracked binary artifacts in git — historical.
- No CI workflow — historical.
- **Compiler:** **global-pointer element width — FIXED (P4.2):** a global pointer (`U16 *p`, `U32 *p`) never registered its pointee width, so `p[i]` used the default 8-byte stride/width (8-byte `LDR`/`STR`). Root-fixed in `Compiler.HC` and locked in by `SelfTestPtrScale`/`RasterBootCheck`. >8-arg calls hard error; `auto` hang risk; `#include` inside `Compiler.HC`; diagnostics; script-mode gaps (fnptr/F64-struct/forward-struct/cross-unit) — P1.1/P1.2. **New (found by the P0.5 expansion):** 2-D arrays fault (Data Abort); `enum` unsupported (returns -1); function-like `#define` unsupported (returns -1); an unterminated `struct {` is silently accepted (returns 0); a global-`F64` subtraction (`F64 r = 0.0 - q;`) returned 0; recompiling the whole battery twice in one boot trips a re-entrancy fault (guarded in `SelfTest.HC`).
- **Kernel:** one allocator/table/HAL; arm timer + IRQ; real scheduler; SMP queues; exception `x3`; `g_kernel_booting`×14 — P3.
- **Render:** `z_avg`; textures unsampled; no SDF/shader VM; VirtioGpu truncated commands; `BenchCpuMathNeon` LCG (BEN-01); synthetic telemetry (BEN-02); PMU absent — P4/P7.
- **DolDoc:** char grid; missing `$MA/$DA/$AN/$ID`/word-wrap; `g_doc_dirty_mask` shift; cycles; fake WM FPS/"4 Cores"; uptime wraps at 999 s — P5.
- **Shell:** dead `shell_register_cmd`; if/else ladder; cycles — P6.
- **Typing:** `%d`×~40; fnptr as `U64`; colors as `I64`; `int` truncation; signature mismatches — sweep.
- **Security/environment:** hardcoded host paths (fixed historically via `NEO_ROOT`); QMP socket single-client — historical.

---

## Part C — Decisions & resolutions (2026-10)

### D1. "Allocator anomaly `free=8388560 used=48`" — RESOLVED (not an allocator bug)
- **Claim (hypothesis):** `kmalloc(36)` failed with 8 MB free → the KHeap block-split corrupts the remainder
  (pointer arithmetic scaled by `sizeof(CHeapBlock)`), or the sovereign handover is mis-timed.
- **Reality:** the `[HCLX]` diagnostic was printing the **idle** HolyC pool (`used=48` = one header); the
  failing allocator was the **C seed heap** (`boot/runtime/kheap.c`), which had ~43 MB free → **not exhaustion**.
  The split is **correct**: `HcParseAdditive` emits a raw `add x0,x0,x1`, so HolyC pointer arithmetic is
  **byte-based** (only `[]` scales, via `HcGlobalScale`/strides). **Causa 2 ruled out.**
- **Verdict:** the real root cause was a **silent 128 KB module truncation** in `KInitLoad` (`Compiler.HC` was
  already truncated past `CompilerCompileAndRun`; growth pushed it past the cutoff → dangling functions).
  Fixed in P0.7 (`HC_MODULE_MAX` 1 MB, `HC_SRC_MAX`, C-JIT `INCLUDE_BUF_SIZE` 2 MB). Decision: **any module
  read must have a ceiling ≥ the largest source, and truncation must never be silent.**

### D2. Lexer string allocation — DECIDED: dedicated bump arena, never per-literal `kmalloc`
Per-literal `kmalloc(slen+1)` (never freed) leaked ~2000 small blocks/boot and fragmented the heap. Decision:
a dedicated **string arena** (`HcStrAlloc`, chained 256 KiB chunks, **BSS-first** chunk so lexing has no
allocator dependency during the boot window, bounds-checked). String literals must **persist** because emitted
code embeds their addresses. *(Landed P0.7.)*

### D3. P4.3 architecture — DECIDED: one unified rasterizer; texel gather is scalar (hardware)
- **Rejected:** a permanent **separate scalar rasterizer** (fragments the engine, violates the P4 mandate).
- **Decided:** `RasterRow` is the single span driver; when `g_raster_tex_active` it runs the textured span,
  otherwise the byte-identical `RasterSpanNEON`. AArch64 NEON has **no gather**, so the 8-texel fetch is
  **scalar `LDR`+`INS` by hardware necessity**; the coordinate/filter/blend math is NEON-able. The definitive
  NEON extension of the textured span is **p4.3b**, validated against the scalar math. The 2D golden path
  forces `RasterDisableTexture()` so `RENDER 0xD28836F` stays bit-exact.

### D4. Compiler hard limits that constrain all P4+ code — ENCODE IN THE PLAN
- **Max 8 arguments per call** (C JIT `jit_arm64.c:978`, self-hosted `Compiler.HC:1724`). Violating it fails
  the unit → since functions are **published before body-parse**, a mid-body error leaves **dangling symbols**
  (the p4.3-wip BSOD: a 9-arg debug `doldoc_printf` at `RasterTile.HC:425`). **Never exceed 8 args; never
  print from inside the rasterizer; diagnostics are globals read after the draw.**
- Max `print`-statement args 7 (C JIT); local arrays supported (≤256 locals, frame ≤4080 B); `#define` persists
  across modules (idempotent redefine); unresolved symbols are a **safe no-op trap** (return 0), but a symbol
  published to a **rolled-back** address is **not** safe.

### D5. Research method — DECIDED
For any non-trivial root fix, first spawn **read-only** research agents (codebase forensics + external
best-in-class) and persist their briefs under `docs/research/`, **then** implement in one shot. Agents must
**not** edit the project. *(This session: the BSOD root cause and the §9 algorithm map came from those briefs.)*

### D6. Mixed I64/F64 arithmetic — FIXED (root) in the compiler
- **Bug:** the float binary path (`HcParseMultiplicative/Additive/Relational/Equality`) moved operands with
  `fmov d0,x0`/`fmov d1,x1`, assuming **both** were F64. When one was an integer, its bit pattern was
  reinterpreted as a double. `F64 half_w = g_hgl.vp_w * 0.5` therefore produced a denormal ≈0, so **every
  HolyGL triangle collapsed to (0,0)** — 3D rendering had been silently broken (the 2D golden scene calls
  `RasterTriangleZ` directly, masking it).
- **Fix:** `HcEmitPromoteFloat(lf, rf)` converts the integer operand with **`scvtf d, x`** before the float op.
- **Verdict:** root-fixed. Any int↔float arithmetic now promotes correctly. *(This was the single biggest
  hidden defect; it is why the cube/3D demos never really rendered.)*

### D7. Struct-member pointer indexing stride — **ROOT-FIXED** (p4.3b)
- **Bug:** indexing a pointer **struct member** (`g_rtex.data[k]`, a `U32 *`) advanced by **8** bytes, not
  `sizeof(U32)=4` (global pointers get their scale via `HcRegisterGlobalScale`; struct members did not). The
  typed-local workaround (`U32 *td = g_rtex.data; td[i]`) was **technical debt** that would have broken the P4.4
  SDF font atlas and the P5 DolDoc `CDoc` nodes.
- **Fix (root, `Compiler.HC`):** new `g_hc_member_elem_bytes[8192]` carries each member's element/pointee width
  (mirrors `struct_member_t.elem_size` in the C JIT). `HcFindMember` publishes it via the global
  `g_hc_found_member_elem` (a 9th out-param would violate the **8-arg** cap, D4). In `HcResolveLValue`, an
  indexed `m_ptr`/`m_arr` member uses `cur_scale = elem`, so `s.data[k]` strides by 4 and emits `LDR W`.
- **Workaround removed** in `RasterTile.HC`; `g_rtex.data[...]` is used directly. Regression `PTRSCALE2: PASS`
  (`U8 *p8/U16 *p16/U32 *p32`, direct + arrow, no adjacent-byte corruption) + golden case `struct_member_ptr_scale`.

### D8. p4.3b textured span — DECIDED: one kernel, NEON, integer-exact
- **One kernel.** `RasterSpanNEON` branches on `CRasterSpan.tex_ptr`; the solid path is byte-identical (golden
  hash `0xD28836F` unchanged). No second rasterizer, no scalar fallback for the aligned body (head/tail < 8 px
  still use `RasterPixelTextured`).
- **Hardware split.** Coverage + 8-lane depth = NEON (`CMHI.8H`). Per-lane perspective = **exact 64-bit `SDIV`**
  (`u=(numU<<16)/den`, `numU=Σwₖ·uowₖ` recomputed per block from that block's `w0,w1,w2`); texel **gather is
  scalar** (AArch64 NEON has no gather). Bilinear / modulate / blend are **NEON** (`UXTL`/`UMULL`/`UMLAL`/`SHRN`,
  exact `/255` via `(P+(P>>8)+1)>>8`, blend `+127` then `/255`). Mask-skip via `TST` on the active mask.
- **Not bit-identical to the old scalar F64 path** by construction (16.16 integer vs F64), but `SelfTestTexture`'s
  4 sub-tests pass (tolerances cover the difference). The **golden 2D hash** path is untouched, so it stays exact.
- **Bring-up bugs (both fixed):** (a) `w19` (colour) clobbered by the loop's `x19` temp → modulate colour rebuilt
  from garbage → dimmed texels; build `v8`/`v9` once in the prologue. (b) overlapping 8-byte stack slots for
  `fx/fy`/`tx0/tx1`/`ty0/ty1` → 4-byte slots. (c) affine `numU/numV/den` must be recomputed **per block** (a
  single descriptor `numU0` is only valid for the first block).

### D9. P4.4 font architecture — DECIDED: merged module + boot-baked AA coverage atlas
- **One module.** `FontMono` + `FontVector` merged into `apps/Fonts.HC`; the mock SFNT parser and the
  redundant bitmap copy are deleted; `KernelInit` Stage 2 loads only `Fonts.HC`. The bitmap path stays
  (crisp small text, golden-hash-safe); the vector outline table stays (scalable source).
- **AA via a baked coverage atlas, not a live SDF.** A fixed-function composite cannot evaluate an SDF per
  fragment, so `smoothstep` is applied at **bake** time: outlines are rasterised at 4x supersample and
  box-downsampled to a 24x24 coverage cell (17 alpha levels) in a 256x256 PoT atlas. Per-fragment SDF is a
  **P4.6 fragment-VM** follow-up.
- **Composite = direct bilinear coverage read into the framebuffer**, NOT a rasterizer textured quad. The
  packed atlas's sub-texel UV is fragile at the NEON span's 16.16 precision (verified: a rasterizer-quad
  composite produced malformed glyphs); the direct read is clip-safe and exact.
- **Keep the `FontVectorDrawString`/`MeasureString` names** (DolDoc late-binds via `symbols_lookup`).

### D10. 3D transform matrix order — **ROOT-FIXED** (P4.5 prerequisite)
- **Bug:** `Mat4Translate`/`Mat4Scale`/`Mat4RotateX/Y/Z` (`Math3D.HC`) **pre-multiplied**
  (`out = T * out`) instead of GL's post-multiply (`out = out * T`). Any translate/rotate/scale
  sequence therefore composed in the wrong order, so **every 3D object collapsed** (gears -> an 8-px strip;
  the cube filled/blanked the viewport). The 2D golden scene and the identity-projection texture tests never
  exercised a sequence, so they passed and hid it.
- **Fix:** post-multiply in all five helpers. Verified: a lit HolyGL cube now renders
  (`3D: PASS, ink=109078`, correct face colours) through the one rasterizer; `RENDER 0xD28836F` unchanged;
  a new `3D` gate added to `golden-boot.sh`.
- **Superseded by D11:** the "gears collapse" was NOT a gear-geometry bug at all — it was the compiler F64
  codegen bug fixed in D11. See D11.

### D11. Gears geometry "collapse" — **ROOT-FIXED** (P4.5a): cross-unit F64 function return type
- **Symptom:** `Gears3DRenderViewport` drew 366 tris / 644 px (an ~8-px strip) while the equivalent cube
  rendered fully; the gear vertices' `x`/`y` were garbage (huge/NaN bit patterns) but `z` (`-width*0.5`, a
  constant expression) was correct.
- **Root cause (compiler, not geometry):** `HcReset()` clears `g_hc_func_*` at the start of EVERY unit, so the
  per-unit function table only ever holds the current unit's functions. When `Gears3D.HC` (a later unit) called
  `MathCos` (defined in `Math3D.HC`, an earlier unit), `HcFuncIsFloat("MathCos")` returned **0** — the call was
  treated as returning an **integer**. `HcEmitPromoteFloat` then emitted `scvtf d0, x0`, reinterpreting the
  double's raw IEEE-754 bits as an integer: `r * MathCos(a)` produced garbage, `z = w*0.5` (no call) stayed
  correct. This is a landmine under all F64 math (P4.5 lighting, P4.6 VM, P4.7 OBJ).
- **Fix (root):** a **persistent** `name → returns-F64` table (`g_hc_fnf_names/flags/count`, `HC_FNF_MAX`
  2048, never reset) written by `HcAddFunc`; `HcFuncIsFloat` consults the per-unit table first, then the
  persistent one. Plus `HcPrescanFuncs` — a brace-depth-0 pre-scan (mirroring `HcPrescanStructs`) that
  registers every top-level function's floatness before parsing, so intra-unit forward references resolve too.
- **Verified:** gears now render **800 tris / 71410 px** (`3D-GEARS: PASS`), visually correct in the WM
  desktop. Regressions: `f64_lhs_mul_fn_call`, `f64_struct_arr_member_assign`, `f64_seven_arg_mixed`
  (`SelfTest.HC`) and the first two in `tests/jit_golden/cases.json` (expect `0x4000000000000000`).
- **Note:** the C seed JIT does not track cross-unit F64 return types either, but it only compiles
  `Compiler.HC` at bootstrap and the in-guest parity corpus, so it is not on the runtime path.

### D12. P4.5 shading architecture — DECIDED: three colour stages in the ONE NEON kernel
- **One kernel, mode dispatch.** `CRasterSpan.gmode` (0xF8): **0 flat** (byte-identical solid path → the
  golden `0xD28836F` is untouched), **1 Gouraud** (affine per-vertex lit colour), **2 per-fragment
  Blinn-Phong**. The shared coverage/depth stage is computed exactly as before; only the colour stage differs,
  so there is no duplicated Pineda/top-left/depth code.
- **Affine accumulators, not per-pixel division.** Colour and normal are linear in `x`, so the C side passes
  the value at the block's `x_start` plus a per-pixel delta; the kernel advances the accumulator by `8*delta`
  per block and fans the 8 lanes with `FMLA v.4s, v.4s, [0..7]`. No per-pixel `SDIV` for shading.
- **Per-fragment normal normalize = `FRSQRTE` + one `FRSQRTS` Newton step** (the ARM64 SIMD rsqrt made for
  vector normalization), then `N·L` diffuse, `N·H` Blinn specular (`^16` via four `FMUL` squarings),
  `amb + diff·N·L`, and a **gamma-corrected** `sqrt(base²·lambert + spec)` → sRGB.
- **Head/tail (<8 px/row) scalar mirror** (`RasterPixelShaded`/`RasterShadeColorAt`) — the same split p4.2b
  uses; the span body (the bulk of every row) is fully NEON.
- **Lighting is computed per fragment, not per vertex.** `HolyGLApplyLighting` (the old flat-at-v0 path) is no
  longer used by `HolyGLSubmitTriangle`; the triangle rotates its per-vertex normals into view space
  (`HolyGLViewNormal`) and hands them to the rasterizer. `RenderGoldenScene`/`RenderBench` force
  `RasterDisableGouraud()` so 2D never inherits a stale shade mode.
- **Texture + shading is not combined yet** (a textured span still uses the flat modulate colour); documented
  as a follow-up. `gmode` is forced 0 whenever `tex_ptr != 0`.

### D13. P4.6 fragment-shader VM architecture — DECIDED: register bytecode VM over a 2×2 NEON quad
- **Where it lives.** A new `apps/ShaderVM.HC` (Stage 5, after `HolyGL.HC`). It is deliberately NOT inside the
  rasterizer: the rasterizer keeps its fixed-function solid/Gouraud/Phong stages, and the VM is the programmable
  path for `$SHADER$` nodes. DolDoc (Stage 6) routes the procedural types to it by direct call (the SIC cell
  binds it, since ShaderVM loads first) — no `symbols_lookup` added, so the census is unchanged.
- **Machine model.** A **register** bytecode machine: 16 shader registers, each holding **four lanes** (a 2×2
  fragment quad, SoA: lane 0=(x,y), 1=(x+sx,y), 2=(x,y+sy), 3=(x+sx,y+sy)). One instruction word is 4×I64
  `[op, a, b, c]`. The ISA covers mov/movi, add/sub/mul/div/min/max, sqrt/rsq/abs/neg/floor/fract, sin/cos,
  len2/len3/dot2, mix/clamp/smooth, fragx/fragy/time, dfdx/dfdy, if/else/endif, jmp/jnz/jz, the library ops
  (perlin/fbm/mandel/sdfsphere/sdfbox/sdftorus) and out.
- **The arithmetic core is 128-bit NEON** (`ShaderOp4`, hand-encoded in `scripts/shader_quad.s`, 75 words): one
  instruction applies to all four lanes at once with 2× `.2d` ops (`fadd`/`fsub`/`fmul`/`fdiv`/`fmin`/`fmax`/
  `fsqrt`/`fabs`/`fneg`/`frintm`, and `frsqrte`+`frsqrts` for `rsq`). "4 px/iteration in NEON lanes" is this op core; the
  interpreter only does the per-lane masked blend of the result.
- **Derivatives via lane permutation.** `dFdx` = `(v1−v0, v1−v0, v3−v2, v3−v2)`, `dFdy` =
  `(v2−v0, v3−v1, v2−v0, v3−v1)` — the standard 2×2 screen-space derivative, exactly the quad's lane layout.
- **Execution masking.** `if r[a]` computes a 4-bit per-lane predicate and intersects it with the current mask;
  masked ops write only active lanes; `else`/`endif` restore via a mask stack. The built-in `mandel` program
  uses it as a real divergence loop (escaped lanes stop iterating).
- **Built-in library first, generic VM for custom shaders.** Native fast paths for Perlin gradient noise
  (`ShaderPerlin3`), multi-octave fBm (`ShaderFbm3`), the Mandelbulb distance estimator (`ShaderMandelbulbDE`,
  with `atan2`/`acos`/`log` implementations), and SDF primitives; a text assembler (`ShaderVMAssemble`,
  `mnemonic a, b, c` lines + labels) compiles custom shaders into the same bytecode. Built-in programs:
  animated gradient, shaded 2-D SDF disc (uses `dfdx/dfdy`), Perlin fBm, masked Mandelbrot.
- **Native 4-lane raymarcher.** `ShaderRaymarchQuad` marches a 2×2 quad (4 px/iteration) against a
  sphere+torus+ground-plane scene whose field (`ShaderField4`) is evaluated **4 lanes at a time through
  `ShaderOp4`**, shaded with a finite-difference normal + Blinn-Phong + gamma. Exposed as `shadervm`.
- **Root fix it depended on.** The VM's `F64 tmp[4]`/library arrays surfaced two latent `Compiler.HC` bugs:
  (a) a **local array's element floatness** was inherited from the *previous* declaration (never set on the
  local-array path), so `F64 a[3]; a[0]=1.0;` stored/loaded raw integer bits; (b) indexing a **pointer local**
  (`F64 *p; p[i]`) used the pointer's own floatness (always 0) instead of the **pointee** type. Both are fixed
  at the root (`g_hc_decl_float`/`g_hc_decl_elem_float` + `g_hc_local_elem_float`); regression
  `f64_local_array_assign`.
- **Golden invariant:** the VM is a separate path; `RENDER: PASS (0xD28836F)` is untouched (bit-exact).

### D14. P4.7 OBJ blocker — **ROOT-FIXED**: a local redeclared with a different type kept the FIRST type
- **Symptom.** `MeshSelfTest` faulted with `EC 0x25 (Data Abort)`, `ESR_EL1 0x96000005`, `FAR_EL1 ≈ 0x433A5BD60`
  (~18 GB, unmapped) inside `MeshParseOBJ`'s post-parse "fill missing normals" loop, evaluating `m->fni[b]`.
- **Root cause.** `HcAddLocalTyped` (`apps/Compiler.HC`) returned the existing slot on a redeclaration **without
  updating the local's type flags**. `MeshParseOBJ` declares `F64 b` in the `vn`/`v` branches and later `I64 b`
  in the fan/fill loops, so `b` kept `is_float = 1`. Using a float-typed local as an array index emits
  `ldr d0, [x0]` (which leaves **x0 = &b**) and the index code then does `mul x0, x0, #elem` → `&b × elem`, a
  wild address. Arithmetic confirms it: `(FAR − (m + off)) ÷ 8 = 0x77738150`, a kernel-stack address (`&b`).
- **Fix.** On redeclaration, update `g_hc_local_scales / is_ptr / is_float / elem_float / st_idx`. Safe because
  the compiler is **single-pass**: code already emitted for earlier uses keeps the old type; only later uses see
  the new one. The branches are mutually exclusive at run time, so the shared 8-byte slot is correct.
  Regression `redecl_float_int_index` (expect 30).
- **Why the earlier REPL probes all passed:** they used uniquely-named locals (`probe`, `k`) or literal array
  dimensions — never a name redeclared with a different type. The dead `#define HC_MAX_LOCALS 64` (unused; the
  real local table is 256 entries and overflows hard-error) was removed to stop it misleading future audits.

### D15. Struct-member array dimensions did not accept `N*M` / `N+M` — **ROOT-FIXED** (Compiler.HC + C seed)
- **Symptom (latent until P4.7).** `CMesh` declares `I64 fv[MESH_MAX_T * 3]` (and `fni`, `ft`). Both compilers'
  struct-member array parsers accepted only a **single number**, so `fv` recorded 512 elements (not 1536) and
  left `* 3]` for the member loop to skip. Every following member's offset was then wrong: `fni` @20512 (true
  28704), `ft` @24608 (true 40928), `sizeof(CMesh)` = 28704 (true 53280). The local-array and global-array
  parsers in both compilers already handled `*`/`+`; only the member path did not.
- **Fix.** Added the same `while (TOK_STAR || TOK_PLUS)` dimension fold to the member-array parser in **both**
  `apps/Compiler.HC` (self-hosted) and `boot/seed/jit_arm64.c` (C seed), so the two engines agree — the parity
  gate caught the seed's identical omission (it would otherwise have reported `1 diff`). Regression
  `member_arr_compound_dim` (expect 5).
- **Note:** in pure-HC the bug was self-consistent (definition and every use shared the wrong offsets), so it
  never surfaced as a render error — but it corrupted `sizeof` and any cross-engine layout. Fixed at the root.

### D16. P4.8 — one damage tracker, one present, one theme owner — **DECIDED**
- **The duplicate is gone.** P4.1 merged `GfxBackendPresent` into `GfxDevice`; P4.8 removes the *last*
  duplicate: the compositor's own damage bounding box (`g_comp.dmg_*`) and its write-only KolibriOS tile maps
  (`tile_dirty_map`, `win_tile_map`). `CompositorDamage{All,Rect,Window}` now forward to the ONE tracker
  (`GfxDeviceDamage` → `gfx_dirty_expand` → Render's `g_canv.dirty`; `gfx_dirty_all` for the full screen) and
  `CompositorPresent` reads that same rect through new `RenderDirtyActive()`/`RenderDirtyBounds()` before
  calling `GfxPresent`. WM's redraw predicate now tests `RenderDirtyActive()` instead of `g_comp.dmg_active`.
  Rationale: a second tracker can silently diverge from the draws that actually happened; the rasterizer's own
  dirty rect is the ground truth. Present semantics are unchanged (partial blit of the dirty rect, full blit
  when nothing is dirty, then reset).
- **Theme ownership moved.** `CThemePalette g_theme` + `ThemeApply` + `ThemeSetByName` + the `THEME_*` ids
  moved from `Compositor.HC` into a new `apps/Theme.HC` (Stage 6, before Compositor; **36** subsystems). WM,
  DolDoc and Compositor all read the same global. This de-risks P5 (which dissolves Compositor) — the palette
  survives on its own. Verified live with `theme latte`.
- **Dead-code purge (P4.8).** Deleted, all verified 0 call sites: `CompositorMain`, `CompositorDrawBox` (+
  `CBoxStyle`), `CompositorQueryTileOwner`, `CompositorStampWindowTiles`, `CompositorClearDamage`;
  `RenderIsZeroRamMode`, `gfx_mark_dirty`, `gfx_draw_circle`; `HolyGLApplyLighting` + `HolyGLGetViewportW/H`,
  `HolyGLTextureEnabled`, `HolyGLGetBound{,W,Data}`, `HolyGLTexOK` + the dead `gl*` aliases
  (`glPushMatrix/PopMatrix/Rotatef/Scalef/Color3f/Vertex2f`); `RasterGetDepthTest`, `RasterShadeMode`,
  `RasterTextureActive`. Census unchanged (181 — no allocator sites touched); symbol count drops.
- **Determinism gate (the exit criterion).** `scripts/determinism-gate.sh` boots the OS on 1 core and on N
  cores (`run-viewer-vm.sh` now honours `NEO_SMP`), runs the battery, and asserts the golden-frame hash is
  identical. Wired into `golden-boot.sh`. Result: `DETERMINISM: PASS (1 vs 4 cores identical: 0xD28836F)` —
  the rasterizer is single-core and IRQ-masked during the golden render, so SMP scheduling cannot perturb it.

### D17. HolyC has **no function forward declarations** — **ROOT-FIXED** (Compiler.HC / DolDoc.HC)
- **Symptom.** `DolDoc.HC` compiled (`res = 1`) but `DolDocExecTag` did nothing: `$FG,RED$` did not change the
  colour, `$BT$`/`$SL$`/`$AN$`/`$MA$` created no widgets/anchors/macros. The whole tag dispatcher was inert.
- **Root cause.** A prototype `U0 DolDocExecTag(U8 *tag);` is parsed by `HcParseProgram` as a *function
  definition* (`Type ident (` → `HcParseFunction`), which then consumes tokens looking for a `{ … }` body. The
  later real definition was therefore mis-registered/empty, so every call to `DolDocExecTag` hit an empty body.
- **Fix.** Removed every function prototype (`U0 DolDocExecTag(U8*);`, `U0 DolDocDrawNode(I64,I64);`). HolyC
  resolves forward *references* through the runtime symbol/function table — prototypes are unnecessary and
  harmful. **Rule: never write a `Type name(args);` prototype.**

### D18. HolyC rejects **comma-separated initialized declarations** — **ROOT-FIXED** (DolDoc.HC)
- **Symptom.** `U8 t0 = tag[0], t1 = tag[1];` left `t1` undefined/garbage, so every `t1 == 'X'` comparison was
  false and the dispatcher fell through.
- **Root cause.** The compiler's statement parser handles `Type a, b;` (no initializers) but not
  `Type a = expr, b = expr;` — only the first declarator is bound correctly.
- **Fix.** Split every such declaration into one statement per variable (`U8 t0 = tag[0]; U8 t1 = tag[1];`);
  18 sites in `DolDoc.HC`. **Rule: one initialized variable per declaration.**

### D19. Per-module compiler caps were too small for the new UI module — **RAISED** (Compiler.HC)
- `HC_MAX_FUNCS` (persistent function table) was **128**; `DolDoc.HC` now defines ~141 functions → `HcAddFunc`
  set `g_hc_error`. Raised to **512** (`g_hc_func_names/addrs/ret_float` resized).
- The per-function epilogue-patch cap was a literal **64** (`g_hc_epi_patches[64]`); a large two-letter tag
  dispatcher legitimately has 60+ `return`s → error. Introduced `HC_MAX_EPILOGUES 512`.
- Both are arbitrary ceilings, not semantic limits; raising them is the root fix. The C seed has no such table,
  so parity is unaffected; `self-host` and `PARITY 56/56 (0 diff)` stay green.

### D20. A global used **before its declaration** is implicitly sized to 8 bytes — **ROOT-FIXED** (DolDoc.HC)
- **Symptom.** `DolDoc.HC` compiled, but writing `g_comp.screen_w = …` during module execution corrupted the
  kernel heap; the *next* module (`Shell.HC`) then failed `GLOBAL ARRAY ALLOC FAILED g_shell_cmds`.
- **Root cause.** `DolDocSampleTelemetry` (defined earlier in the file) references `g_comp.fps`; the compiler
  implicitly registered `g_comp` as an 8-byte global at that point. The later `CCompositorState g_comp;`
  declaration was skipped (symbol already present), so `DolDocCompositorInit` wrote 13×I64 into an 8-byte block.
- **Fix.** Moved the `CCompositorState` class + `CCompositorState g_comp;` declaration to the top of the module,
  before any use. **Rule: declare a global before the first function that touches it.**

### D21. FNV-1a `hash % 128` is **signed-negative** → out-of-bounds bucket read — **ROOT-FIXED** (Shell.HC)
- **Symptom.** `Shell.HC` compiled but the OS BSOD'd while executing `ShellInit`'s command registrations:
  `Data Abort`, `FAR 0xBAD2CF896F69AD18` (a wild pointer), inside a strcmp loop.
- **Root cause.** `I64 b = (I64)(ShellHash(name) % SHELL_CMD_BUCKETS);`. `ShellHash` returns a `U64` whose high
  bit is often set; cast to `I64` it is negative, and C `%` is signed, so `b` landed in `[-127, 0]`. `g_shell_buckets[b]`
  read *before* the array, yielding a garbage chain index → `g_shell_cmds[garbage].name` → wild read.
- **Fix.** Use a power-of-two mask: `b = (I64)(ShellHash(name) & (SHELL_CMD_BUCKETS - 1));` (both in `ShellFindCmd`
  and `shell_register_cmd`). **Rule: for a power-of-two table, mask the hash; never signed-`%` a `U64`.**

### D22. P6 architecture — documents emit actions, the shell executes them — **DECIDED**
- **The cycle is broken.** `DolDoc.HC` no longer names any Shell function. Buttons/links/`$CM$` enqueue a
  `CDocAction{kind,target,val,payload}` into a 64-entry ring (`DolDocPushAction`); the shell drains it
  (`ShellDrainActions` → `ShellExecuteAction`). For the desktop loop (which lives in DolDoc), the Shell registers
  its pump via a function pointer (`DolDocSetPump(&shell_poll)`) — a callback, not a name coupling. The DAG is
  strictly `Shell.HC → DolDoc.HC`.
- **The ladder is gone.** `ShellRunCommand` splits `verb`/`args`, does an O(1) `ShellFindCmd` (FNV-1a), dispatches
  through the handler pointer, else tries `<verb>.HC` on RedSea, else feeds the raw text to the HolyC JIT.
- **Tools are documents.** `top` (live timer/CPU/KHeap/FPS + `$PB` bar + buttons), `filer` (per-file
  `[Open][Edit][Run]` buttons), `edit`/`editline`/`editsave`/`editchrun` (line-numbered buffer, save to RedSea,
  compile-and-run in place).
- **Idle.** The event loop calls `__wfe()` when a frame has no work (wakes on the 1 kHz timer PPI), else
  `task_yield()`.

### Open questions
- **P4.3/P4.5 color space:** P4.5 now shades in **linear light** and gamma-corrects to sRGB on output
  (`sqrt`), but the 2D golden path stays straight-alpha sRGB. Full pipeline unification (linear present +
  premultiplied alpha everywhere) is still open; the golden hash pins the 2D path.
- **SDF atlas:** bake from the built-in vector glyphs first (bootstrap) vs implement the full TTF parser first.
- **Handover timing:** keep the sovereign handover at the end of `KernelInit` (8 MB HolyC pool) or enlarge the
  sovereign pool to absorb Stages 2–6? (Current: unchanged; the 8 MB pool is idle during boot, so this is a
  memory-efficiency question, not a correctness one.)
- **>8-arg calls:** implement stack-arg spill vs keep the hard error and document the limit.
- **p4.3b:** ✅ DONE (see D8). **Gears geometry:** ✅ ROOT-FIXED (see D11).
- **P4.5 texture+shading:** combine the textured span with Gouraud/Phong (per-lane perspective `(u,v)` ×
  interpolated shade) — deferred; today a bound texture forces `gmode 0`.
- **P4.4 font blit:** the bilinear coverage read is scalar (per-pixel F64). It is a font subsystem, NOT the
  rasterizer (which stays fully NEON), so the NEON mandate is not violated; vectorizing the glyph blit (8 px/
  iteration) is a possible follow-up. Per-fragment SDF text can now use the P4.6 VM (see D13).
- **P4.6 follow-ups (not blocking):** (a) the VM's `ShaderOp4` op core is NEON, but the per-lane ray-march
  parameter update and the trig-heavy library ops (Mandelbulb) are scalar per lane — a full SoA library is a
  possible follow-up; (b) the built-in library and the bytecode VM are separate paths (native fast paths + a
  generic interpreter) — folding the library into bytecode is optional; (c) the raymarch demo presents in
  16-row bands because the per-lane march dominates; a tile-parallel version across the 4 cores (P9) is the
  natural scaling path. **P4.6 is ✅ DONE** (D13); the fragment-VM open question is resolved.
- **Compiler `*p` F64 deref (latent, not on the P4.6 path):** `HcParsePrimary`'s `*p` path always emits an
  integer-sized load and sets `g_hc_expr_float = 0`, so dereferencing an `F64 *` yields the raw bits as an
  integer. The VM uses `p[i]` (now correct via D13), not `*p`, so this is not exercised today; it should be
  fixed the same way (`g_hc_local_elem_float`) with a regression before any code relies on it.

---

## Part F — Decisions & resolutions (P7 planning, 2026-10)

- **D23 — P7 reframed: "HolyGL Sovereign Unification + Real Telemetry/Benchmark".** The old ladder treated P7 as
  "a benchmark". The forensic diff against the original C (`36ca4b0`) proved P4's "one pipeline" delivered the
  *core*, not the *engine*: HolyGL lacks the projection matrix stack + `glClear/glColor4f/glFlush`, there is no
  Sutherland–Hodgman near-plane clipper, `TILE_W/H=64` is declared but unused (no L1 binning, no SMP slicing),
  `Render` uses `memcpy`/scalar instead of NEON memory kernels, and `GfxDevice` has no `gpu_*` config plane /
  VirtIO batching / page-flip. P7 now closes all of those *and* measures the result with a real profiler and a
  real 40-phase suite. Authoritative text: `00-MASTER-PLAN.md` §11; runbook: `02-TASKLIST.md` §P7.
- **D24 — `tests/jit_golden/cases.json` is declared HISTORICAL.** `apps/SelfTest.HC` is the single source of
  truth (each case run through both engines in-process). `scripts/run-jit-golden.py` becomes a thin wrapper over
  `selftest`; no new cases are added to the JSON. "No outdated format" applies to tests and benchmarks alike.
- **D25 — Merge `Profiler.HC` + `PerfOverlay.HC` → one `apps/Telemetry.HC`.** (P7.5.) `BenchCpu.HC` +
  `BenchReport.HC` fold into `HolyBenchmark.HC`. This removes 3 modules (34 → 31); `apps/KernelInit.HC:111` and
  `scripts/golden-boot.sh:25` must both change to "31". NEITHER upstream nor current code uses the ARM PMU; P7.5
  adds it (`PMCR_EL0`/`PMCCNTR_EL0`/`PMEVCNTR*`) for instruction/memory-level profiling with minimal overhead.
- **D26 — Peephole optimizer moved to P7.0 (mandatory).** The original `boot/seed/jit_arm64.c:800` has a 3-pass
  peephole pass (stack round-trip collapse, dead moves, dead adds); `apps/Compiler.HC` does NOT. Every module
  compiled after Stage 1 therefore runs unoptimized machine code. Root-fixed at P7.0 **before** benchmarking.
  **Branch-safety constraint (critical):** `Compiler.HC` backpatches by instruction index (`HcBackpatchCbz/Cbnz/B`,
  `HcPushLoopCtx`/`HcPatchBreaks`/`HcPatchContinues` store `g_hc_code_len` at emit time), so *deleting* emitted
  instructions after the function is complete would corrupt every jump crossing the deletion. The peephole is
  therefore done **on-the-fly at emit time**, guarded by `g_hc_last_target_idx` (a branch/label target may not
  be collapsed), never as a post-pass over `g_hc_code[]`.
- **D27 — The 5-doc rule is enforced.** `ls docs/*.md` must list exactly `00`–`04`. The P7 planning docs (`05`,
  `06`, `07`) were merged losslessly into `01`/`03` (salvage), `00`/`02` (plan + runbook), and this Part F, then
  deleted. No extra `.md` in `docs/`.
- **D28 — At most 2 agents in parallel.** Never launch 3+ concurrently.
- **D29 — Array dimensions must accept any constant expression — ROOT-FIXED (Compiler.HC + C seed).** Root-found
  at P7.0: `U8 g_hc_target_bits[HC_CODE_CAPACITY / 8];` allocated **1 MB** (the `/ 8` was dropped), exhausting
  memory and breaking boot. Root-fixed by one precedence-climbing helper per engine
  (`HcDimPrec`/`HcParseArrayDimExpr`/`HcParseArrayDim` in `Compiler.HC`; `parse_array_dim_prec`/
  `parse_array_dim_expr`/`parse_array_dim` in `boot/seed/jit_arm64.c`) that folds `* / % + - << >>`, unary
  `+/-` and parentheses, replacing the three `Compiler.HC` and two seed inline `N*M`/`N+M`-only parsers. The
  literal workaround is gone (`[HC_CODE_CAPACITY / 8]` restored). Locked in by `SelfTestCheck`
  `array_dim_const_expr` (`16/2`, `2*3+1`) and `array_dim_shift_sub` (`1<<3`, `10-4`), both engines.
- **D30 — Struct function-pointer members (`Type (*fn)(...)`) — ROOT-FIXED (was NOT a codegen bug).** The former
  "null indirect call / absent `blr`" symptom was the **interactive shell silently truncating any input longer
  than 255 characters** (`SHELL_MAX_LINE 256`, `Shell.HC` dropped the overflow in `ShellPoll`): a pasted unit
  like `... p->calc(p,3); }` lost its tail, so the compiler genuinely saw a shorter program. `SHELL_MAX_LINE`
  is now 1024 (history arena resized to match). The struct-fnptr member dispatch itself was always correct —
  locked in by `SelfTestCheck("fnptr_member_dispatch", …, 210)`. The `U64 fn_addr` member in `Shell.HC` is an
  ordinary registry design, not a workaround. (The doc's old "missing `TOK_LPAREN`" explanation was wrong.)
- **P7.0 DONE (2026-10):** docs consolidated to exactly 5 files; peephole optimizer live in `Compiler.HC`
  (`[PEEPHOLE] runs=33 roundtrips=5600`); cross-module `g_hgl.*` writes purged (now `HolyGLColorPacked`);
  orphan `apps/TestJitP0.HC` removed; stale `p4.3-wip` branch deleted.
- **P7.0 AUDIT + D29/D30 ROOT FIX (2026-10):** `golden-boot.sh` gained `set -o pipefail` (the census gate could
  never fail before) and its SELFTEST floor was raised to 99; the screenshot stage no longer trips on curl's
  SIGPIPE. The C seed's statement parser now falls through to the generic expression parser for a statement that
  merely *begins* with an array index (`a[0] + b[1];`), and marks F64 array elements as float. Gate:
  `SELFTEST 99/99`, `PARITY 68/68 (0 diff)`, `CENSUS 181`, `SELF-HOST: PASS`, `DETERMINISM: PASS (0xD28836F)`,
  `GOLDEN BOOT: PASS`.
