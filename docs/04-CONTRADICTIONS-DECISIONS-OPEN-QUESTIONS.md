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
- **P2.7 compiler-only bootstrap — PARTIAL.** Parser bug fixed (function after a top-level statement; commit
  `95ece53`) — `KHeap.HC`/`Symbols.HC` now compile under `Compiler.HC`. **Blocked** by a separate codegen bug:
  `Compiler.HC` mis-compiles `KHeap.HC`, corrupting the C-heap canaries at load. Until fixed, the C-JIT flip
  stays after `KHeap.HC`/`Symbols.HC` (seed still compiles 7 modules, not 1).
- RedSea in-place sector allocation / reclaim / dynamic `next_alloc_lba` — open (→ RedSea v2, doc 03 §9.5).
- Tracked binary artifacts in git — historical.
- No CI workflow — historical.
- **Compiler:** >8-arg calls hard error; `auto` hang risk; `#include` inside `Compiler.HC`; diagnostics; script-mode gaps (fnptr/F64-struct/forward-struct/cross-unit) — P1.1/P1.2. **New (found by the P0.5 expansion):** 2-D arrays fault (Data Abort); `enum` unsupported (returns -1); function-like `#define` unsupported (returns -1); an unterminated `struct {` is silently accepted (returns 0); a global-`F64` subtraction (`F64 r = 0.0 - q;`) returned 0; recompiling the whole battery twice in one boot trips a re-entrancy fault (guarded in `SelfTest.HC`).
- **Kernel:** one allocator/table/HAL; arm timer + IRQ; real scheduler; SMP queues; exception `x3`; `g_kernel_booting`×14 — P3.
- **Render:** `z_avg`; textures unsampled; no SDF/shader VM; VirtioGpu truncated commands; `BenchCpuMathNeon` LCG (BEN-01); synthetic telemetry (BEN-02); PMU absent — P4/P7.
- **DolDoc:** char grid; missing `$MA/$DA/$AN/$ID`/word-wrap; `g_doc_dirty_mask` shift; cycles; fake WM FPS/"4 Cores"; uptime wraps at 999 s — P5.
- **Shell:** dead `shell_register_cmd`; if/else ladder; cycles — P6.
- **Typing:** `%d`×~40; fnptr as `U64`; colors as `I64`; `int` truncation; signature mismatches — sweep.
- **Security/environment:** hardcoded host paths (fixed historically via `NEO_ROOT`); QMP socket single-client — historical.
