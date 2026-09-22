// Gears.HC - Native HolyC 2.0 GLXGears 3D Benchmark Launcher
// Brian Paul / Mesa 3D ported to Terry Davis SASOS Architecture (NeoOS AArch64)

U0 Main() {
    "Starting Authentic 3D GLXGears Benchmark...\n";
    "3 Interlocking Gears: Red (20T), Green (10T), Blue (10T).\n";
    "16-bit Depth Z-Buffer, Screen-Space Backface Culling & Directional Lighting.\n";
    "Drag with mouse to rotate camera in 3D. Type 'closegears' to dismiss.\n";
    glxgears_start(0, 0, 0);
}

Main();
