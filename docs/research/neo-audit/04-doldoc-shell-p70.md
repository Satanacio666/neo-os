# NeoOS Forensic Audit — P5 (DolDoc 3.0) · P6 (Reactive Shell) · P7.0 (Peephole + 5-doc rule)

Read-only audit. Repo: `/home/user/neo-os` @ `61b5546` ("P7.0: 5-doc consolidation + Compiler.HC peephole optimizer + hygiene").
Scope: `apps/DolDoc.HC`, `apps/Shell.HC`, `apps/SelfTest.HC`, `apps/KernelInit.HC`, `apps/Compiler.HC` (peephole ~805-995, driver ~3860-3890), `docs/00`–`04`, `scripts/golden-boot.sh`, `tests/jit_golden/cases.json`, `tests/census-baseline.txt`.

Legend: **[BLOCKER]** breaks correctness or lets the gate lie · **[HIGH]** real defect/workaround with runtime or gate impact · **[MED]** doc/consistency · **[LOW]** cosmetic/naming.

---

## 1. WM.HC / Compositor.HC dissolution

**Deletion confirmed.** `ls apps/` contains neither `WM.HC` nor `Compositor.HC`; `find . -iname 'WM.HC' -o -iname 'Compositor.HC'` is empty. `grep -rn 'g_wm' apps/` → no hits. All surviving references:

| Ref | Kind | Verdict |
|---|---|---|
| `apps/DolDoc.HC:13,249-250,1976-1978,2095` | comments ("dissolved from Compositor.HC/WM.HC") | stale comment, harmless |
| `apps/DolDoc.HC:252-267` `CCompositorState g_comp;` | live global (dissolved compositor state) | **LIVE** |
| `apps/DolDoc.HC:1980-2091` `DolDocCompositorInit/EndFrame/Dashboard/Cmd` | live functions | **LIVE** |
| `apps/DolDoc.HC:2115` `U0 wm_set_dirty()` | live function (dissolved WM entry) | **LIVE** |
| `apps/HolyBenchmark.HC:26` `wm_set_dirty();` | live call into DolDoc | **LIVE** |
| `apps/Shell.HC:655` `ShellCmd_compositor` → `DolDocCompositorCmd` | live | **LIVE** |
| `apps/KernelInit.HC:102-104` | comment ("WM.HC and Compositor.HC are dissolved") | stale comment, harmless |
| `apps/Theme.HC:4-7` | comments ("moved OUT of Compositor.HC", "WM, DolDoc and Compositor all read…") | stale comment |
| `apps/PerfOverlay.HC:23,62,119,133-134,165,168` | `wm_overhead_us` / `PerfOverlayRecordWmOverhead` | **LIVE fields**, legacy "wm" naming only |
| `apps/Profiler.HC:25,39-40,50,63,124,242,252,272,293,348` | `wm_us`/`wm_start_vct`/`wm_end_vct` fields | **LIVE fields**, legacy naming only |
| `scripts/p1-parity.sh:95-97` `g_wm.count`, `g_wm.screen_w`, `g_comp.tiles_x` | REPL probe list | **STALE** — see below |
| `scripts/p1-parity.sh:116-119` owners `"Compositor.HC"`, `"WM.HC"` | owner map | **STALE** |
| `scripts/interactive_uart_harness.py:269-273` `"run WM.HC"` / `WM.HC Window Manager Inspector` | manual harness stage | **STALE** |
| `scripts/_superseded/**` (test_p2_wm.py, test_p5_compositor.py, test_p6_storage.py, test_p7_smp.py, test_p8_holygl.py, test_wm_shell_switch.py, test_singlecore.py, …) | retired test scripts | stale by directory |

- `scripts/p1-parity.sh:95-97,116-119` — **STALE / HIGH** — probes `g_wm.count`, `g_wm.screen_w`, `g_comp.tiles_x` and attributes them to `WM.HC`/`Compositor.HC`. `g_wm` no longer exists anywhere in `apps/`, `CCompositorState` has **no `tiles_x` member** (`apps/DolDoc.HC:252-266`), and neither owner file exists. Any run of `p1-parity.sh` on these keys will fail/fault (or silently mis-attribute). Root-fix: drop `g_wm.*`/`g_comp.tiles_x` from `KEY_GLOBALS`, and re-own `g_theme.theme_id`→`Theme.HC`, plus add `g_comp.screen_w`→`DolDoc.HC` if a compositor probe is still wanted.
- `scripts/interactive_uart_harness.py:269-273` — **STALE / MED** — sends `run WM.HC`, a file that no longer exists; the harness stage will always fail. Root-fix: replace with `wm` (DolDoc desktop) or `compositor`.
- `apps/Theme.HC:4-7`, `apps/DolDoc.HC:13,249-250`, `apps/KernelInit.HC:102-104` — **LOW** — stale comments only; no code coupling. Root-fix: rewrite the comments to say "absorbed into DolDoc/Theme" (drop "Compositor.HC/WM.HC" names).
- `wm_overhead_us`/`wm_us` in `PerfOverlay.HC`/`Profiler.HC` — **LOW** — live metrics, misleading legacy name; will be removed by the pending P7.6 `Telemetry.HC` merge (`docs/02:1729` tracks it). No action now.

