# P1 COMPILER PERFECTION — AGENT DELEGATION SPEC

> Canonical instruction set for the P1 self-hosting push. Two agents work this:
> **Agent A** = compiler critical path (edits source, uses the VM, commits).
> **Agent B** = verification harness + migration specs (docs + host-only tooling, no VM, no source edits).
> Read this whole file before doing anything. Obey every guardrail.

---

## 0. Mission & Definition of Done

Make NeoOS self-host: `apps/Compiler.HC` (bootstrapped once by the C JIT) must compile **every** `.HC`
module, run it, and pass the golden gate. Then retire the C JIT.

**P1 is DONE only when ALL of these hold:**
1. `apps/KernelInit.HC` sets `g_hc_ready = 1` right after `Compiler.HC` loads and routes all later modules
   through `CompilerCompileAndRun` (see §9).
2. `scripts/golden-boot.sh` prints `GOLDEN BOOT: PASS` **with the flip ON**.
3. `CompilerSelfTest();` (over UART) reports **7/7**.
4. All **34** modules compile+run under `Compiler.HC` with **0** synchronous exceptions, **0** heap
   corruption, **0** undefined identifiers.
5. `scripts/compile-parity.sh` shows both engines agree (same module set compiled, same key globals) for
   all 34 modules.
6. Stage-2 blob embedded in `boot/main.c`; `compiler/jit_arm64.c` + `lexer.c` + `table.c` retired (or
   provably dead) without breaking the gate.

---

## 1. Environment & exact commands

- Repo: `/home/user/neo-os` (git, branch `main`). Persisted artifacts live in `/home/user/project`.
- Build: `make all` → `build/BOOTAA64.EFI`, `build/disk.img`, `build/redsea.img`.
- VM control: `scripts/run-viewer-vm.sh start|stop|restart|status`
  (QEMU; VNC 127.0.0.1:5900; monitor unix `/tmp/neo-os-mon.sock`; UART-in unix `/tmp/neo-os-uart-in.sock`;
  serial log `/tmp/neo-os-serial.log`).
- REPL: `scripts/uart-repl.py "cmd1" "cmd2"` (env `NEO_WAIT` seconds to wait, `NEO_SETTLE`).
- Golden gate: `scripts/golden-boot.sh` → must print `GOLDEN BOOT: PASS`.
- JIT battery: `scripts/run-jit-golden.py` (52 cases, `tests/jit_golden/cases.json`).
- Symbol audit: `scripts/audit-symbols.sh`. Crash decode: `scripts/crash-decode.py`. Screenshot diff:
  `scripts/screenshot-diff.py`.
- **Serialization lock:** the VM, the build dir, and the git index are singletons. Wrap every build/boot/
  test/commit/bundle in:
  `flock -w 900 /tmp/neo-os-vm.lock -c '<command>'`
  so the two agents never collide.

---

## 2. Guardrails (hard — never violate)

- **C only** in `boot/main.c` and `boot/uefi/*`. All OS logic is HolyC.
- **Never leave the tree red.** The self-hosting flip (§9) is a 3-line change — revert it before any
  commit unless P1 is fully done.
- **Golden gate must PASS after every committed change.**
- **No unbounded compiler buffers.** Caps must raise `g_hc_error` (hard error), never silently truncate.
- **No JIT miscompiles / no special-casing.** Fix the general codegen/parser path; never special-case a
  module name or a specific function.
- **No UI cycles:** `DolDoc⇄Shell`, `WM⇄Shell`, `WM⇄Compositor`, `DolDoc⇄Compositor` must stay broken.
- **Persist after every green step:**
  `git add -A && git commit -m "..."` then
  `git bundle create /home/user/project/neo-os.bundle --all`.
- The sandbox can reset and wipe `/home/user/neo-os` + `/tmp`. `/home/user/project` persists.

---

## 3. State of the world (already done — do NOT regress)

