// ==============================================================================
// apps/GpuConfig.HC - P7.5 Unified GPU Configuration Plane
// Architecture: ARMv8-A Ring 0 (EL1) | Single Address Space OS (SASOS)
//
// ONE canonical configuration struct (CGpuConfig g_gpu_cfg) replacing the old
// split g_gfx_cfg (Render.HC) + ad-hoc flags. It exposes the five real
// hardware/pipeline knobs through clean functional accessors, so no other module
// ever touches a struct member directly (sovereign cross-module rule):
//
//   1. buffer_mode  0=single/direct, 1=double, 2=triple   (Render scanout)
//   2. tile_size    32 or 64 px                            (RasterTile TILE_W/H)
//   3. smp_cores    1..4 workers                           (RasterSceneEndSmp clamp)
//   4. zprecision   16 or 32 bits                          (Z-buffer element width)
//   5. vsync        0=off, 1=on (60 Hz via CNTVCT_EL0)     (Render present)
//
// Setters CLAMP to the legal range and never fail silently; getters are the
// single source of truth. The consumers (Render.HC, RasterTile.HC, GfxDevice.HC)
// PULL the values at use time, so there is no cross-module push and no cycle.
// ==============================================================================

#define GPU_BUF_SINGLE   0
#define GPU_BUF_DOUBLE   1
#define GPU_BUF_TRIPLE   2
#define GPU_TILE_MIN     32
#define GPU_TILE_MAX     64
#define GPU_CORES_MIN    1
#define GPU_CORES_MAX    4
#define GPU_Z16          16
#define GPU_Z32          32
#define GPU_MODE_CPU     0
#define GPU_MODE_HW      1
#define GPU_MODE_SMP     2

class CGpuConfig {
  I64 mode;          // mirrors GfxDevice mode (0 CPU, 1 HW, 2 SMP tiled)
  I64 buffer_mode;   // 0 single/direct, 1 double, 2 triple
  I64 tile_size;     // 32 or 64
  I64 smp_cores;     // 1..4
  I64 zprecision;    // 16 or 32
  I64 vsync_en;      // 0/1
  I64 vsync_hz;      // 60
};

CGpuConfig g_gpu_cfg;

U0 GpuConfigInit() {
  g_gpu_cfg.mode = GPU_MODE_CPU;
  g_gpu_cfg.buffer_mode = GPU_BUF_DOUBLE;
  g_gpu_cfg.tile_size = 64;
  g_gpu_cfg.smp_cores = GPU_CORES_MAX;
  g_gpu_cfg.zprecision = GPU_Z16;
  g_gpu_cfg.vsync_en = 0;
  g_gpu_cfg.vsync_hz = 60;
}

// ---- 0. pipeline mode (mirrors GfxDevice; kept in sync by GfxDeviceSetMode) ----
I64 gpu_get_mode() { return g_gpu_cfg.mode; }
U0  gpu_set_mode(I64 m) {
  if (m < GPU_MODE_CPU) m = GPU_MODE_CPU;
  if (m > GPU_MODE_SMP) m = GPU_MODE_SMP;
  g_gpu_cfg.mode = m;
}

// ---- 1. buffer mode (single/direct, double, triple) ----
I64 gpu_get_buffer_mode() { return g_gpu_cfg.buffer_mode; }
U0  gpu_set_buffer_mode(I64 m) {
  if (m < GPU_BUF_SINGLE) m = GPU_BUF_SINGLE;
  if (m > GPU_BUF_TRIPLE) m = GPU_BUF_TRIPLE;
  g_gpu_cfg.buffer_mode = m;
}

// ---- 2. tile size (32 or 64 px; snapped to a supported value) ----
I64 gpu_get_tile_size() { return g_gpu_cfg.tile_size; }
U0  gpu_set_tile_size(I64 sz) {
  if (sz < GPU_TILE_MIN) sz = GPU_TILE_MIN;
  if (sz > GPU_TILE_MAX) sz = GPU_TILE_MAX;
  if (sz < 64) sz = 32; else sz = 64;   // only 32 and 64 are supported
  g_gpu_cfg.tile_size = sz;
}

// ---- 3. SMP worker count (1..4) ----
I64 gpu_get_smp_cores() { return g_gpu_cfg.smp_cores; }
U0  gpu_set_smp_cores(I64 n) {
  if (n < GPU_CORES_MIN) n = GPU_CORES_MIN;
  if (n > GPU_CORES_MAX) n = GPU_CORES_MAX;
  g_gpu_cfg.smp_cores = n;
}

// ---- 4. Z precision (16 or 32 bits) ----
I64 gpu_get_zprecision() { return g_gpu_cfg.zprecision; }
U0  gpu_set_zprecision(I64 bits) {
  if (bits <= GPU_Z16) bits = GPU_Z16; else bits = GPU_Z32;
  g_gpu_cfg.zprecision = bits;
}

// ---- 5. vsync (0=off, 1=on @ vsync_hz) ----
I64 gpu_get_vsync() { return g_gpu_cfg.vsync_en; }
U0  gpu_set_vsync(I64 en) { g_gpu_cfg.vsync_en = en ? 1 : 0; }
I64 gpu_get_vsync_hz() { return g_gpu_cfg.vsync_hz; }

if (g_kernel_booting) {
  GpuConfigInit();
}