**No orphan symbol is a live reference to a deleted module.** The only genuine live coupling is `wm_set_dirty` (now a DolDoc function) and `g_comp` (now DolDoc state).

---

## 2. Strict DAG `Shell.HC → DolDoc.HC`

**PASS — no violation found.** `grep -ni 'shell' apps/DolDoc.HC` returns only comments (`:271-273`, `:293`, `:2201`, `:2327`). There is **no** direct call and **no** `symbols_lookup`/`SymLookup` of any `Shell*`/`shell_*` symbol:

- `apps/DolDoc.HC:933,935` — `SymLookup(vn/lbl)`/`symbols_lookup` on user widget vars (not Shell).
- `apps/DolDoc.HC:1452,1453,1467,1476,1597,1767` — lookups of `HolyGLRenderCube`, `HolyGLViewport`, `Gears3DRenderViewport`, `Physics3DRenderViewport`, `FontVectorDrawString`. None Shell.

The only touchpoints are exactly the three claimed, all defined in DolDoc and consumed by Shell:
- `apps/DolDoc.HC:295` `DolDocPushAction` (DolDoc emits; Shell drains).
- `apps/DolDoc.HC:307` `DolDocPollAction` (Shell calls `apps/Shell.HC:533`).
- `apps/DolDoc.HC:322` `DolDocSetPump` + `:293` `g_doc_pump_cb`, invoked at `apps/DolDoc.HC:2466` (`if (g_doc_pump_cb) g_doc_pump_cb();`); registered by Shell at `apps/Shell.HC:1061`.

Severity: none (design holds). Root-fix: none required. Optional hardening — add a `scripts/` lint asserting `rg -n 'shell_|Shell[A-Z]' apps/DolDoc.HC` matches comments only.

---

## 3. Defect register sweep D1–D30 (root-fix vs caller workaround)

Reviewed every decision in `docs/04` Parts C/E/F against the code. **Root-fixed at source:** D6 (`Compiler.HC:2209-2214` SCVTF promote), D7 (`:1846-1851` member elem width), D10/D11 (persistent F64-return table + `HcPrescanFuncs`, `:3860`), D13 (`g_hc_local_elem_float`), D14 (redecl updates flags), D15 (`:2592-2606` member dim `N*M/N+M`), D16 (one damage tracker/theme), D19 (caps raised), D21 (power-of-two mask), D1 (`HC_MODULE_MAX`), D2 (string arena), **D17** (`Compiler.HC:3339-3347` "D17 root fix: a forward prototype … must NOT publish a body"), **D18** (`Compiler.HC:3614-3621` "D18 root fix: multiple initialized globals in one declaration").

**Defects bypassed rather than root-fixed in `Compiler.HC` (besides D29/D30):**

1. **D4 — the 8-argument call cap is worked around with global out-parameters, not fixed by stack-spill.** `Compiler.HC:529-530` explicitly: *"caps function calls at 8 arguments — HcFindMember already takes 8 out-params."* and adds the global `g_hc_found_member_elem = 8` (`:530`), published at `:552,571`, read at `:1834`. The cap is a deliberate deferral (`docs/02:262`: "Stack spill is deliberately deferred … `known_over8_args`"), and callers avoid it (e.g. the former 9-arg raster debug print, per `docs/04:395-396`). — **[HIGH]** — Root-fix: implement X8+ stack-arg spill in `HcParseCall`/`HcParseFunction` and retire `g_hc_found_member_elem`, then promote `known_over8_args` out of `known`.

