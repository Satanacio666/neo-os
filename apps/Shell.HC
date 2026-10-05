// ==============================================================================
// Shell.HC - Sovereign Pure HolyC Interactive Shell Console
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Substrate: Interactive REPL, Command History & Dynamic RedSea Autocompletion
// ==============================================================================

#define SHELL_MAX_LINE    256
#define SHELL_HISTORY_MAX 16

class CShell {
    U8  cmd_buf[SHELL_MAX_LINE];
    I64 cmd_len;
    U8  history[SHELL_HISTORY_MAX][SHELL_MAX_LINE];
    I64 history_count;
    I64 history_head;
    I64 history_nav;
};

CShell g_shell;

U0 ShellInit() {
    g_shell.cmd_len = 0;
    g_shell.cmd_buf[0] = 0;
    g_shell.history_count = 0;
    g_shell.history_head = 0;
    g_shell.history_nav = -1;
}

U0 ShellAddHistory(U8 *cmd) {
    if (!cmd || !*cmd) return;
    if (g_shell.history_count > 0) {
        I64 last_idx = (g_shell.history_head - 1 + SHELL_HISTORY_MAX) % SHELL_HISTORY_MAX;
        if (strcmp(g_shell.history[last_idx], cmd) == 0) {
            g_shell.history_nav = -1;
            return;
        }
    }
    strcpy(g_shell.history[g_shell.history_head], cmd);
    g_shell.history_head = (g_shell.history_head + 1) % SHELL_HISTORY_MAX;
    if (g_shell.history_count < SHELL_HISTORY_MAX) g_shell.history_count++;
    g_shell.history_nav = -1;
}

U0 ShellRunCommand(U8 *cmd) {
    if (!cmd || !*cmd) return;
    ShellAddHistory(cmd);

    if (strcmp(cmd, "help") == 0) {
        doldoc_print("\n$FG,CYAN$=== NeoOS Sovereign Pure HolyC Shell Commands ===$FG$\n");
        doldoc_print("  $FG,YELLOW$run <file.HC>$FG$   : Compile and execute HolyC application in RAM\n");
        doldoc_print("  $FG,YELLOW$ls$FG$              : List files in current RedSea directory\n");
        doldoc_print("  $FG,YELLOW$cat <file>$FG$      : Print file contents\n");
        doldoc_print("  $FG,YELLOW$clear$FG$           : Clear terminal output\n");
        doldoc_print("  $FG,YELLOW$mem$FG$             : Print physical kernel heap allocator statistics\n");
        doldoc_print("  $FG,YELLOW$top$FG$             : SMP Multi-Core real-time task manager\n");
        doldoc_print("  $FG,YELLOW$menu$FG$            : Open sovereign application drawer\n");
        doldoc_print("  $FG,YELLOW$reboot$FG$          : Clean hardware reset\n\n");
    } else if (strcmp(cmd, "clear") == 0) {
        doldoc_clear();
    } else if (strcmp(cmd, "ls") == 0) {
        redsea_list_dir();
    } else if (strcmp(cmd, "mem") == 0) {
        kheap_dump_stats();
    } else if (strcmp(cmd, "menu") == 0) {
        menu_toggle();
    } else if (strcmp(cmd, "reboot") == 0) {
        hal_reset_system();
    } else if (strncmp(cmd, "run ", 4) == 0) {
        U8 *fname = cmd + 4;
        while (*fname == ' ') fname++;
        U8 fbuf[16384];
        I64 fsize = 0;
        if (redsea_read_file(fname, fbuf, 16383, &fsize) == 0) {
            fbuf[fsize] = 0;
            doldoc_printf("$FG,GREEN$[RUN]$FG$ Compiling and executing %s (%lld bytes)...\n", fname, fsize);
            I64 res = jit_compile_and_run(fbuf);
            doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", res, res);
        } else {
            doldoc_printf("$FG,RED$File not found on RedSea disk: %s$FG$\n", fname);
        }
    } else if (strncmp(cmd, "cat ", 4) == 0) {
        U8 *fname = cmd + 4;
        while (*fname == ' ') fname++;
        U8 fbuf[4096];
        I64 fsize = 0;
        if (redsea_read_file(fname, fbuf, 4095, &fsize) == 0) {
            fbuf[fsize] = 0;
            doldoc_printf("$FG,CYAN$--- %s (%lld bytes) ---$FG$\n", fname, fsize);
            doldoc_print(fbuf);
            doldoc_print("\n$FG,CYAN$-------------------------$FG$\n");
        } else {
            doldoc_printf("$FG,RED$File not found: %s$FG$\n", fname);
        }
    } else {
        // Direct HolyC evaluation
        I64 res = jit_compile_and_run(cmd);
        doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", res, res);
    }
}

U0 ShellMain() {
    ShellInit();
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$       ✦ NeoOS Sovereign Pure HolyC Shell Console (Shell.HC) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" Environment: ARMv8-A Ring 0 SASOS | 100% Native AArch64 JIT\n");
    doldoc_print(" Substrate  : Pure HolyC Line Editor & Circular History Buffer\n");
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    doldoc_print(" Available Sovereign Commands & Launchers:\n");
    doldoc_print("  System & Bench : $BT,\"HolyBenchmark\",LM=\"run HolyBenchmark.HC\"$  $BT,\"Scorecard\",LM=\"run BenchReport.HC\"$  $BT,\"Top\",LM=\"run Top.HC\"$\n");
    doldoc_print("  3D & Graphics  : $BT,\"GLXGears 3D\",LM=\"run Gears.HC\"$  $BT,\"Physics 3D\",LM=\"run Physics3D.HC\"$  $BT,\"Shaders\",LM=\"run ShaderEditor.HC\"$\n");
    doldoc_print("  Compilers      : $BT,\"Sovereign JIT\",LM=\"run Compiler.HC\"$  $BT,\"WASM JIT\",LM=\"run WasmJit.HC\"$  $BT,\"DolDoc\",LM=\"run DolDoc.HC\"$\n");
    doldoc_print("  Files & Storage: $BT,\"Filer Explorer\",LM=\"run Filer.HC\"$  $BT,\"List (ls)\",LM=\"ls\"$  $BT,\"Heap Stats\",LM=\"mem\"$\n");
    doldoc_print("  Navigation     : $BT,\"✦ NeoMenu\",LM=\"menu\"$  $BT,\"Clear Console\",LM=\"clear\"$  $BT,\"Help Index\",LM=\"help\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

ShellMain();
