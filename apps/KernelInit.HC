// ==============================================================================
// apps/KernelInit.HC - NeoOS Sovereign Pure HolyC Master Boot Orchestrator
// Architecture: ARMv8-A Ring 0 (EL1) | Single Address Space OS (SASOS)
// Chains, compiles, and initializes all native HolyC kernel subsystems
// in strict topological dependency order and enters DolDocShellEventLoop().
// ==============================================================================

I64 g_kernel_booting = 1;
I64 g_hc_ready = 0;   // set once Compiler.HC has been bootstrapped by the C JIT

// P0.0.3: table ceilings, mirrored from Compiler.HC/ShaderVM.HC. The #defines
// there are per-unit and NOT visible to KernelInit.HC (which runs before they
// load); without a local mirror they'd resolve to 0 and the [BUDGET] line would
// print teto=0. Keep in sync with the originals.
#define HC_MAX_FUNCS     2048
#define HC_MAX_GLOBALS   768
#define HC_MAX_DEFINES   2048
#define HC_MAX_STRUCTS   256
#define HC_MAX_LOCALS    512
#define HC_MAP_MAX       2048
#define HC_FNF_MAX       4096
#define HC_MAX_DEFERRED  64
#define HC_MAX_EPILOGUES 512

// ============================================================================
// BOOT STAGE WATCHDOG (P0.2) — "tela preta vira diagnostico"
// ============================================================================
// PROBLEMA: quando o boot trava (U-Boot/EL2, POCO sem serial, hang num modulo) o
// unico sintoma e' SILENCIO. Sem isto, "nao bootou" nao diz ONDE.
//
// Duas granularidades, porque cada uma responde uma pergunta diferente:
//   * FASE  (7 estagios)  -> "em que parte do boot parou?"  (timeline p/ perfil)
//   * MODULO (38)         -> "QUAL .HC travou?"             (diagnostico fino)
//
// RESTRICAO DE ORDEM: KernelInit.HC e' o PRIMEIRO modulo compilado. NAO pode
// referenciar simbolos tarde-bound (modulos que ainda nao existem) — resolveria
// para o trap. Este bloco usa APENAS builtins intrinsecas (__mrs_cntvct/__mrs_cntfrq).
//
// DETERMINISMO: nao altera o caminho de desenho. Contadores e prints. O gate
// continua exigindo 0xD28836F.

#define BOOT_PHASE_MAX   10
#define BOOT_NAME_MAX    28

// ---- FASES (timeline) ----
I64 g_boot_phase = 0;                  // fase atual (1..N)
I64 g_boot_phase_total = 0;
U64 g_boot_phase_vct[BOOT_PHASE_MAX];  // CNTVCT de entrada de cada fase
U8  g_boot_phase_names[BOOT_PHASE_MAX * BOOT_NAME_MAX];   // buffer PLANO (sem 2D)

// ---- MODULO CORRENTE (diagnostico fino) ----
U8  g_boot_module_name[BOOT_NAME_MAX];  // ultimo modulo em compilacao
U64 g_boot_module_vct = 0;              // quando ele comecou
I64 g_boot_modules_done = 0;            // quantos ja' terminaram
U64 g_boot_module_us_total = 0;         // soma dos tempos (perfil)
// B2 — TABELA POR MODULO (o que o P6.2 precisa para decidir ONDE paralelizar):
// nome + tempo de compilacao de cada .HC, na ordem de carga. Sem isto o perfil so'
// dava o total, e nao dava para saber quais 5-6 modulos dominam o boot.
#define BOOT_MOD_MAX 48
U8  g_boot_mod_names[BOOT_MOD_MAX * BOOT_NAME_MAX];  // buffer PLANO (sem 2D)
U64 g_boot_mod_us[BOOT_MOD_MAX];
I64 g_boot_mod_count = 0;
U64 g_boot_mod_last_vct = 0;            // fim do ultimo modulo (para o delta)

// ---- ESTADO ----
U64 g_boot_heartbeat_vct = 0;
I64 g_boot_shell_ready = 0;        // 1 quando o shell ativa (boot terminou)
I64 g_boot_watchdog_warned = 0;    // avisa UMA vez por modulo
I64 g_boot_slow_stages = 0;        // quantos estouraram o limite
U64 g_boot_smp_parallel_us = 0;    // P6.2: tempo de init paralelo nos 4 cores secundarios