2. **D20 — "global used before its declaration is implicitly sized to 8 bytes" is worked around in the caller, not fixed with a global prescan.** The compiler pre-scans structs and functions (`Compiler.HC:3859 HcPrescanStructs()`, `:3860 HcPrescanFuncs()`) but there is **no global pre-scan**. The fix in place is the caller-side rule at `apps/DolDoc.HC:248-267` ("Declared before any use so that functions earlier in the module resolve `g_comp` to the real struct"). — **[HIGH]** — Root-fix: add `HcPrescanGlobals()` (mirroring the struct prescan) so a global referenced before its definition gets its real size/type, then the ordering rule becomes advisory, not load-bearing.

3. **`*p` dereference of an `F64 *` is still an integer-sized load (latent, unfixed).** `Compiler.HC:2203` `g_hc_expr_float = 0; // integer-sized dereference load`; `:2192-2198` only resolves a width for `*cast`/local-pointer, never the pointee F64-ness. Code avoids `*p` on F64 by using `p[i]` (`docs/04:676-679`). — **[MED]** — Root-fix: in `HcParsePrimary`'s `*` path set `g_hc_expr_float` from `g_hc_local_elem_float`/global floatness and emit an F64 load, with a regression.

**Note (doc↔code mismatch, not a bypass):** D17/D18 are documented as caller-side rules (`docs/04:597-613`, `docs/00:875` "Enforce D17/D18/D20 as a lint … no prototypes; one initialized var per decl"), but the compiler now **root-fixes both** (`:3339`, `:3614`) and `SelfTest.HC` has active passing regressions `fn_prototype_forward` (`:962`), `decl_comma_init` (`:960`), `decl_comma_global` (`:961`). The docs understate the fix state.

---

## 4. Peephole optimizer safety (`apps/Compiler.HC:809-990`)

**(a) NOP substitution never shifts indices — SAFE.** `HcOptimizePeephole` overwrites in place (`:935-936,942-943,962,979`) and never inserts/deletes, so the index-based backpatching (`HcBackpatchCbz/Cbnz/B` `:1082-1100`) and the break/continue stacks (`:1155,1163`) stay valid. It runs as a **post-pass** at `:3875` after `HcParseProgram`, not "on the fly" — see doc mismatch below.

**(b) No pattern alters NZCV — SAFE.**
- MOV emitted for the X1 retarget is `0xAA0003E1` = `ORR X1,XZR,X0`, **non-S** (`:942`) → flags untouched.
- Dead-move pass masks `(insn & 0xFFE0FFFF) == 0xAA0003E0` (`:958`), which excludes `ORRS` (`0xEA…`) and any shifted form (imm6 field is inside the mask) → only true `MOV Xd,Xd` is NOPed.
- Zero-add pass masks `(insn & 0xFFC00000) == 0x91000000` (`:974`); this fixes `sf=1,op=0,S=0,sh=0` and **excludes `ADDS` (`0xB1…`), `SUBS`, 32-bit `ADD` (`0x11…`), and shifted forms** (`sh` bit 22 is inside the mask) → only 64-bit non-flag-setting `ADD Xd,Xd,#0` is NOPed.
- The removed `STR/LDR` never set flags, so nothing flag-setting is deleted.

**(c) Branch-target bitmap covers all emitted branch kinds and the window — SAFE for the emitted ISA.**
- Bitmap build `:899-920` decodes **B** (`:903`, imm26 sign-extend correct), **B.cond** (`:907`, imm19 correct), **CBZ/CBNZ** (`:911`, `0x7E000000` mask drops `sf` so 32- and 64-bit both match, imm19 correct).
- The compiler only ever emits `B` (`HcBackpatchB` `:1100`), `CBZ` (`:1088`), `CBNZ` (`:1094`), plus `BLR`/`RET` — all covered or handled as barriers in `HcCanCollapse` (`:872-878`).
- Window check `:882-886` scans `k = p+1 … k <= q`, i.e. `(p,q]`. Excluding `p` is correct (a branch to the push is harmless: push+pop are net-neutral and the intervening code cannot touch `reg`/SP); including `q` is required (a branch to the pop must block).

**(d) X1-retarget is semantically correct — SAFE.** `:940-946` replaces `STR X0,[SP,#-16]!` at `p` with `MOV X1,X0` **at the push site** and NOPs the `LDR X1,[SP],#16` at `q`. `MOV X1,X0` captures X0 at `p`, exactly the value the original pushed, so later X0 mutations are irrelevant; `HcCanCollapse(p,q,1)` (`:941`) rejects any intervening instruction that reads or writes X1 or SP (`:879`), so writing X1 early is unobservable.

