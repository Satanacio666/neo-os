# NeoOS P3 (Kernel Correctness) — Forensic Audit

- **Repo:** `/home/user/neo-os` @ `61b5546` ("P7.0: 5-doc consolidation + Compiler.HC peephole optimizer + hygiene")
- **Mode:** READ-ONLY. No repo file was modified; this report is the only artifact written.
- **Scope:** `apps/{KHeap,Symbols,Sched,Smp,Gic,Timer,HalPlatform,KernelInit,Exceptions}.HC`, `boot/runtime/{kheap,symbols}.c`, `kernel/arch/aarch64/{vectors,smp_entry}.S`, `kernel/sched/switch.S`, plus `docs/02-TASKLIST.md` §P3 and `docs/04-CONTRADICTIONS-DECISIONS-OPEN-QUESTIONS.md`.
- **Method:** line-by-line read of every in-scope file; exhaustive `grep` for call sites, cross-module globals, and intrinsic usage; cross-checked against the claimed P3 exit gates (`SOVEREIGN/TICK/SCHED/BSOD/SMP`).

**Headline:** P3's *mechanisms* exist and the boot gate is plausible on QEMU-virt, but the **sovereign handover is not complete** (the C seed allocator + symbol table remain live and are still invoked post-handover), the **symbol table is entirely unsynchronised** under a 1000 Hz preemptive IRQ on 4 cores, and the **exception recovery path is structurally unsound** (eret into a new PC without unwinding SP). Details below.

---

## 1. Sovereign handover completeness

### 1.1 The C seed allocator is NOT frozen — it is still allocated from after handover — **BLOCKER**
- `apps/KHeap.HC:492-496` `KHeapHandover()` SIC-patches only `kmalloc`→`KMalloc` and `kfree`→`KFree`. It is called at `apps/KernelInit.HC:126`.
- But immediately **after** handover, `apps/KernelInit.HC:137` calls `jit_compile_and_run("DolDocShellEventLoop();")` — this is the **C seed JIT**, not the `.HC` compiler.
- The C JIT calls `kmalloc`/`kfree` **directly (static C link)**, not through a SIC cell, so the hot-patch does not affect it. Concrete sites in `boot/seed/jit_arm64.c`: `:102`, `:120`, `:907`, `:935`, `:1265`, `:2140`, `:2391`, `:2625`, `:2762`, `:2765`, `:2795`, `:2843`, `:3421`, `:3576`, `:3695`, `:3730` (22 `kmalloc`/`kfree` call sites total).
- Therefore the C seed heap (`boot/runtime/kheap.c`) continues to be mutated at runtime. The "frozen at handover" invariant (`docs/02-TASKLIST.md:444-450`) is **violated**.
- **Root fix:** delete the C JIT from the runtime path (make `CompilerCompileAndRun` the only executor) or route `jit_arm64.c`'s allocations/registrations through the SIC cells (e.g., call `symbols_lookup("kmalloc")` once at init and indirect through it). Also remove the `KernelInit.HC:137` C-JIT invocation.

### 1.2 The C seed symbol table is NOT frozen — two live tables — **BLOCKER**
- `apps/Symbols.HC:259-272` `SymbolsHandover()` patches `symbols_lookup/is_defined/is_func/is_var/var_cell/sic_cell/register` then ingests a **snapshot** of the C table via `symbols_foreach(&SymIngest)` (`:271`).
- The C JIT still writes into the C table after that snapshot: `boot/seed/jit_arm64.c:2579` (`symbols_register(name, fn_cb.code, SYM_FUNC)`), `:2627`, `:2767`, `:2797`, `:2845`, `:3578`, `:3599-3602`; and reads it via `symbols_lookup_entry` (`:684`, `:1148`, `:1512`, `:2018`, `:2040`, `:2478`, `:2620`, `:2692`, `:2718`, `:2735`, `:2790`, `:2838`). 34 direct C symbol call sites.
- These post-handover registrations **never reach the `.HC` 1024-bucket table**. The seed table is not frozen and the two tables diverge. `docs/04-...:317-323` claims the seed is "frozen at handover" — **not true**.
- **Root fix:** same as 1.1 — eliminate the runtime C JIT; if kept, funnel it through the SIC cells.

