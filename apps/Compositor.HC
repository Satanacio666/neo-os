// Compositor.HC - Native HolyC Desktop Compositor & Aero Controller
// NeoOS AArch64 Ring 0 SASOS

U0 Main() {
    "Opening Dedicated Desktop Compositor & Aero Controller Window...\n";
    "Configure: V-Sync Frame Pacing (60/120/144Hz), Window Shadows, Aero Glass Translucency.\n";
    compositor_config_open();
}

Main();
