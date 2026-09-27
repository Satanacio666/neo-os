# NeoOS Sprint 1 — Maximum Performance

- [/] 1. `gui/render.c` + `render.h` — NEON blit, clear, dirty rect, vsync
- [ ] 2. `drivers/input/mouse.c` + `mouse.h` — LocateHandleBuffer, WaitForEvent, cursor_to_front
- [ ] 3. `kernel/math/math3d.c` + `math3d.h` — mat4_mul NEON, vec3_dot NEON, fast_rsqrt
- [ ] 4. `kernel/math/gears3d.c` — NEON span fill in scanline rasterizer
- [ ] 5. `kernel/bench/perf_overlay.c` + `perf_overlay.h` — [NEW] ring buffer, 1%low, 0.1%low, stddev
- [ ] 6. `kernel/bench/glxgears.c` — integrate perf_overlay
- [ ] 7. `kernel/bench/bench_suite.c` — integrate perf_overlay, unify with gears
- [ ] 8. `boot/main.c` — WaitForEvent idle loop, vsync call, cursor_to_front
- [ ] 9. `gui/shell.c` — vsync, perf, bench commands
- [ ] 10. Build & verify