### 1.3 `SymLookupCanonical`'s "bootstrap fallback" is self-referential after handover — **HIGH**
- `apps/Symbols.HC:294-304`: after patching, `symbols_lookup` **is** `SymLookup` (same table). So the "fallback to Ring-0 bootstrap symbol table" at `:295/:299/:303` re-queries the same `.HC` table; the C table is unreachable through this path. Any symbol registered only in the C table post-handover is invisible to canonical lookup.
- **Root fix:** drop the fallback (redundant) or keep an explicit, separate seed-table handle captured before patching.

### 1.4 Handover order, atomicity and the `SymbolsHandover` window — **MED**
- Order is correct in intent: `KHeapHandover()` (`KernelInit.HC:126`) runs while `symbols_register` is still the C function, so the "kmalloc"/"kfree" C entries are updated in place before ingest; `SymbolsHandover()` (`:127`) then patches the API and ingests. `kmalloc`/`kfree` already exist in the C table (`boot/main.c:254-255`), so no allocation occurs during `KHeapHandover`.
- `SymbolsHandover` patches `symbols_lookup` (`:263`) **before** ingesting (`:271`), creating a window where the `.HC` table is empty/incomplete while the API already points at it. This window is not locally IRQ-masked or locked. It is *incidentally* safe because the whole of `KernelInitMain` runs with IRQs masked (`boot/main.c:323`, `apps/Exceptions.HC:245`), and `enable_interrupts()` is not called until `KernelInit.HC:133`. **Atomicity holds by boot ordering, not by an enforced guard.**
- **Root fix:** mask IRQ + take a lock around both handovers, and assert `g_kheap_boot_pool != 0` and full ingest success.

### 1.5 `KHeapHandover` fails silently if the sovereign pool is missing — **MED**
- `apps/KHeap.HC:493` `if (!g_kheap_boot_pool) return;` — if the 8 MB pool allocation failed at load (`:503`), handover silently no-ops and the C seed allocator stays the runtime owner with no diagnostic. Contradicts "no silent failure".
- **Root fix:** print a FATAL and set a boot-failure flag.

### 1.6 `SymbolsHandover` has no ingest-failure handling — **MED**
- `apps/Symbols.HC:271` `symbols_foreach(&SymIngest)`; `SymIngest`→`SymRegister`→`kmalloc(sizeof(CSymbol))` (`:177`) can return 0 on OOM and is ignored (`:178`), yielding a silently partial symbol table.
- **Root fix:** count ingest successes and abort/flag on mismatch with `symbols_count()`.

### 1.7 The sovereign pool physically lives inside the C heap, and `kheap_get_stats` mixes the two heaps — **MED**
- `apps/KHeap.HC:503` `g_kheap_boot_pool = kmalloc(8388608)` allocates the `.HC` pool from the **C heap**, so both allocators own the same physical region (disjoint only because the pool is a live C allocation).
- `apps/KHeap.HC:278-321` `kheap_get_stats` walks from `g_uefi_heap_base` treating the C heap as a chain of `CHeapBlock` (48 B headers), then follows `next` pointers into the sovereign pool's `.HC` free list (`:305`). Layouts happen to match (`HEAP_BLOCK_HEADER_SIZE 48` = `sizeof(heap_block_t)` = 48), so no crash, but the "32 MB physical heap telemetry" mixes C and `.HC` accounting. `guard < 65536` and the bounds check (`:293-295`) prevent runaway.
- **Root fix:** publish separate C-heap vs sovereign-heap telemetry; never walk one allocator's freelist with the other's header convention.

### 1.8 Duplicate global ownership: `g_uefi_heap_base` / `g_uefi_heap_size` — **MED**
- Defined in both `apps/KHeap.HC:32-33` and `boot/main.c:109-110`. The C symbols are registered first (`boot/main.c:245-246`), so per the D20 rule the `.HC` declarations are skipped and `KHeap.HC` binds to the C storage. It "works" only because of that ordering; it is a duplicate owner and a latent divergence.
- **Root fix:** declare them `extern`-only in `.HC` (or expose via `HalGetHeapBase/Size`, which already exist at `apps/HalPlatform.HC:142-143`).

### 1.9 Dead duplicate stats struct `g_heap_stats` — **LOW**
- `apps/KHeap.HC:27` `CHeapStats g_heap_stats;` is written by `KhSyncStats` (`:35-42`) but **never read** anywhere (grep confirms). `g_kheap` is the real owner.
- **Root fix:** delete `g_heap_stats`/`KhSyncStats`.