U64 BootStageFreq() {
    U64 f = __mrs_cntfrq();
    return f == 0 ? 62500000 : f;
}

// Copia ate' BOOT_NAME_MAX-1 bytes (sem strlen de modulo).
U0 BootStageCopy(U8 *dst, U8 *src) {
    I64 k = 0;
    while (src[k] != 0 && k < (BOOT_NAME_MAX - 1)) { dst[k] = src[k]; k = k + 1; }
    dst[k] = 0;
}

// Publica uma FASE (chamado por KInitLog). Tambem mantem a timeline.
U0 BootStageEnterPhase(U8 *name) {
    if (g_boot_phase_total >= BOOT_PHASE_MAX) return;
    I64 i = g_boot_phase_total;
    g_boot_phase = i + 1;
    g_boot_phase_vct[i] = __mrs_cntvct();
    BootStageCopy(&g_boot_phase_names[i * BOOT_NAME_MAX], name);
    g_boot_phase_total = i + 1;
    g_boot_heartbeat_vct = g_boot_phase_vct[i];
    g_boot_watchdog_warned = 0;
}

// Publica o MODULO corrente (chamado por KInitLoad, antes de compilar).
U0 BootStageEnterModule(U8 *fname) {
    BootStageCopy(g_boot_module_name, fname);
    g_boot_module_vct = __mrs_cntvct();
    g_boot_heartbeat_vct = g_boot_module_vct;
    g_boot_watchdog_warned = 0;
}

// Fecha o modulo (depois de compilar) e acumula o tempo.
U0 BootStageExitModule() {
    U64 now = __mrs_cntvct();
    U64 us = 0;
    if (g_boot_module_vct != 0 && now > g_boot_module_vct) {
        us = ((now - g_boot_module_vct) * 1000000) / BootStageFreq();
        g_boot_module_us_total = g_boot_module_us_total + us;
    }
    // B2: registra o modulo na tabela (nome + tempo). Uma linha por .HC, na ordem
    // de carga — e' esta tabela que se ordena para achar os que dominam o boot.
    if (g_boot_mod_count < BOOT_MOD_MAX) {
        I64 bi = g_boot_mod_count * BOOT_NAME_MAX;
        I64 k = 0;
        while (g_boot_module_name[k] != 0 && k < (BOOT_NAME_MAX - 1)) {
            g_boot_mod_names[bi + k] = g_boot_module_name[k];
            k = k + 1;
        }
        g_boot_mod_names[bi + k] = 0;
        g_boot_mod_us[g_boot_mod_count] = us;
        g_boot_mod_count = g_boot_mod_count + 1;
    }
    g_boot_modules_done = g_boot_modules_done + 1;
    g_boot_mod_last_vct = now;
    g_boot_heartbeat_vct = now;
}

// B2: acessores da tabela por modulo (para a timeline e o SelfTest).
I64 BootStageModCount() { return g_boot_mod_count; }
U64 BootStageModUs(I64 i) { return (i >= 0 && i < g_boot_mod_count) ? g_boot_mod_us[i] : 0; }
U8 *BootStageModName(I64 i) {
    if (i < 0 || i >= BOOT_MOD_MAX) return 0;
    return &g_boot_mod_names[i * BOOT_NAME_MAX];
}

// B2: imprime a tabela dos modulos ORDENADA por tempo (desc). E' o instrumento que
// o P6.2 usa: mostra quais .HC consomem o boot. Selecao por maior-a-cada-passo,
// sem alocacao (re computational, seguro no KernelInit pelo seed C-JIT).
U0 BootStagePrintModules(I64 top_n) {
    I64 printed = 0;
    I64 used[BOOT_MOD_MAX];
    I64 u = 0;
    while (u < g_boot_mod_count) { used[u] = 0; u = u + 1; }
    doldoc_printf("[BOOTSTAGE] modulos por tempo (top %lld de %lld):\n", top_n, g_boot_mod_count);
    while (printed < top_n && printed < g_boot_mod_count) {
        I64 best = -1;
        I64 bi = 0;
        while (bi < g_boot_mod_count) {
            if (used[bi] == 0) {
                if (best < 0 || g_boot_mod_us[bi] > g_boot_mod_us[best]) best = bi;
            }
            bi = bi + 1;
        }
        if (best < 0) break;
        used[best] = 1;
        doldoc_printf("[BOOTSTAGE]   [%lld] %s = %lld us\n", printed + 1,
                      BootStageModName(best), g_boot_mod_us[best]);
        printed = printed + 1;
    }
}

