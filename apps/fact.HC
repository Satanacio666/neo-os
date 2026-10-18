// ==============================================================================
// fact.HC - Sovereign Combinatorics & Factorial Verification Workbench
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 Recursive & Iterative JIT
// ==============================================================================

I64 factorial(I64 n) {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}

I64 FactIterative(I64 fi_n) {
    if (fi_n <= 1) return 1;
    I64 fi_acc = 1;
    I64 fi_i = 2;
    while (fi_i <= fi_n) {
        fi_acc = fi_acc * fi_i;
        fi_i = fi_i + 1;
    }
    return fi_acc;
}

I64 FactBinomial(I64 fb_n, I64 fb_k) {
    if (fb_k < 0 || fb_k > fb_n) return 0;
    I64 fb_use_k = fb_k;
    if (fb_use_k > fb_n - fb_use_k) {
        fb_use_k = fb_n - fb_use_k;
    }
    I64 fb_res = 1;
    I64 fb_i = 1;
    while (fb_i <= fb_use_k) {
        fb_res = (fb_res * (fb_n - fb_use_k + fb_i)) / fb_i;
        fb_i = fb_i + 1;
    }
    return fb_res;
}

I64 FactMain() {
    doldoc_clear();
    U64 fm_t0 = __mrs_cntvct();
    I64 fm_pass = 0;
    I64 fm_prev = 1;
    I64 fm_n = 0;

    doldoc_print("\n$CARD,title=\"NeoOS Sovereign Factorial & Combinatorics Verification (0! .. 20!)\",w=108,h=2,bg=0xFF1E1E2E,border=0xFF89B4FA$\n");
    doldoc_print("  $FG,SAPPHIRE$N     Recursive n!              Iterative n!              Hexadecimal           Invariant$FG$\n");
    doldoc_print("$HR$\n");

    while (fm_n <= 20) {
        I64 fm_rec = factorial(fm_n);
        I64 fm_itr = FactIterative(fm_n);
        I64 fm_ok = 0;
        if (fm_n == 0) {
            if (fm_rec == 1 && fm_itr == 1) fm_ok = 1;
        } else {
            if (fm_rec == fm_itr && fm_rec == fm_prev * fm_n) fm_ok = 1;
        }
        fm_prev = fm_rec;
        if (fm_ok) fm_pass = fm_pass + 1;

        if (fm_n <= 10 || fm_n == 12 || fm_n == 15 || fm_n == 18 || fm_n == 20) {
            doldoc_printf("  $FG,YELLOW$%2lld!$FG$   $FG,WHITE$%20lld$FG$    $FG,CYAN$%20lld$FG$    0x%016llX    ", fm_n, fm_rec, fm_itr, fm_rec);
            if (fm_ok) {
                doldoc_print("$FG,GREEN$[PASS]$FG$\n");
            } else {
                doldoc_print("$FG,RED$[FAIL]$FG$\n");
            }
        }
        fm_n = fm_n + 1;
    }

    U64 fm_t1 = __mrs_cntvct();
    U64 fm_cycles = fm_t1 - fm_t0;

    I64 fm_c10_3 = FactBinomial(10, 3);
    I64 fm_c10_4 = FactBinomial(10, 4);
    I64 fm_c11_4 = FactBinomial(11, 4);

    doldoc_print("$HR$\n");
    doldoc_printf("  Pascal Identity : C(10,3) + C(10,4) = %lld + %lld = $FG,GREEN$%lld$FG$ == C(11,4) ($FG,GREEN$%lld$FG$)\n", fm_c10_3, fm_c10_4, fm_c10_3 + fm_c10_4, fm_c11_4);
    doldoc_printf("  Verification    : $FG,GREEN$%lld / 21 invariants passed$FG$  |  6! = $FG,YELLOW$%lld$FG$  |  Elapsed: $FG,CYAN$%llu cycles$FG$\n", fm_pass, factorial(6), fm_cycles);
    doldoc_print("$HR$\n");
    doldoc_print("  $BT,\"Re-Run Fact\",LM=\"run fact.HC\"$  $BT,\"Disasm factorial\",LM=\"uf factorial\"$  $BT,\"Run Calc\",LM=\"run calc.HC\"$\n\n");

    return factorial(6);
}

FactMain();
factorial(6);