---

## 2. Interrupt safety of critical sections

### 2.1 `KMalloc` / `KFree` are correctly protected — **PASS**
- `apps/KHeap.HC:115-117` (`__mrs_daif` + `__irq_disable` + `smp_spin_lock`) and `:190-192`; every exit restores DAIF (`:125,:170,:182,:197,:244`). `smp_spin_lock` uses `ldaxr/stlxr` + `dmb ish` (`kernel/arch/aarch64/smp_entry.S:56-65`), not plain loads/stores. This is the only allocator/scheduler primitive that gets it right.

### 2.2 `KHeapInit` locks but does NOT mask IRQ — **MED**
- `apps/KHeap.HC:72` takes `g_kheap_lock` without `__irq_disable`. If an IRQ-time `kfree` (scheduler zombie reap) fires while `KHeapInit` holds the lock, the IRQ handler spins forever on the non-recursive lock (same core). `KHeapInit` is reachable at runtime via `KHeapSelfTest`/`kheap_dump_doldoc` (`:363,:389`).
- **Root fix:** add the same DAIF save/restore around the lock in `KHeapInit`.

### 2.3 Unlocked heap reads and self-test mutation — **MED**
- `apps/KHeap.HC:99-108` `KHeapIsValidPtr` reads `blk->canary_head` with no lock; called from `KFree` **before** the lock (`:188`) and from `KRealloc` (`:263`).
- `apps/KHeap.HC:263-268` `KRealloc` reads `blk->canary_head` and `blk->size` unlocked; a concurrent coalesce can mutate them between read and the subsequent `KMalloc`/`KFree` (TOCTOU).
- `apps/KHeap.HC:373-474` `KHeapSelfTest` swaps `g_heap_head`/`g_heap_start`/`g_heap_end` and all `g_kheap.*` fields directly, unlocked and without masking IRQ — a timer IRQ during the test would allocate from the swapped test pool.
- `apps/KHeap.HC:337-348` `KHeapPrintStats` reads `g_kheap.*` unlocked.
- **Root fix:** make `KHeapIsValidPtr` lock/IRQ-mask, have `KRealloc` do its size read under the lock, and run the self-test with IRQs masked (`g_sched_preempt_off` is not sufficient — the IRQ still executes).

### 2.4 `Symbols.HC` has ZERO synchronisation — **BLOCKER**
- No `DAIFSet/DAIFClr`, no spinlock anywhere in `apps/Symbols.HC`. The only protection is `__dmb_ish()` (ordering, not mutual exclusion):
  - `SymRegister` mutates `g_sym_buckets[bucket]`, `g_sym_total_count`, allocates `CSymbol` — `:158-190` (dmb only at `:170,:187`).
  - `SymInit` clears all 1024 buckets — `:145-156`.
  - `SymLookupEntry`/`SymLookup` traverse buckets — `:192-210`.
  - `SymVarCell`/`SymSicCell` allocate + register — `:240-257`.
  - `SymbolsHandover` — `:259-272`.
- With a 1000 Hz timer IRQ (`apps/KernelInit.HC:132`) and 4 cores, a `kmalloc` from the IRQ path (`SchedReapZombie`→`kfree`, or the compiler) can run concurrently with `SymRegister`/`SymLookup`, corrupting bucket chains or losing/duplicating symbol entries. `g_sym_total_count` is a non-atomic RMW.
- **Root fix:** wrap all mutation and traversal in `__mrs_daif`+`__irq_disable`+`smp_spin_lock(&g_sym_lock)` (or an RCU/read-copy scheme for lookup). Add a `g_sym_lock` U32.

### 2.5 `Sched.HC` list/flag mutations are only partially protected — **HIGH**
- `TaskCreate` disables IRQ around list insertion (`:193-199`) but takes **no SMP spinlock**; `TaskExit` likewise (`:223-233`). Cross-core `TaskCreate` would race the circular list.
- `TaskYield` (`:209-212`) and the `g_sched_need_resched` RMW race with `SchedOnTick` (`:272-273`) — a yield request can be lost (no atomic; not masked).
- `TaskSetAffinity` walks and writes `curr->affinity_mask` with no lock (`:295-307`).
- `SchedInit`/`SchedCleanupAll` free the whole task list with no lock and no IRQ mask (`:106-160`).
- `SchedOnTick` runs in IRQ context and mutates `g_sched_current`, task states, quanta (`:261-293`) — safe only because it is the sole IRQ-context writer on the BSP.
- **Root fix:** one `g_sched_lock` (spinlock + DAIF save) around list mutation and `g_sched_need_resched`; use an atomic set for the resched flag.

