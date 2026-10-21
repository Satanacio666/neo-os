# Next Step — Isolate & Fix the `Compiler.HC` corruption on `Render.HC`

**Objective:** make `Compiler.HC` compile **Render.HC** (then every module) with **no heap corruption**, unblocking the boot flip (P1.3) and the Stage-2 blob (P1.5).

**State:** P1.1 hardening done (op-stack, name copies, caps→errors, `g_hc_error`) — self-test 7/7, golden gate PASS. Flip reverted (safe). Remaining symptom:
```
[HEAP] FATAL: Memory corruption detected at block 0x7B056860!
[SYMBOLS] Failed to allocate symbol: RenderDrawRect
[EXC #1] EC=0x25 Data Abort | Insn=0xF9000040 (str x0,[x2]) | FAR=0x2B9B2B9376C8BF08
```

**Invariants:** never leave the tree red; revert the flip after each experiment; golden gate green after every change; persist (commit+bundle) after every green step.

---

## Hypotheses (test in order)
- **H1 — miscompiled construct:** Render.HC uses a construct `Compiler.HC` codegens wrong (class member `->`, multi-dim array, nested call, `#define`, or a function-pointer member). → a store to a garbage address.
- **H2 — per-module state not reset:** `g_hc_func_count` / `g_hc_struct_count` are reset **only in `HcInit`** (once), not in `HcReset` → they **accumulate across modules**; the struct table then aliases/misindexes, and `g_hc_member_names[st_idx*16+m_cnt]` computes wrong slots. **Strong suspect.**
- **H3 — pool/heap interaction:** the 4 MB `g_hc_code` pool allocated at `HcInit` collides with or fragments the heap.
- **H4 — another unbounded buffer** not yet found (member slots `fp_slot`, struct sizes, etc.).

---

## Task list (phased, each task verified)

### Phase A — Instrument (make the failure observable)
- **A1.** Add a **safe compile probe**: a shell/UART command `hcprobe("source")` (or reuse `CompilerCompileAndRun`) that returns `-1` on `g_hc_error` and prints the failing construct/line. *(Compiler.HC already prints "internal error" on `g_hc_error`; extend it to print `g_hc_pos` + a token snapshot.)*
- **A2.** Add a **heap-corruption tripwire**: after each `CompilerCompileAndRun`, call `kheap_is_valid_ptr` / re-read a canary on `g_hc_code`; print PASS/FAIL. (Cheap: verify `g_hc_code[0..3]` canary + `g_hc_code_len <= CAPACITY`.)
- **A3.** Build + boot; confirm the probe reports cleanly on a *small* module and FAILS on Render.HC.

### Phase B — Bisect Render.HC to the minimal corrupting construct
- **B1.** Split Render.HC: compile **classes only** (`CClipRect/CDirtyRect/CCanvasState`) → probe.
- **B2.** Compile **`RenderInit` alone** (no classes) → probe.
- **B3.** Compile **groups of 5 functions** (binary search the 45) → find the first group that corrupts.
- **B4.** Reduce the failing group to the **single function**, then to the **single statement/expression** (by trimming).
- **B5.** Record the exact construct → maps to H1 or H4.

### Phase C — Diagnose the mechanism
- **C1.** If **H2** (state accumulation): print `g_hc_func_count`, `g_hc_struct_count`, `g_hc_member` slot before/after each module. If they grow unboundedly, **fix: reset all counts in `HcReset`** (not just `HcInit`) — but *keep the pool* (`g_hc_code`) so already-emitted code stays valid; re-emit per module is fine because each module re-registers symbols.
- **C2.** If **H1** (construct): read `HcParsePrimary`/`HcParseStatement` for the failing construct; compare with the C JIT's handling; fix the codegen.
- **C3.** If **H3** (pool): print the `kmalloc` result + address range of `g_hc_code`; verify no other allocation overlaps. Consider a **separate static BSS pool** instead of `kmalloc` (no heap interaction).
- **C4.** If **H4**: add bounds to the offending buffer (`fp_slot`, struct sizes, member slots) → `g_hc_error`.

### Phase D — Fix & verify
- **D1.** Apply the minimal fix from C.
- **D2.** Re-run the probe on Render.HC → must be clean; self-test still 7/7.
- **D3.** Re-attempt the flip **for Render.HC only** (compile it with `Compiler.HC` while the rest use the C JIT) → boot must stay green.
- **D4.** Flip **module-by-module** in load order (Render → FontMono → … → Shell), running the golden gate after each. On the first failure, return to Phase B for that module.
- **D5.** When all 34 modules compile via `Compiler.HC`: run the **parity harness** (compile every `.HC` with both engines, diff).
- **D6.** Then **P1.5** (Stage-2 blob) and **P1.6** (retire the C compiler).

---

## Verification per task
- **Golden gate** (`scripts/golden-boot.sh`) green.
- **Self-test** `run Compiler.HC` = 7/7.
- **Probe** on the target module returns clean (no `g_hc_error`, no heap trip).
- **Manual UART** check of the specific behavior.
- **Persist** (commit + bundle) after each green step.

## Rollback
- The flip is a 2-line change in `KernelInit.HC` (`g_hc_ready` branch); revert instantly.
- Each Phase-C fix is isolated; if it regresses, revert that edit and return to the previous green commit.

## Definition of done (this step)
`Compiler.HC` compiles **all 34 modules** with **zero heap corruption**, self-test 7/7, golden gate PASS — i.e. the flip is stable and the C compiler can be retired.