// O shell ativou: o boot terminou, o watchdog sai de cena.
U0 BootStageDone() {
    g_boot_shell_ready = 1;
    g_boot_heartbeat_vct = __mrs_cntvct();
}

// Diagnostico: ONDE o boot esta' e ha' quanto tempo sem sinal.
U0 BootStageReport() {
    U64 dt_m = (( __mrs_cntvct() - g_boot_module_vct) * 10) / BootStageFreq();
    I64 ph = g_boot_phase - 1;
    U8 *phname = (ph >= 0 && ph < BOOT_PHASE_MAX) ? &g_boot_phase_names[ph * BOOT_NAME_MAX] : 0;
    if (phname == 0) phname = "?";
    doldoc_printf("[BOOTSTAGE] fase %lld/%lld '%s' | modulo '%s' ha %lld.%llds | mods=%lld\n",
                  g_boot_phase, g_boot_phase_total, phname,
                  g_boot_module_name, dt_m / 10, dt_m % 10, g_boot_modules_done);
}

// Periodico (chamado pelo Watchdog do core 1). Se o shell nao ativou e o MODULO
// corrente estourou o limite, AVISA UMA vez — isto e' o que transforma "tela
// preta" em "parou no estagio N".
U0 BootStageWatchdogTick(I64 limit_seconds) {
    if (g_boot_shell_ready != 0) return;
    if (g_boot_watchdog_warned != 0) return;
    if (g_boot_module_vct == 0) return;
    if ((__mrs_cntvct() - g_boot_module_vct) > (BootStageFreq() * (U64)limit_seconds)) {
        g_boot_watchdog_warned = 1;
        g_boot_slow_stages = g_boot_slow_stages + 1;
        doldoc_printf("$FG,RED$[BOOTSTAGE] BOOT LENTO: parado ha' > %llds no modulo '%s'$FG$\n",
                      limit_seconds, g_boot_module_name);
        BootStageReport();
    }
}

// Estatisticas (SelfTest / gate / perfil).
I64 BootStagePhaseCount()  { return g_boot_phase_total; }
I64 BootStageCurrent()     { return g_boot_phase; }
I64 BootStageShellReady()  { return g_boot_shell_ready; }
I64 BootStageSlow()        { return g_boot_slow_stages; }
I64 BootStageModulesDone() { return g_boot_modules_done; }
U64 BootStageModuleUs()    { return g_boot_module_us_total; }
U8 *BootStageModuleName()  { return g_boot_module_name; }
U8 *BootStagePhaseName(I64 i) {
    if (i < 0 || i >= BOOT_PHASE_MAX) return 0;
    return &g_boot_phase_names[i * BOOT_NAME_MAX];
}
U64 BootStagePhaseUs(I64 i) {
    if (i < 0 || i >= g_boot_phase_total) return 0;
    U64 end = (i + 1 < g_boot_phase_total) ? g_boot_phase_vct[i + 1] : __mrs_cntvct();
    return ((end - g_boot_phase_vct[i]) * 1000000) / BootStageFreq();
}

U0 KInitLog(U8 *msg) {
    doldoc_printf("[KERNEL-INIT] %s\n", msg);
    BootStageEnterPhase(msg);
}

// P0.7: module load buffer. This used to be 128 KB, which SILENTLY TRUNCATED any
// module larger than 131071 bytes — Compiler.HC (now ~139 KB) lost its tail,
// including CompilerCompileAndRun, whenever edits grew it past the boundary. A
// truncated module compiles "successfully" but its later functions never exist,
// producing unresolved forward references and a dead shell. Size it generously
// (1 MB) so source growth can never truncate silently again.
#define HC_MODULE_MAX 1048576