### 2.6 `__irq_enable()` unconditionally clears I (no save/restore) — **MED**
- `apps/Sched.HC:199` and `:233` pair `__irq_disable()` with `__irq_enable()`. `__irq_enable` compiles to `MSR DAIFClr, #2` (`apps/Compiler.HC:2476`). If `TaskCreate`/`TaskExit` is entered with IRQs already masked (boot, nested critical section, `g_exc_selftest_active`), it will **prematurely unmask** interrupts. Only `KHeap.HC` uses the correct save/restore pattern.
- **Root fix:** use `__mrs_daif`/`__msr_daif` in Sched (as KHeap does).

### 2.7 `Gic.HC` state is unsynchronised — **MED**
- `g_gic.dispatched_count++` (`:173`, `:193`) and handler-table writes (`GicRegisterHandler` `:161-167`, `GicSetPriority` `:157`) have no lock; `GicDispatch`/`GicHardwareIrqHandler` can run on multiple cores.
- **Root fix:** spinlock around GIC table mutation; make the counter atomic.

### 2.8 `KMalloc` OOM prints while holding the lock — **LOW (latent)**
- `apps/KHeap.HC:178-180` calls `doldoc_printf` **before** unlocking (`:181`). Today this is safe: `doldoc_printf` is the C implementation (`boot/main.c:90-97`) which uses a stack buffer and calls the C `doldoc_print` → `symbols_lookup` (C, non-allocating). If a future `.HC` `doldoc_print` allocates, this becomes a self-deadlock on `g_kheap_lock`.
- **Root fix:** unlock before printing.

---

## 3. WFE/SEV correctness (no dry busy-wait)

### 3.1 `SmpDispatch` is a dry busy-wait — **MED**
- `apps/Smp.HC:187-190`: `while (!j->completed && wait_iters < 1000000) { __sev(); wait_iters++; }` — issues `sev` but never `wfe`; the BSP burns up to 1,000,000 iterations spinning on a cache line instead of idling. `__sev` here only wakes the worker.
- **Root fix:** `while (!j->completed) __wfe();` (or bounded `wfe`), relying on the worker's `sev` at `:84`.

### 3.2 `SmpInit` core-online wait is a dry busy-wait — **MED**
- `apps/Smp.HC:147-150`: `while (!g_smp_hc.core_online[ap_c] && wait_w < 50000) { __sev(); wait_w++; }` — no `wfe`. The secondary does issue `sev` after setting online (`:59-61`), so `wfe` would work.
- Also missing an acquire barrier on the BSP side before reading `core_online`.

### 3.3 Secondary worker idle is correct (lost-wakeup safe) — **PASS**
- `apps/Smp.HC:62-65`: `while (!j->pending) __wfe();` then re-check. `SmpDispatch` sets `j->fn/arg`, `__dmb_ish()`, `j->pending=1`, `__dmb_ish()`, `__sev()` (`:179-184`). The `sev` before `wfe` sets the event register, so a wakeup cannot be lost. `smp_entry.S:133-134` and `SmpSecondaryWorker` (`:91-93`) idle with `wfe`.

### 3.4 Scheduler idle paths are `wfe`-based — **PASS**
- `apps/Sched.HC:238-240` (`TaskExit` terminal) and `:348` (`SchedTestWorker`) use `while(1){__wfe();}`. No `for(volatile...)` or empty `while(1){}` spins exist anywhere in scope (grep clean).

### 3.5 `sev` after enqueuing work — **PASS**
- `TaskCreate` `:202`, `TaskYield` `:211`, `TaskExit` `:234`, `SmpDispatch` `:184`, worker `:84`. `SchedOnTick` (IRQ) does not need `sev`.

### 3.6 `TimerSleepMs` spin via `task_yield` — **LOW**
- `apps/Timer.HC:105-107`: `while (TimerGetUsec() < target_us) { task_yield(); }`. If preemption is deferred (`g_hc_compiling`/`g_sched_preempt_off`, `Sched.HC:279`) or the scheduler is not live, this is a hot spin. Not a dry `wfe` but a busy loop.
- **Root fix:** `__wfe()` in the loop (the 1 kHz timer wakes it).