- **Golden gate PASS** with the flip OFF; tree clean at commit `1a99159`.
- `Compiler.HC` compiles **19** modules with 0 heap corruption; `RenderInit` runs; `FontMono` compiles.
  Boot reaches **Stage 5 (Math3D)**.
- All fixes in §6 are in place. Do not undo them.

---

## 4. Critical path (do in this order)

1. **Fix the `Math3D.HC` hang** in `Compiler.HC` (current blocker).
2. **March the module tail** (§8) one module at a time — each exposes one more codegen/parser bug.
3. **Flip module-by-module**, running the golden gate after each.
4. **Parity harness** — both engines, all 34 modules, diff.
5. **Stage-2 blob** — pre-compile `Compiler.HC`, embed in `boot/main.c`.
6. **Retire the C JIT** (`jit_arm64.c`/`lexer.c`/`table.c`) + dead `jit_run_self_tests`.

---

## 5. Debugging methodology (the proven recipe)

**Never guess. Reproduce minimally, instrument, fix the general path, verify, remove instrumentation.**

1. **Reproduce the hang.** Boot with the flip on (or a focused helper). The serial log shows
   `[KERNEL-INIT] Compiling Math3D.HC (... bytes)...` and then nothing → the hang is inside
   `Compiler.HC` (lexer/parser/codegen), not in the module's own execution.
2. **Bisect the source.** Extract `Math3D.HC` into halves and compile each via a temporary UART helper
   `I64 r = CompilerCompileAndRun("<snippet>");`. Halve until a single function/statement hangs.
   (Adding a temporary diagnostic command to a module is fine — remove it before committing.)
3. **Instrument the parser.** Temporarily add `doldoc_printf` in `HcLexNext`, `HcParseStatement`,
   `HcParsePrimary`, `HcResolveLValue` printing `g_hc_tok`, `g_hc_pos`, `g_hc_len`. Find the token where
   `g_hc_pos` stops advancing (the non-advancing token is the bug).
4. **Fix generally.** Correct the codegen/parse path in `Compiler.HC` (or `jit_arm64.c` if the C engine is
   also wrong — it must stay the golden reference). No shortcuts, no module special-casing.
5. **Verify.** Minimal repro passes → full module compiles+executes → `CompilerSelfTest()` 7/7 →
   `scripts/golden-boot.sh` PASS. Remove all instrumentation.
6. **Commit + bundle** under the flock (§1).

**Useful inspection tools:** QEMU monitor (`socat - unix:/tmp/neo-os-mon.sock`, `xp /Ni <addr>`,
`info registers`), `scripts/crash-decode.py`, `scripts/audit-symbols.sh`, `nm` on `build/BOOTAA64.EFI`.

---

## 6. Compiler bugs already fixed (do NOT regress)

**In `compiler/jit_arm64.c` (C JIT):** `&arr[i]` uses element size (`vt->scale`), not 8; frame-based
locals (recursion-safe, prologue `MOVZ X16,#n; SUB SP,SP,X16` = `0xCB3063FF`); `&function`; forward-struct
two-pass (`parse_struct_def` + `prescan_struct_defs`); read-path late-binding; `#include`; inline `asm{}`;
block comments; unresolved-symbol diagnostic; op-stack 256→4096; 17 safe name copies; caps→hard errors;
per-module table resets; 6 name-table copy bounds; `g_hc_arg_float[8]→[32]`; pool-write guards in
`HcBackpatchCbz/B`/`HcFinalizeFrame`.

**In `apps/Compiler.HC` (self-host target):** AArch64 intrinsics (`__wfe __sev __dmb_ish __dsb_sy __isb
__mrs_cntvct __mrs_cntfrq __mrs_mpidr __mrs_esr __mrs_far __dc_civac __ic_ivau __mmio_r32 __mmio_w32`);
global sizing from declared type (`HcFindStruct` + `g_hc_struct_sizes`, zero whole object); global
struct-type tracking (`HcRegisterGlobalStruct`/`HcGlobalStructIdx`); top-level array decls; `&` path
(`HcResolveLValue` handles vars AND functions); global-array deref fix (`HcRegisterGlobalArray`/
`HcGlobalIsArray` — only deref-load when NOT an array); SIC late-binding for forward calls
(`symbols_sic_cell`); variable late-binding (`symbols_var_cell`).