**Theoretical hazards (no current trigger, but worth a guard):**
- `Compiler.HC:847-853` — `HcInsnTouches` decodes single-register loads/stores but treats `LDP/STP` as single-register (only `Rt`/`Rn`, **not `Rt2` in bits 14:10**). The compiler emits pair ops only for the frame with SP base (`:1041 0xA9BF7BFD`, `:1061 0xA8C17BFD`), which are rejected via `rn==31`, so there is no live hazard. **[LOW]** Root-fix: reject any instruction matching the pair-load/store class outright, or decode `Rt2`.
- `Compiler.HC:866-888` — `HcCanCollapse` rejects `BLR/BL/SVC/RET/B/B.cond/CBZ/CBNZ` but **not `BR`/`TBZ`/`TBNZ`**. The compiler emits none (verified: no `0xD61F0000`/`0x36000000` emitters), so no live hazard. **[LOW]** Root-fix: add the `BR`/`TBZ`/`TBNZ` barriers defensively.

**Doc↔code mismatch (finding for §5):** `docs/04:699-706` (D26) states the peephole is done "**on-the-fly at emit time**, guarded by `g_hc_last_target_idx` … **never** as a post-pass over `g_hc_code[]`." The code is the opposite: a **post-pass** (`:3875`) with a **target bitmap**, and `g_hc_last_target_idx` **does not exist anywhere in the repo**. It is safe precisely because it NOPs instead of deleting, which the doc's premise ("deleting … would corrupt every jump") does not anticipate. — **[MED]** — Root-fix: rewrite D26 to describe the actual NOP + bitmap post-pass.

---

## 5. 5-doc rule + docs integrity

**`ls docs/*.md` = exactly `00`–`04` — PASS** (`00-MASTER-PLAN.md`, `01-REALITY-AUDIT.md`, `02-TASKLIST.md`, `03-IDEAS-AND-RESEARCH.md`, `04-CONTRADICTIONS-DECISIONS-OPEN-QUESTIONS.md`). No extra top-level `.md`.

Caveat: `docs/_superseded-old-docs/` still holds **40 `.md`** files (`master/`, `root/`) that D27 was meant to retire; they are not matched by the `docs/*.md` glob but are still tracked. `docs/research/*.md` (2 files) is allowed by D5. — **[LOW/MED]** — Root-fix: delete `docs/_superseded-old-docs/` (or `git rm`) since the consolidation is claimed lossless.

**Internal contradictions (doc claims vs code / vs each other):**

1. `docs/00-MASTER-PLAN.md:65` — P7 status `⬜` ("not started") vs `docs/04:724-727` **"P7.0 DONE"** and `docs/02:1065` "P7.0 ✅ DONE" and the live peephole gate (`golden-boot.sh:31-40`). — **[HIGH]** — Root-fix: set P7 row to `🟡 P7.0 DONE`.
2. `docs/04:183` (A24) "`DolDoc.HC` is a **char grid**; no `CDoc`/`CTree`; no OmniTape buffer [STUB]/[MISSING]" and `docs/04:357` (Part E) "DolDoc: char grid; missing `$MA/$DA/$AN/$ID`/word-wrap…" — **contradict the code and docs 00/01/03**: `apps/DolDoc.HC:5-7` says the char grid is gone, `CDocNode g_doc_nodes[]` (`:86,204`), `g_doc_attr` (`:206`), `OmniTapeAppendNode` (`:351`), and the tag dispatchers `$WW` (`:1154`), `$AN` (`:1161`), `$LK` (`:1181`), `$DA` (`:1214`), `$ID` (`:1219`), `$MA` (`:1232`), word-wrap (`:491,581`). `docs/00:63`, `docs/01:153`, `docs/03:34` correctly say REAL. — **[MED]** — Root-fix: mark A24/Part E rows as superseded-by-P5, not open.
3. `docs/00:58` P0.5 "80/80 + parity 54/54" vs actual **96/96** active and parity **64/64** (`docs/04:726`, `docs/02:1068`). Same stale "80/80 / 54/54" throughout `docs/01:34,171` and `docs/02:61,220,314,343,385,396,409,423`. — **[MED]** — Root-fix: re-baseline all counts to 96/96 + PARITY 64/64.
4. `docs/01-REALITY-AUDIT.md:9` says `SELFTEST 87/87 · PARITY 56/56` while `docs/01:34` and `:171` say `80/80`/`54/54` — internally inconsistent within one doc. — **[MED]**.
5. `docs/01:307` "a new `apps/Theme.HC` (Stage 6, before Compositor; **36** subsystems)" vs `KernelInit.HC:110-111` banner and loader = **34** (verified count of loaded modules) — **[MED]**.
6. `docs/02:97` "`tests/jit_golden/cases.json` actually holds **75** cases (1 `known`), i.e. **74/74** active" — the JSON holds **89** case objects (88 active + 1 `known`) and `SelfTest.HC` holds **96** active. — **[MED]**.
7. `docs/00:875` "Enforce D17/D18/D20 as a lint (no `Type name(args);` prototypes; one initialized var per decl…)" vs `Compiler.HC:3339`/`:3614` which **root-fix D17/D18** and the active passing regressions (`SelfTest.HC:960-962`). Only D20 remains a real ordering rule. — **[MED]**.
8. Dangling references to docs deleted by D27: `docs/00:287,292,307,434,457,815`, `docs/02:1071,1079`, `docs/03:594` cite `docs/05-UPSTREAM-SALVAGE-AUDIT.md`, `docs/06-PERFECTED-PRIORITY-PLAN.md`, `docs/07-P7-EXECUTION-BLUEPRINT.md`, none of which exist. — **[LOW]** — Root-fix: point at the merged sections in `01`/`02`.