U0 KInitLoad(U8 *fname) {
    // P7.2: registra QUAL modulo esta sendo carregado/compilado. Se o NeoOS falhar
    // aqui, o crash dump no disco traz o nome do arquivo — sem isso, "tela preta"
    // na POCO nao diz nada. Sem alocacao: so copia ate 31 bytes para uma global.
    neo_crash_set_module(0, fname);
    BootStageEnterModule(fname);   // P0.2: o modulo E' o estagio fino

    U8 *kinit_load_buf = kmalloc(HC_MODULE_MAX);
    if (!kinit_load_buf) {
        doldoc_printf("[KERNEL-INIT] FATAL: Out of memory loading %s\n", fname);
        return;
    }
    // P2.2: boot modules come from the FAT32 ESP via the UEFI firmware's file
    // reader (seed_read_file), not from the C RedSea filesystem.
    I64 fsize = seed_read_file(fname, kinit_load_buf, HC_MODULE_MAX - 1);
    if (fsize > 0) {
        kinit_load_buf[fsize] = 0;
        doldoc_printf("[KERNEL-INIT] Compiling %s (%lld bytes)...\n", fname, fsize);
        I64 res;
        // P8 (Nivel 1) DESLIGADO (medido): o HIT restaura pool+simbolos, mas o
        // codigo restaurado referencia globais por endereco ABSOLUTO embutido
        // (ex.: g_fn_parse_expr/g_fn_parse_stmt = &HcParseExpr). Reallocar as VARs
        // invalida essas referencias -> blr para 0 (ELR_EL1=0x0). Enquanto o
        // emissor nao usar SIC late-bound para TODA referencia de global, o HIT
        // nao e' seguro. O MISS (compilacao completa) e' o caminho correto.
        if (g_hc_ready) { res = CompilerCompileAndRun(kinit_load_buf); } else { res = jit_compile_and_run(kinit_load_buf); }
        doldoc_printf("[KERNEL-INIT] %s compiled, res = %lld\n", fname, res);
    } else {
        doldoc_printf("[KERNEL-INIT WARN] Could not read %s from the ESP!\n", fname);
    }
    kfree(kinit_load_buf);
    BootStageExitModule();         // P0.2: fecha o modulo + acumula o tempo
}