### 3.7 Spinlock contention path uses `wfe`/`sev` — **PASS**
- `kernel/arch/aarch64/smp_entry.S:64` (`2: wfe; b 1b`) and `:70` (`sev` on unlock).

---

## 4. Cross-module struct/global access

Direct access to another module's private globals (all confirmed by grep):

| file:line | accesses | owner | accessor exists? |
|---|---|---|---|
| `apps/Gic.HC:41` | `g_hal_gicd_base` | `apps/HalPlatform.HC:32` | yes — `HalGetGicdBase()` |
| `apps/Gic.HC:46` | `g_hal_gicc_base` | `apps/HalPlatform.HC:33` | yes — `HalGetGiccBase()` |
| `apps/Timer.HC:16` | `g_hal_timer_freq` | `apps/HalPlatform.HC:37` | yes — `HalGetTimerFreq()` |
| `apps/GfxDevice.HC:258,260,262` | `g_hal_virtio_base/slots/stride` | `apps/HalPlatform.HC:34-36` | yes — `HalGetVirtio*()` |
| `apps/VirtioBlk.HC:109,111,113` | `g_hal_virtio_base/slots/stride` | `apps/HalPlatform.HC:34-36` | yes |
| `apps/VirtioInput.HC:288,290,292` | `g_hal_virtio_base/slots/stride` | `apps/HalPlatform.HC:34-36` | yes |
| `apps/Exceptions.HC:241`, `apps/Gic.HC:214`, `apps/Smp.HC:133` | `g_arch_vectors` (3 writers) | `kernel/arch/aarch64/vectors.S:257` | **no accessor** |
| `apps/Smp.HC:123` | `g_mmu_config` | `kernel/arch/aarch64/smp_entry.S:139` | **no accessor** |
| `apps/KHeap.HC:32-33` | defines `g_uefi_heap_base/size` | `boot/main.c:109-110` (duplicate) | `HalGetHeapBase/Size()` |
| `apps/KHeap.HC:278-321` | walks C heap as `.HC` blocks | `boot/runtime/kheap.c` | **no** (see 1.7) |

- **Severity:** MED (HAL globals are the P3.2 invariant the docs claim fixed: `docs/02-TASKLIST.md:479-484`). The `g_arch_vectors`/`g_mmu_config` writes are unavoidable for a vector table, but they are un-arbitrated (3 independent writers with no lock/barrier coordination beyond `__dmb_ish`).
- **Root fix:** replace all `g_hal_*` reads with the existing `HalGet*()` accessors; add a small `HalBindIrqVector()`/`HalBindSecondaryVector()` API owning `g_arch_vectors`/`g_mmu_config`.
- Note: `g_kheap.*`, `g_sched_*`, `g_smp_hc.*`, `g_sym_*`, `g_gic.*`, `g_timer.*`, `g_current_platform.*` have **no** external struct accesses — those ownership boundaries are clean.

---

## 5. Exception / BSOD correctness

### 5.1 Trap frame save/restore is consistent — **PASS**
- `vectors.S:7-92` `SAVE_ALL`/`RESTORE_ALL` offsets match `Sched.HC:45-52` and `CTrapFrame` (`Exceptions.HC:12-18`): x0–x29 at 0..224, x30@240, ELR@248, SPSR@256, SP_EL0@264, Q0–Q31 at 272..783 (784 B). `SchedBuildFrame` (`Sched.HC:244-257`) writes x0/arg, x30/`TaskExit`, ELR/`entry_fn`, SPSR=0x5 (EL1h, DAIF clear). Correct.

### 5.2 Sync vector no longer hardcodes `x3=1` — **PASS (but classification differs from docs)**
- `vectors.S:207` passes `x3=#0`; `ExceptionsHandleSync` decides recovery via `is_user_jit || g_exc_user_ok` (`Exceptions.HC:193`). Since the vector always passes 0, recovery is gated **solely** on `g_exc_user_ok`, set only by the shell (`Shell.HC:920,936`). The docs' "classify by `ELR_EL1` range" (`docs/02-TASKLIST.md:451-454,509-511`) is **not** implemented; `ELR` is only used to bound the instruction-word read (`Exceptions.HC:180-185`).