**Feature-done claims the code does not implement (correctly marked pending):** the `Telemetry.HC` merge (`docs/00:119,143,546,873`, `docs/02:1100,1405-1466`) is **not** done — `Profiler.HC`/`PerfOverlay.HC`/`BenchCpu.HC`/`BenchReport.HC` still exist and `KernelInit.HC:97-100` still loads all four. That is consistent with P7.5 being future work.

---

## 6. Test-format truth

- **`apps/SelfTest.HC` is the source of truth; JSON is not gated — CONFIRMED.** `tests/jit_golden/cases.json` is referenced only by `scripts/run-jit-golden.py:12`; `scripts/golden-boot.sh` never calls it (it uses the in-guest `selftest` sentinel `:50-51`, `self-host-test.sh` `:248`, `determinism-gate.sh` `:251`, and `census-c-runtime.sh` `:245`). D24 holds.
- **Real active case count = 96**, not the claimed 74:
  - `SelfTestCheck(` call sites = 70, `SelfTestCheck2(` = 18, `SelfTestCheck3(` = 6, `SelfTestReject(` = 1, `SelfTestInclude()` = 1 → **96** (`SelfTest.HC:877-993,986`).
  - `SelfTest.HC:13` header comment "**74** active cases are the exact corpus from `tests/jit_golden/cases.json`" is **stale on both counts** (74≠96; and the JSON has 88 active, not 96, so it is not the same corpus). — **[HIGH]** — Root-fix: correct the comment to 96 and stop claiming JSON equivalence (D24 already declares it historical).
- **Golden gate SELFTEST floor does not match the real count.** `scripts/golden-boot.sh:60` requires `a >= 74` (comment at `:58` says `"74/74"`). Real is 96, so **up to 22 cases could be silently deleted and the gate would still pass** (a==b is also trivially satisfied). `docs/02:1118,1698` repeats the `>= 74` floor. — **[HIGH]** — Root-fix: raise the floor to the real count (96) or, better, assert `a >= <frozen>` from a single source and fail on any drop.
- **`known`-tagged / excluded tests:**
  - `known_over8_args` — the only `known` case: `SelfTest.HC:994` (`SelfTestKnown`, not counted) and `cases.json:675-682` (`"known": true`). It is the 9-arg (D4 cap) case; it is *expected* to fail and is reported separately (`SelfTest.HC:123-133,1018-1020`).
  - **The D30 struct-function-pointer case is excluded entirely** — no `Type (*fn)(...)` member test exists in `SelfTest.HC` or `cases.json` (grep for `I64 (*`/fnptr members in `apps/` returns nothing). This matches `docs/04:717-723`. `fnptr_indirect_call` (`SelfTest.HC:974`) is the *address-of-function* path (works); it is **not** the D30 struct-member fnptr path.
  - `SelfTestKnown` total = 1 (`SelfTest.HC:994`); header comment `:14` "1 additional case is `known`" is correct.

---

## 7. Census / gate integrity

