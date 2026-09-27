// GpuConfig.HC - Native HolyC GPU Hardware & Buffering Controller
// NeoOS AArch64 Ring 0 SASOS

U0 Main() {
    "Opening Dedicated GPU Hardware & Buffering Configuration Window...\n";
    "Configure: CPU Software (UEFI) vs VirtIO-GPU Hardware vs SMP Multi-Core, Zero-RAM vs Double-Buffered.\n";
    gpu_config_open();
}

Main();