**In `kernel/symbols/symbols.{c,h}`:** `symbols_sic_cell`, `symbols_var_cell`, `symbols_report_unresolved`,
`symbols_lookup_or_reserve`. Registered in `boot/main.c`.

---

## 7. Known HolyC language limits (as compiled by the C JIT — must match in Compiler.HC)

- No `(void*)` casts — use `(U8*)`.
- Calls with **> 8 args** fail (args are X0–X7) — currently a hard limit; handle by hard-error or stack
  spill (tracked as B-tail item).
- `.HC` **globals are heap-allocated** by the JIT (`kmalloc` per global).
- `auto` tokenizes but is not consumed in some paths (candidate hang cause — see §8).
- Enums `TOK_*` already identical 0–70 between engines; unify to one enum later (C3).

---

## 8. Module tail (compile order) — current blocker + remaining

**Current blocker:** `apps/Math3D.HC` (495 lines) — hangs `Compiler.HC`.
Candidate constructs to check: `F64` structs + `->` member access on struct pointers, `F64 m[16]` array
member, `(F64)k` cast expressions, `#define` macros, chained `a->y * b->z - a->z * b->y`.

**Then, in order:** `RasterTile.HC`, `HolyGL.HC`, `Physics3D.HC`, `Gears3D.HC`, `Profiler.HC`,
`PerfOverlay.HC`, `BenchCpu.HC`, `BenchReport.HC`, `Compositor.HC`, `DolDoc.HC`, `WM.HC`, `Shell.HC`,
`ShaderEditor.HC`, `HolyBenchmark.HC`.

**Already compiling under `Compiler.HC`:** HalPlatform, Timer, Gic, Exceptions, KHeap, Symbols, Compiler,
Render, FontMono, FontVector, Sched, Smp, VirtioBlk, RedSea, Keyboard, Mouse, VirtioInput, VirtioGpu,
GfxBackend.

---

## 9. The flip (exact procedure — revert unless P1 fully done)

`apps/KernelInit.HC` currently:
- L9 `I64 g_hc_ready = 0;`
- L25 `I64 res = jit_compile_and_run(kinit_load_buf);`
- L104 `jit_compile_and_run("DolDocShellEventLoop();");`

Flip = restore exactly this (from commit `1a99159` reversed):
```c
// L25 region:
I64 res;
if (g_hc_ready) { res = CompilerCompileAndRun(kinit_load_buf); } else { res = jit_compile_and_run(kinit_load_buf); }
// after KInitLoad("Compiler.HC"); add:
g_hc_ready = 1;
```
Prefer flipping **one module at a time** (temporarily route a single module through `CompilerCompileAndRun`)
to isolate which module first breaks, then expand. Revert the flip to green before committing unless the
whole P1 DoD (§0) is met.

---

## 10. Commit + bundle protocol

```bash
flock -w 900 /tmp/neo-os-vm.lock -c '
  cd /home/user/neo-os &&
  git add -A &&
  git commit -m "P1: <what + why>" &&
  git bundle create /home/user/project/neo-os.bundle --all
'
```
Mirror docs to `/home/user/project/neo-os-docs/` when docs change.

---

## 11. AGENT A — Compiler critical path (edits source; owns VM)

**Owns (write access):** `apps/*.HC`, `apps/KernelInit.HC`, `compiler/*`, `kernel/symbols/*`, `boot/*`.
**Must NOT touch:** `docs/master/*` (Agent B owns), `tests/jit_golden/*` (Agent B owns), `scripts/*` (do
not create new scripts; use existing ones).

**Tasks, in order:**
1. **A1 — Fix the `Math3D.HC` hang** using §5. Definition of done: `Math3D.HC` compiles under
   `Compiler.HC` and executes; `CompilerSelfTest()` 7/7; `scripts/golden-boot.sh` PASS (flip reverted to
   green before commit). Commit + bundle (§10).