- **Baseline sums correctly.** `tests/census-baseline.txt` = 55+52+38+26+1+1+1+1+1+5 = **181**. `bash scripts/census-c-runtime.sh` prints `CENSUS: PASS (181 total .HC->C runtime calls, none increased)` (rc=0). Match. — **PASS**.
- **[BLOCKER] The census gate cannot fail `golden-boot.sh`.** `scripts/golden-boot.sh:245`: `"$ROOT/scripts/census-c-runtime.sh" | tail -1 || fail=1`. The script sets only `set -u` (`:7`) — **no `set -o pipefail`** — so the pipeline's exit status is `tail`'s (always 0) and the `|| fail=1` branch is dead. A `CENSUS: FAIL` (i.e. a regression that *increases* `.HC→C` calls) would print but the overall gate would still report `GOLDEN BOOT: PASS`. — Root-fix: add `set -o pipefail` (or capture rc before piping: `census-c-runtime.sh || fail=1`).
- **[HIGH] The gate cannot detect silently removed tests.** Two independent holes:
  1. `scripts/golden-boot.sh:60` floor `a >= 74` vs real 96 (§6) — a 22-case deletion passes.
  2. The parity check (`:67-73`) only asserts `"0 diff"`; there is **no minimum parity total**, so removing cases reduces the denominator and still reports `0 diff`. `TWINS: 5/5` (`:75`) is fixed, so that one is safe.
  3. The census itself only fails on **increases** (`census-c-runtime.sh:49-54`); removals print `[DOWN]` and are ignored, so it is a one-directional guard and cannot catch deleted tests either.
  — Root-fix: assert exact SELFTEST/PARITY totals (or `>=` frozen totals) and make the census also fail on unexpected decreases for symbols whose counts are load-bearing.

---

## Prioritized root-fix list

1. **[BLOCKER]** `scripts/golden-boot.sh:245` — add `set -o pipefail` (or drop the pipe) so `census-c-runtime.sh`'s exit code can fail the gate.
2. **[HIGH]** `scripts/golden-boot.sh:60` — raise the SELFTEST floor from 74 to the real 96 and assert a frozen minimum for PARITY too; prevents silent test removal.
3. **[HIGH]** `scripts/p1-parity.sh:95-97,116-119` — remove stale `g_wm.count`, `g_wm.screen_w`, `g_comp.tiles_x`; re-own `g_theme.theme_id`→`Theme.HC`; add `g_comp.screen_w`→`DolDoc.HC` if a compositor probe is wanted.
4. **[HIGH]** `apps/Compiler.HC` — root-fix the 8-arg cap (stack-arg spill) and retire the `g_hc_found_member_elem` global out-param (`:529-530,552,571,1834`); promote `known_over8_args` out of `known`.
5. **[HIGH]** `apps/Compiler.HC` — add `HcPrescanGlobals()` so a global referenced before declaration is sized/typed correctly; makes the D20 caller ordering rule non-load-bearing (`DolDoc.HC:248-267`).
6. **[HIGH]** Docs: reconcile P7 status (`docs/00:65` ⬜ vs `docs/04:724`, `docs/02:1065`), re-baseline all SELFTEST/PARITY counts to 96/96 + 64/64 (`docs/00:58`, `docs/01:9,34,171`, `docs/02:61,97,220,314,343,385,737,763,805,843,871,982,1141`), and fix the "74 active / JSON corpus" claim (`SelfTest.HC:13`).
7. **[MED]** `docs/04:183` (A24) and `docs/04:357` (Part E) — mark "char grid / missing `$MA/$DA/$AN/$ID`" as superseded by P5 (code implements CDoc/CTree, tags, word-wrap).
8. **[MED]** `docs/04:699-706` (D26) — rewrite to describe the actual NOP-based post-pass with the target bitmap (there is no `g_hc_last_target_idx`); add defensive barriers for `BR`/`TBZ`/`TBNZ` and pair load/store in `Compiler.HC:847-853,866-888`.
9. **[MED]** `apps/Compiler.HC:2203` — fix `*p` on `F64 *` to load/flag floatness correctly (with regression).
10. **[MED]** `scripts/interactive_uart_harness.py:269-273` — replace `run WM.HC` with the dissolved `wm`/`compositor` path.
11. **[LOW]** Delete tracked `docs/_superseded-old-docs/**` (40 stale `.md`) and fix dangling `docs/05/06/07` references (`docs/00:287,292,307,434,457,815`; `docs/02:1071,1079`; `docs/03:594`).
12. **[LOW]** Refresh stale comments in `apps/Theme.HC:4-7`, `apps/DolDoc.HC:13,249-250`, `apps/KernelInit.HC:102-104`; rename/retire `wm_*` metric fields in `PerfOverlay.HC`/`Profiler.HC` during the P7.6 `Telemetry.HC` merge.
