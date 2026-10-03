// Top.HC - Native HolyC Task Manager & SMP Telemetry
// NeoOS AArch64 Ring 0 SASOS

U0 TopMain() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$       ✦ NeoOS Pure HolyC System Telemetry & Monitor (Top.HC) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    top_print_doldoc();
}

TopMain();
