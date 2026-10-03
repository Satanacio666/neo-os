// GpuConfig.HC - Native HolyC GPU Hardware & Buffering Controller
// NeoOS AArch64 Ring 0 SASOS

U0 Main() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$     ✦ NeoOS GPU Presentation & Buffering Controller (GpuConfig.HC) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" Graphics Presentation Pipeline:\n");
    doldoc_print("  Actions: $BT,\"CPU SW Blit\",LM=\"render cpu\"$  $BT,\"VirtIO GPU DMA\",LM=\"render gpu\"$  $BT,\"SMP Multi-Core\",LM=\"render smp\"$\n\n");
    doldoc_print(" Sovereign L1 NEON Raster Engine:\n");
    doldoc_print("  Actions: $BT,\"Confirm L1 Tile Engine\",LM=\"raster tile\"$  $BT,\"Tile 32x32\",LM=\"tilesize 32\"$  $BT,\"Tile 64x64\",LM=\"tilesize 64\"$\n\n");
    doldoc_print(" Zero-RAM Direct-to-VRAM Buffer:\n");
    doldoc_print("  Actions: $BT,\"Zero-RAM ON\",LM=\"zeroram on\"$  $BT,\"Double-Buffer ON\",LM=\"zeroram off\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
    gpu_config_open();
}

Main();