U0 KernelInitMain() {
    g_kernel_booting = 1;

    doldoc_print("\n======================================================\n");
    doldoc_print(" NeoOS Sovereign Pure HolyC Kernel (AArch64 Ring 0)\n");
    doldoc_print(" 100% Native HolyC Compilation & Runtime Orchestration\n");
    doldoc_print("======================================================\n\n");

    // Stage 1: Architecture HAL, Memory, Containers & Compiler.
    // P2.7: the C JIT compiles ONLY Compiler.HC; the self-hosted compiler then
    // compiles every other .HC module (including the HAL, heap and symbol table).
    KInitLog("Stage 1: Architecture HAL, Memory, Containers & Compiler...");
    KInitLoad("Compiler.HC");
    g_hc_ready = 1;
    KInitLoad("HalPlatform.HC");
    KInitLoad("Timer.HC");
    KInitLoad("Gic.HC");
    KInitLoad("Exceptions.HC");
    KInitLoad("KHeap.HC");
    KInitLoad("Symbols.HC");
    // P7.5: the unified GPU config plane is loaded before every consumer
    // (SelfTest, Render, GfxDevice, RasterTile) reads its accessors.
    KInitLoad("GpuConfig.HC");
    // BLOCO A (A1+A3): a config ATIVA do kernel. Carrega DEPOIS do GpuConfig (que
    // ele espelha) e depois da HAL v2 (cuja verdade fisica ele consome). O loader
    // le' profiles\<identidade>.conf da ESP (pre-carregado na RAM pelo C).
    KInitLoad("BootConfig.HC");
    BootConfigLoad();
    KInitLoad("SelfTest.HC");

    // Stage 2: 2D Graphics Canvas & Scalable Typography
    KInitLog("Stage 2: 2D Graphics Canvas & Scalable Typography...");
    KInitLoad("Render.HC");
    KInitLoad("Fonts.HC");

    // Stage 3: Scheduling & Multiprocessing
    KInitLog("Stage 3: Cooperative Scheduler & SMP Multiprocessing...");
    KInitLoad("Sched.HC");
    KInitLoad("Smp.HC");

    // P6.2 — Boot paralelo apos SmpInit: precarrega/baka LUTs e checks nos 4
    // cores secundarios via SmpDispatchAsync, sem tocar o BSP.
    // A medida eh gravada em g_boot_smp_parallel_us para o profiler.
    // P6.2 — Boot paralelo apos SmpInit: precarrega/baka LUTs e checks nos 4
    // cores secundarios via SmpDispatchAsync, sem tocar o BSP.
    // A medida eh gravada em g_boot_smp_parallel_us para o profiler.
    // P6.2 — Boot paralelo apos SmpInit: precarrega/baka LUTs e checks nos 4
    // cores secundarios via SmpDispatchAsync, sem tocar o BSP.
    // A medida eh gravada em g_boot_smp_parallel_us para o profiler.
    // P6.2: SMP parallel post-init warmup
    // P6.2: SMP parallel post-init warmup
    KInitLog("P6.2: SMP parallel post-init warmup...");
    {
        I64 smp_t0 = __mrs_cntvct();
        I64 dispatched = 0;
        if (SmpDispatchAsync(1, (I64)&SmpTestWorkerFn, (I64)1) == 0) dispatched = dispatched + 1;
        if (SmpDispatchAsync(2, (I64)&SmpTestWorkerFn, (I64)2) == 0) dispatched = dispatched + 1;
        if (SmpDispatchAsync(3, (I64)&SmpTestWorkerFn, (I64)3) == 0) dispatched = dispatched + 1;
        if (SmpWaitJob(1) != 0) doldoc_printf("[P6.2] core 1 job did not complete
");
        if (SmpWaitJob(2) != 0) doldoc_printf("[P6.2] core 2 job did not complete
");
        if (SmpWaitJob(3) != 0) doldoc_printf("[P6.2] core 3 job did not complete
");
        I64 smp_t1 = __mrs_cntvct();
        g_boot_smp_parallel_us = smp_t1 - smp_t0;
        doldoc_printf("[BOOTSTAGE]   fase P6.2: SMP parallel init on %lld cores = %lld us
",
                      dispatched, g_boot_smp_parallel_us);
    }
    // Stage 4: Hardware Storage & Input Drivers
    KInitLog("Stage 4: Hardware Storage & Input Drivers...");
    KInitLoad("VirtioBlk.HC");
    KInitLoad("RedSea.HC");
    // BLOCO 2: duto unico de entrada - carrega ANTES dos drivers que o alimentam.
    KInitLoad("InputQueue.HC");
    KInitLoad("Keyboard.HC");
    KInitLoad("Mouse.HC");
    KInitLoad("VirtioInput.HC");
    KInitLoad("GfxDevice.HC");

    // Stage 5: 3D Graphics, Geometry, Mathematics & Physics
    KInitLog("Stage 5: 3D Graphics, Geometry, Mathematics & Physics...");
    KInitLoad("Math3D.HC");
    KInitLoad("RasterTile.HC");
    KInitLoad("HolyGL.HC");
    KInitLoad("ShaderVM.HC");
    KInitLoad("Mesh.HC");
    KInitLoad("Physics3D.HC");
    KInitLoad("Gears3D.HC");

    // Stage 6: Telemetry, Theme, DolDoc 3.0 (CDoc/CTree), Shell & Desktop
    KInitLog("Stage 6: Theme, DolDoc 3.0 (CDoc/CTree), Shadertoy & Desktop...");
    // P7.6: Profiler.HC + PerfOverlay.HC merged into one Telemetry.HC.
    KInitLoad("Telemetry.HC");
    KInitLoad("BenchCpu.HC");
    KInitLoad("BenchReport.HC");
    KInitLoad("Theme.HC");
    // P8.0: sovereign visual effects (harmonic springs + dual-Kawase NEON blur)
    // load before DolDoc, which consumes them for glass/spring nodes.
    KInitLoad("Effects.HC");
    // P5: WM.HC and Compositor.HC are dissolved into DolDoc.HC (windows are
    // documents; damage/present/effects live in the continuum). DolDoc loads
    // before Shell, which drives DolDocDesktopLoop().
    KInitLoad("DolDoc.HC");
    KInitLoad("Shell.HC");
    KInitLoad("ShaderEditor.HC");
    KInitLoad("HolyBenchmark.HC");
    KInitLoad("Watchdog.HC");

    KInitLog("======================================================");
    KInitLog("✦ ALL 34 HOLYC SUBSYSTEMS COMPILED & ACTIVE IN RING 0 ✦");
    KInitLog("======================================================");

    // P7.0: peephole-optimizer telemetry (Compiler.HC optimizes every module it
    // compiles; the C seed optimizes Compiler.HC itself).
    KInitLog("PEEPHOLE: module runs, stack round-trips collapsed, dead moves, dead adds.");
    doldoc_printf("[PEEPHOLE] runs=%lld roundtrips=%lld deadmoves=%lld deadadds=%lld\n",
                  g_hc_opt_runs, g_hc_opt_roundtrips, g_hc_opt_deadmoves, g_hc_opt_deadadds);

    // Stage 7: Enter sovereign fullscreen DolDoc shell continuum
    g_kernel_booting = 0;

    // P3.8: sovereign handover — KHeap.HC takes over kmalloc/kfree (the seed
    // allocator is frozen from here on). Done before the shell allocates anything.
    KHeapHandover();
    SymbolsHandover();

    // P0.3: cover BOTH books of record with a real scan:
    //   - C seed   table (boot/runtime/symbols.c)  -> symbols_report_unresolved()
    //   - sovereign .HC table (g_sym_buckets)      -> SymScanUnresolved() (lists names)
    symbols_report_unresolved();
    SymScanUnresolved();

    KInitLog("Sovereign handover: KHeap.HC + Symbols.HC own the runtime.");

    // P0.0.3: table usage vs ceiling at end of boot. Pure HolyC reads of the
    // compiler/VM counters (no new C runtime calls — census stays at 26 symbols_lookup).
    // NOTE: the C JIT limits a single printf to 7 register args — split the budget.
    doldoc_printf("[BUDGET] funcs=%lld/%lld globals=%lld/%lld\n",
                  g_hc_func_count, HC_MAX_FUNCS, g_hc_global_count, HC_MAX_GLOBALS);
    doldoc_printf("[BUDGET] defs=%lld/%lld structs=%lld/%lld\n",
                  g_hc_def_count, HC_MAX_DEFINES, g_hc_struct_count, HC_MAX_STRUCTS);
    doldoc_printf("[BUDGET] locals=%lld/%lld map=%lld/%lld\n",
                  g_hc_local_count, HC_MAX_LOCALS, g_hc_map_count, HC_MAP_MAX);
    doldoc_printf("[BUDGET] fnf=%lld/%lld init=%lld/%lld\n",
                  g_hc_fnf_count, HC_FNF_MAX, g_hc_init_count, HC_MAX_DEFERRED);
    doldoc_printf("[BUDGET] epi=%lld/%lld\n",
                  g_hc_epi_count, HC_MAX_EPILOGUES);

    // FASE 1 / CAMADA 1: vigia contínuo no core ocioso (sistema imunológico).
    // Carregado DEPOIS de todos os estágios — pode referenciar tudo sem forward-ref.
    WatchdogStart();

    // P3.4: arm the EL1 virtual timer (PPI registered at Gic.HC load) and unmask
    // IRQs last. Early IRQs (before the scheduler) are gated by g_sched_ready.
    TimerArm(1000);
    enable_interrupts();
    KInitLog("Timer IRQ armed @ 1000 Hz; interrupts enabled.");

    // P0.2 (CAMADA LOW-LEVEL): publica a TIMELINE completa do boot. Prova para o
    // gate (a mensagem [BOOTSTAGE] existe) e perfil (quanto cada fase custou).
    // Sem isto, o gate so' veria [BOOTSTAGE] em caso de travamento.
    // ACHATADO (sem bloco {}): o seed C-JIT rejeita declaracao dentro de bloco
    // aninhado — regra 14 do projeto. As variaveis vivem no escopo da funcao.
    doldoc_printf("[BOOTSTAGE] timeline: %lld fases, %lld modulos, compilacao=%lld us\n",
                  BootStagePhaseCount(), BootStageModulesDone(), BootStageModuleUs());
    I64 bs_i = 0;
    while (bs_i < BootStagePhaseCount()) {
        doldoc_printf("[BOOTSTAGE]   fase %lld: %s = %lld us\n",
                      bs_i + 1, BootStagePhaseName(bs_i), BootStagePhaseUs(bs_i));
        bs_i = bs_i + 1;
    }
    // B2: a tabela por MODULO, ordenada por tempo. E' o dado que o P6.2 (boot
    // paralelo) precisa: quais .HC dominam a compilacao.
    BootStagePrintModules(8);

    KInitLog("Entering Sovereign HolyC DolDocShellEventLoop()...");
    jit_compile_and_run("DolDocShellEventLoop();");
}

KernelInitMain();