### 5.3 Recovery eret's to a new PC without unwinding SP — **HIGH**
- `Exceptions.HC:209-216`: on recovery it overwrites `f->elr_el1 = ShellRecover` and `f->lr = DolDocShellEventLoop`, clears `in_fault`, returns 1. `vectors.S:213-215` then `RESTORE_ALL` + `eret`. `RESTORE_ALL` restores the **faulting** SP (`add sp,sp,#784`), so `ShellRecover` executes on the faulting call chain's stack, not a clean stack. Its frame is built atop the faulted frames; when it returns (x30 = `DolDocShellEventLoop`) the SP is still deep in the abandoned chain. This can re-fault or corrupt state.
- **Root fix:** save a per-task/REPL recovery SP at shell entry and restore it in the recovery path (true unwinding), or longjmp-style restore of SP+LR.

### 5.4 Hardcoded recovery fallback address — **HIGH**
- `Exceptions.HC:212` `if (!rec_addr) rec_addr = 0x75001000;` — if `ShellRecover`, `ShellInit`, and `shell_poll` are all unresolved, the CPU eret's to a hardcoded JIT-pool address (arbitrary code). This is a silent, dangerous fallback.
- **Root fix:** if no recovery symbol resolves, treat as unrecoverable → BSOD, never jump to a magic address.

### 5.5 BSOD has no PC→symbol+offset mapping and no instruction dump — **MED**
- `Exceptions.HC:82-152` prints raw `ELR_EL1`, `ESR_EL1`, `FAR_EL1`, `X30`, and X0–X15 pairs. It does **not** map the fault PC to `symbol+offset` nor print the decoded instruction. `insn_val` is computed (`:179-185`) but only used on the *recovered* path (`:198`), never in the BSOD. P3.6 required "full register, symbol+offset and assembly-instruction dumps" (`docs/02-TASKLIST.md:508-514`).
- **Root fix:** use `SymLookupCanonical`/the symbol table to find the nearest preceding symbol and print `sym+off` plus the 32-bit instruction word.

### 5.6 Double-fault path is a hang, not a panic card — **MED**
- `Exceptions.HC:160-169`: on a nested fault it prints `<<<BSOD:DOUBLE>>>` then `while(1){__wfe();}`. It never returns, so `vectors.S:213`'s `cbz x0, panic_halt` is unreachable on this path. P3.6 asked for a proper double-fault panic card (`docs/02-TASKLIST.md:512`).
- **Root fix:** render a minimal text BSOD (no gfx/heap) and then `panic_halt`.

### 5.7 FIQ vector is mis-wired — **LOW**
- `vectors.S:109-114,126-131` route `fiq` to `handle_unhandled_exception`, which loads `g_arch_vectors[3]` (`:240`) — the SError slot — not `[2]` (FIQ). `GicBindVectors` sets `vecs[2]` (`Gic.HC:216`) which is then never read. FIQs are unused today, so impact is nil, but it is wrong.
- **Root fix:** add a `handle_*_fiq` that loads `[x16,#16]`, or delete the unused `vecs[2]` binding.

### 5.8 `handle_unhandled_exception` terminates in a tight `b .` — **LOW**
- `vectors.S:243` `1: b .` spins with IRQs masked by exception entry (no `wfe`, no BSOD). Unreachable in normal flow but a hard hang if a handler slot is 0.
- **Root fix:** branch to `panic_halt` instead of `b .`.

### 5.9 Double-fault latch (`in_fault`) is correct — **PASS**
- Set at `Exceptions.HC:170`, kept on panic (`:221`, deliberately not cleared), checked at `:160`; `vectors.S:213` halts on `x0==0`. No infinite re-fault loop.

---

## 6. Resource ceilings that silently truncate

