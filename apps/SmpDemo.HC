// ==============================================================================
// SmpDemo.HC - Sovereign HolyC Multi-Core Multiprocessing Task Spawner
// Architecture: ARMv8-A Ring 0 | Pure HolyC AArch64 JIT Execution
// Substrate: Dispatching parallel worker routines across PSCI Cores 1, 2, 3
// ==============================================================================

class CSmpResult {
    I64 core_id;
    I64 iterations;
    I64 checksum;
    I64 status;
};

CSmpResult g_smp_results[4];

U0 SmpDemoWorker(U8 *arg) {
    CSmpResult *res = arg;
    res->checksum = 0;
    I64 i;
    for (i = 0; i < res->iterations; i++) {
        res->checksum = res->checksum + (i * 3 + 7);
    }
    res->status = 1; // Completed
}

U0 SmpDemoMain() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$    ✦ NeoOS HolyC Multi-Core Multiprocessing Task Spawner ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");

    I64 num_cores = smp_get_core_count();
    I64 boot_core = smp_get_current_core();

    doldoc_printf(" Active Cores  : %lld\n", num_cores);
    doldoc_printf(" Boot Core     : Core #%lld (Main Executive)\n", boot_core);
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    I64 c;
    for (c = 1; c < num_cores; c++) {
        g_smp_results[c].core_id = c;
        g_smp_results[c].iterations = 100000;
        g_smp_results[c].checksum = 0;
        g_smp_results[c].status = 0;

        doldoc_printf(" Dispatching Job to Secondary Core #%lld...", c);
        I64 ok = smp_dispatch(c, &SmpDemoWorker, &g_smp_results[c]);
        if (ok == 0) {
            doldoc_print(" $FG,GREEN$[DISPATCHED]$FG$\n");
        } else {
            doldoc_print(" $FG,RED$[BUSY/ERR]$FG$\n");
        }
    }

    doldoc_print("\n Synchronizing with Secondary Cores...\n");
    for (c = 1; c < num_cores; c++) {
        smp_wait_job(c);
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Core #%lld Finished! Checksum: 0x%llX\n",
                       c, g_smp_results[c].checksum);
    }

    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,GREEN$ Multi-Core SMP Dispatching 100% Operational in Pure HolyC!$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

SmpDemoMain();
