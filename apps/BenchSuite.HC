// BenchSuite.HC - Native HolyC 2.0 NeoBench Extreme Launcher
// 6 Test Cycles x 4 Phases (1T, 3T SMP, Dual Window, Hardware Accel)

U0 Main() {
    "Starting NeoBench Extreme Automated Suite...\n";
    bench_suite_start();
    "6 Test Cycles: Wireframe, Polygons, UV Texture, Phong, Clipping, Physics.\n";
    "Phases: Single 1T -> Multi-Threaded 3T -> Dual Window SMP -> HW Accel.\n";
    "All telemetry and final report rendered via DolDoc and saved to /Docs/BENCH_REPORT.TXT\n";
}

Main();