| resource | cap | location | over-cap behaviour |
|---|---|---|---|
| GIC interrupt count | `MAX_GIC_INTERRUPTS 128` | `apps/Gic.HC:23` | `total_irq_lines` clamped to 128 (`:88-90`) — hardware line count silently truncated; `GicEnableIrq`/`GicRegisterHandler` silently `return` for `irq ≥ 128` (`:128,:162`). **RPi4/5/RK3399 UART IRQs 153/146/132** (`HalPlatform.HC:205,218,231`) exceed 128 → UART handler registration silently dropped. **HIGH** |
| GIC entry indexing | 128 entries | `Gic.HC:58-60` | `GicGetEntry` has no internal bounds check; all current callers guard. **LOW** |
| task stack size | min 4096, no max | `Sched.HC:164` | unbounded `kmalloc`; no upper clamp. **LOW** |
| task count | none; walk guard 4096 | `Sched.HC:61` | `SchedPickNext` stops after 4096 nodes → >4096 tasks silently mis-scheduled. **LOW** |
| SMP core count | `SMP_MAX_CORES 4` | `Smp.HC:4` | `SmpDispatch` rejects `core_id==0`/`≥4`/offline with explicit `-1` (`:170-174`) — **clean hard error**; `MPIDR & 3` (`:35`) hardcodes the 4-core assumption. **PASS for explicit failure** |
| symbol table size | 1024 buckets, no count cap | `Symbols.HC:8,18` | memory-limited; no silent truncation. **PASS** |
| symbol name length | 63 chars | `SymStrCpy` `Symbols.HC:27`; `SymBuildSnakeName` `:113` | silently truncated (no error). **LOW** |
| `SmpWorkerLoop` fn range | `fn ≥ 0x40000000` | `Smp.HC:70-72` | `fn < 0x40000000` is silently skipped but the job is still marked `completed=1`. **LOW** |
| module load buffer | 1 MB `HC_MODULE_MAX` | `KernelInit.HC:21` | generous; read is size-checked (`:31-33`). **PASS** |

- **Root fix (GIC):** size the IRQ table from `GICD_TYPER` (up to 1020 INTIDs) or at minimum return an explicit error and log when an IRQ is out of range instead of silently dropping it.

---

## 7. Other P3 invariant violations

### 7.1 "One allocator" — VIOLATED — **BLOCKER**
See §1.1: the C seed heap and the `.HC` KHeap are both live after handover, because the C JIT (invoked at `KernelInit.HC:137`) allocates directly from the seed.

### 7.2 "One symbol table" — VIOLATED — **BLOCKER**
See §1.2/§1.3: two tables, with the C table mutated post-handover and unreachable from `SymLookupCanonical`.

### 7.3 "One HAL" — VIOLATED — **MED**
See §4: `Gic.HC`, `Timer.HC`, `GfxDevice.HC`, `VirtioBlk.HC`, `VirtioInput.HC` read `g_hal_*` directly instead of the `HalGet*()` accessors.

### 7.4 "No duplicate globals" — VIOLATED — **MED**
- `g_uefi_heap_base`/`g_uefi_heap_size`: `apps/KHeap.HC:32-33` vs `boot/main.c:109-110` (§1.8).
- `g_heap_stats`: write-only duplicate of `g_kheap` (`apps/KHeap.HC:27`, §1.9).
- The P3.1 dedup (`docs/02-TASKLIST.md:474-477`) is otherwise done — `g_kernel_booting` is now single-owned at `KernelInit.HC:8` (grep confirms no redeclarations), and `g_hal_gicd_base`/`g_hal_gicc_base`/`g_hal_timer_freq` have single definitions.

### 7.5 Timer IRQ preempts on the BSP only — **MED**
- `TimerArm(1000)` is called **only** on the BSP (`KernelInit.HC:132`). Secondary cores (`SmpWorkerLoop`) never arm `CNTV_CTL_EL0`, and GICv2 PPIs are banked per-core, so secondaries never take the timer IRQ. The "preemptive scheduler" is effectively uniprocessor; the 4-core claim is only for the job-mailbox workers. The docs acknowledge "tickless idle" as residual (`docs/04-...:321-323`) but not the UP-scheduler implication.

### 7.6 `affinity_mask` is write-only (not honoured) — **MED**
- `TaskCreate` sets `affinity_mask = 0x0F` (`Sched.HC:190`) and `TaskSetAffinity` writes it (`:301`), but `SchedPickNext` (`:56-73`) ignores it entirely and there is a single global `g_sched_current`/`g_sched_head`. Affinity has no effect.
- **Root fix:** either implement per-core run queues honouring the mask or delete the field/API.