2. **A2 — March the tail (§8)** one module at a time. For each: reproduce → fix general codegen/parser →
   verify (self-test 7/7 + golden gate PASS) → commit + bundle. Stop and report if a fix would require a
   guard/shortcut or a `(void*)`-style hack.
3. **A3 — Handle >8-arg calls** (spill to stack or hard-error) so no tail module fails on it.
4. **A4 — Enable the flip** (§9) module-by-module; golden gate after each module. When all 34 modules
   compile under `Compiler.HC` with 0 exceptions / 0 undefined, leave the flip ON and commit.
5. **A5 — Stage-2 blob:** pre-compile `Compiler.HC`, embed the binary blob in `boot/main.c` so the C JIT
   is not needed to seed the compiler. Verify the gate still passes with the C JIT bypassed.
6. **A6 — Retire the C JIT** (`compiler/jit_arm64.c`, `lexer.c`, `table.c`, dead `jit_run_self_tests`) or
   mark provably dead. Keep `boot/main.c` + `boot/uefi/*` as the only C. Verify gate PASS.

**Reporting:** after each commit, report: module, root cause, fix, evidence (self-test + gate output),
commit hash. If blocked > ~20 min on one bug, report the minimal repro + instrumentation findings and
stop rather than guessing.

---

## 12. AGENT B — Verification harness + P2–P6 migration specs (NO source edits, NO VM)

**Owns (write access):** `docs/master/*`, `tests/jit_golden/*`, and **new** files `scripts/p1-*.sh`.
**Must NOT:** edit any `.HC`, `compiler/*`, `kernel/*`, `boot/*`; start/stop the VM; run the golden gate
(it needs the singleton VM and Agent A owns it). You may READ all source freely and run `bash -n`,
`python3 -m py_compile`, and static analysis.

**Tasks:**
1. **B1 — Author `scripts/p1-flip-test.sh`** (do not run it): boots with the flip on, waits for
   `Compiling <module>` lines, detects a hang (no new serial bytes for N seconds), dumps the last module
   and a crash decode, then reverts the flip. Make it flock-guarded. Document usage in the file header.
2. **B2 — Author `scripts/p1-parity.sh`** (do not run it): compiles every module with both engines (flip
   toggling per module), diffs the set of modules compiled + key globals + undefined-symbol reports.
   Emits a per-module PASS/FAIL table. This is the P1 DoD item #5 tool.
3. **B3 — Expand `tests/jit_golden/cases.json`** with edge cases discovered in the tail: F64 structs,
   `->` member access, array members `F64 m[16]`, `(F64)k` casts, macros, >8-arg calls, `&arr[i]`,
   forward calls, global arrays. Keep the JSON schema identical; validate with `python3 -m json.tool`.
4. **B4 — Static-analysis audit (read-only)** of the merge targets that are gated behind P1, and write
   `docs/master/P2-P6-MIGRATION-SPECS.md` with **file-level, function-level** migration steps for:
   - FontMono + FontVector → `Fonts.HC`
   - GfxBackend + VirtioGpu → `GfxDevice`
   - Render + RasterTile + HolyGL → one tiled NEON rasterizer (real Z-buffer, textures, SDF, fragment
     shader VM)
   - Profiler + PerfOverlay; Benchmark trio
   - `WM.HC` → DolDoc `$WIN$`/`$SPLIT$`; dissolve `Compositor.HC` into DolDoc
   - `Shell.HC` → action executor over a CDoc (break cycles)
   For each: exact call sites, globals to dedupe, files to delete, and the verification step. No code
   changes — spec only.
5. **B5 — Update `docs/master/NEXT-STEPS.md`** to reflect the current blocker (Math3D hang) and the
   exact P1 DoD from §0.

**Reporting:** list files written, key findings, and any place the spec disagrees with the code (with
`file:line`). Commit + bundle under the flock (§10).
