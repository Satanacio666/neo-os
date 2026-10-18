// BenchReport.HC - Modular Telemetry & Comparative Spike Report Viewer
// NeoOS AArch64 Ring 0 SASOS Native JIT Execution

U0 BenchReportMain() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$    ✦ NeoOS HolyBenchmark Comparative Report & Spike Viewer ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");

    U8 *buf = kmalloc(32768);
    if (!buf) {
        doldoc_print("$FG,RED$[FAIL] Cannot allocate buffer for report.$FG$\n");
        return;
    }

    I64 sz = 0;
    if (redsea_read_file("BENCH_COMPARISON.TXT", buf, 32767, &sz) == 0) {
        buf[sz] = 0;
        doldoc_print("$FG,GREEN$--- [1/3] RedSea Disk: /BENCH_COMPARISON.TXT ---$FG$\n");
        doldoc_print(buf);
        doldoc_print("\n");
    } else {
        doldoc_print("$FG,YELLOW$Notice: /BENCH_COMPARISON.TXT not found yet. Run benchmark suite first.$FG$\n");
    }

    sz = 0;
    if (redsea_read_file("BENCH_CPU.LOG", buf, 32767, &sz) == 0) {
        buf[sz] = 0;
        doldoc_print("$FG,GREEN$--- [2/4] RedSea Disk: /BENCH_CPU.LOG ---$FG$\n");
        doldoc_print(buf);
        doldoc_print("\n");
    }

    sz = 0;
    if (redsea_read_file("BENCH_PROFILER.LOG", buf, 32767, &sz) == 0) {
        buf[sz] = 0;
        doldoc_print("$FG,GREEN$--- [3/4] RedSea Disk: /BENCH_PROFILER.LOG ---$FG$\n");
        doldoc_print(buf);
        doldoc_print("\n");
    }

    sz = 0;
    if (redsea_read_file("BENCH_SPIKES.LOG", buf, 32767, &sz) == 0) {
        buf[sz] = 0;
        doldoc_print("$FG,GREEN$--- [4/4] RedSea Disk: /BENCH_SPIKES.LOG ---$FG$\n");
        doldoc_print(buf);
        doldoc_print("\n");
    }

    kfree(buf);
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");
    doldoc_print(" Actions: $BT,\"Re-run Full Benchmark\",LM=\"bench\"$  $BT,\"CPU Benchmarks\",LM=\"run BenchCpu.HC\"$  $BT,\"App Menu\",LM=\"menu\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

if (!g_kernel_booting) {
    BenchReportMain();
}