### 7.7 `cpu_switch_context` has zero callers — **LOW**
- `kernel/sched/switch.S` is assembled and registered as a symbol (`boot/main.c:298`) but never called (grep: only the `extern` and the registration). Switching is done exclusively through the trap frame (`SchedOnTick` → `vectors.S:227`). This is a defensible design (the docs' guardrail 2 explicitly endorses the trap-frame path), but the P3.5 item "wire `cpu_switch_context`" is unmet and `switch.S` is dead weight.
- **Root fix:** delete `switch.S` + its registration, or document it as intentionally unused.

### 7.8 `g_sched_need_resched` lost-update race — **MED**
- `TaskYield` does a plain store (`Sched.HC:210`); `SchedOnTick` does read-then-clear (`:272-273`). If a tick clears it between a yield store and the switch decision, the yield is lost. Combined with §2.5. Use an atomic set/clear.

### 7.9 Pre-handover `KernelMain` task leaks on re-init — **LOW**
- `SchedInit` is called at boot (`Sched.HC:425`) **before** handover, so `KernelMain` is allocated from the C heap. Any later `SchedInit`/`SchedCleanupAll` (`:106-128`) calls `kfree` on it; after handover `kfree` is `KFree`, whose `KHeapIsValidPtr` (`KHeap.HC:188`) rejects below-pool pointers and no-ops → the C-heap block leaks (by design, "pinned").

### 7.10 Dead allocator wrappers — **LOW**
- `KCalloc` (`KHeap.HC:247`) and `KRealloc` (`:257`) have **zero callers** in `apps/` (grep). Not a correctness bug, but they are untested surface that mutates the heap.

---

## Prioritized root-fix list

1. **BLOCKER — Complete the sovereign handover / kill the runtime C JIT.** Remove the `jit_compile_and_run` call at `KernelInit.HC:137` and route the C seed's own `kmalloc`/`kfree`/`symbols_*` calls (`boot/seed/jit_arm64.c`, 56 direct sites; `boot/runtime/symbols.c:88,137`) through the SIC cells, or make `CompilerCompileAndRun` the only executor. Until then the C heap and C symbol table are not frozen and P3.8 is unmet.
2. **BLOCKER — Synchronise `Symbols.HC`.** Add a spinlock + DAIF save/restore to `SymRegister`/`SymInit`/`SymLookup*`/`SymVarCell`/`SymSicCell`/`SymbolsHandover`. With a 1000 Hz IRQ + 4 cores this is a live corruption path.
3. **HIGH — Make exception recovery unwind SP.** Save/restore a recovery stack pointer (shell entry) instead of only rewriting ELR/LR (`Exceptions.HC:209-216`); remove the `0x75001000` fallback (`:212`) and BSOD when no recovery symbol resolves.
4. **HIGH — Add SMP spinlocks (with DAIF save/restore) to Sched.** `TaskCreate`/`TaskExit`/`TaskYield`/`TaskSetAffinity`/`SchedInit`/`SchedCleanupAll`; make `g_sched_need_resched` atomic. Stop using unconditional `__irq_enable` (`:199,:233`).
5. **HIGH — GIC ceiling.** Size the IRQ table from `GICD_TYPER` (or ≥ 256) and return an explicit error instead of silently dropping IRQs > 128 (breaks RPi4/5/RK3399 UART at `HalPlatform.HC:205,218,231`).
6. **MED — IRQ-mask `KHeapInit`** (`KHeap.HC:72`) and the self-test (`:373-474`); lock the `KRealloc`/`KHeapIsValidPtr` reads.
7. **MED — HAL ownership.** Replace direct `g_hal_*` reads in `Gic/Timer/GfxDevice/VirtioBlk/VirtioInput` with `HalGet*()`; add an accessor for `g_arch_vectors`/`g_mmu_config`; remove the duplicate `g_uefi_heap_base/size` `.HC` declarations and the dead `g_heap_stats`.
8. **MED — BSOD completeness.** Add symbol+offset PC mapping and the decoded instruction to `ExceptionsRenderBsod`; make the double-fault path a real panic card.
9. **MED — Replace dry busy-waits with `wfe`** in `SmpDispatch` (`Smp.HC:187`) and `SmpInit` (`:147`).
10. **MED — Affinity / UP-scheduler honesty.** Implement per-core run queues honouring `affinity_mask` (and arm the timer on secondaries), or delete the affinity API and document the UP scheduler.
11. **LOW — Delete dead code:** `kernel/sched/switch.S` + registration, `KCalloc`/`KRealloc` (or wire them), `g_heap_stats`/`KhSyncStats`, `vecs[2]` FIQ binding; fix the FIQ vector slot (`vectors.S:126-131`) and `handle_unhandled_exception`'s `b .` (`:243`).
