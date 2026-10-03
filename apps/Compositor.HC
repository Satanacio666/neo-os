// Compositor.HC - Native HolyC Desktop Compositor & Aero Controller
// NeoOS AArch64 Ring 0 SASOS

U0 Main() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$    ✦ NeoOS Desktop Compositor & Aero Controller (Compositor.HC) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" V-Sync Frame Pacing & Display Engine:\n");
    doldoc_print("  Actions: $BT,\"VSync 60Hz\",LM=\"vsync 60\"$  $BT,\"VSync 120Hz\",LM=\"vsync 120\"$  $BT,\"Uncapped\",LM=\"vsync off\"$\n\n");
    doldoc_print(" Aero Glass & Window Shadow Styling:\n");
    doldoc_print("  Actions: $BT,\"Open Compositor GUI\",LM=\"compositor_gui\"$  $BT,\"Refresh\",LM=\"run Compositor.HC\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
    compositor_config_open();
}

Main();
