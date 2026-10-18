// NeoOS Sovereign Pure HolyC Graphics Backend & Hardware Presentation Multiplexer
// Direct Ring 0 Architecture: CPU SW, VirtIO-GPU Hardware DMA, and SMP Multi-Core
// Consolidates GfxBackend.HC and GpuConfig.HC

#define GFX_MODE_CPU_SW    0
#define GFX_MODE_GPU_HW    1
#define GFX_MODE_SMP_TILED 2

#define GFX_BUFFER_DOUBLE      0
#define GFX_BUFFER_DIRECT_VRAM 1

#define ZBUFFER_PRECISION_16BIT 0
#define ZBUFFER_PRECISION_32BIT 1

#define RASTER_ENGINE_SCANLINE 0
#define RASTER_ENGINE_TILED_L1 1

#define RASTER_SHADE_FLAT      0
#define RASTER_SHADE_GOURAUD   1
#define RASTER_SHADE_WIREFRAME 2

#define TILE_SIZE_32  32
#define TILE_SIZE_64  64
#define TILE_SIZE_128 128

class CGfxBackendState {
  I64 mode;
  I64 buffering;
  I64 zprecision;
  U8  name[64];
  U32 feature_flags;
  U64 ops_counter;
  U64 dma_transfers_bytes;
  I64 raster_engine;
  I64 tile_size;
  I64 smp_cores;
  I64 shading_mode;
  I64 culling;
  I64 active_tab;
};

CGfxBackendState g_gfx;

U0 GfxBackendInit() {
  g_gfx.mode = GFX_MODE_CPU_SW;
  g_gfx.buffering = GFX_BUFFER_DOUBLE;
  g_gfx.zprecision = ZBUFFER_PRECISION_16BIT;
  strcpy(g_gfx.name, "CPU Software (UEFI)");
  g_gfx.feature_flags = 0x01;
  g_gfx.ops_counter = 0;
  g_gfx.dma_transfers_bytes = 0;
  g_gfx.raster_engine = RASTER_ENGINE_TILED_L1;
  g_gfx.tile_size = TILE_SIZE_64;
  g_gfx.smp_cores = 4;
  g_gfx.shading_mode = RASTER_SHADE_GOURAUD;
  g_gfx.culling = 1;
  g_gfx.active_tab = 0;
  g_gfx_cfg.mode = GFX_MODE_CPU_SW;
  RenderSetZeroRamMode(0);
}

U0 GfxBackendSetMode(I64 p_mode) {
  g_gfx.mode = p_mode;
  g_gfx_cfg.mode = p_mode;
  if (p_mode == GFX_MODE_GPU_HW) {
    strcpy(g_gfx.name, "VirtIO-GPU Hardware");
    g_gfx.feature_flags = 0x0F;
  } else if (p_mode == GFX_MODE_SMP_TILED) {
    strcpy(g_gfx.name, "SMP Multi-Core (4C)");
    g_gfx.feature_flags = 0x07;
  } else {
    strcpy(g_gfx.name, "CPU Software (UEFI)");
    g_gfx.feature_flags = 0x01;
  }
}

I64 GfxBackendGetMode() {
  return g_gfx.mode;
}

U8* GfxBackendGetName() {
  return g_gfx.name;
}

U0 GpuSetBuffering(I64 p_buf_mode) {
  g_gfx.buffering = p_buf_mode;
  RenderSetZeroRamMode(p_buf_mode == GFX_BUFFER_DIRECT_VRAM ? 1 : 0);
}

I64 GpuGetBuffering() {
  return g_gfx.buffering;
}

U0 GpuSetZprecision(I64 p_prec) {
  g_gfx.zprecision = p_prec;
}

I64 GpuGetZprecision() {
  return g_gfx.zprecision;
}

U0 GpuSetRasterEngine(I64 p_eng) {
  g_gfx.raster_engine = p_eng;
}

I64 GpuGetRasterEngine() {
  return g_gfx.raster_engine;
}

U0 GpuSetTileSize(I64 p_size) {
  g_gfx.tile_size = p_size;
}

I64 GpuGetTileSize() {
  return g_gfx.tile_size;
}

U0 GpuSetSmpCores(I64 p_cores) {
  g_gfx.smp_cores = p_cores;
}

I64 GpuGetSmpCores() {
  return g_gfx.smp_cores;
}

U0 GpuSetShading(I64 p_shade) {
  g_gfx.shading_mode = p_shade;
}

I64 GpuGetShading() {
  return g_gfx.shading_mode;
}

U0 GpuSetCulling(I64 p_cull) {
  g_gfx.culling = p_cull;
}

I64 GpuGetCulling() {
  return g_gfx.culling;
}

U0 GpuConfigSetTab(I64 p_tab) {
  if (p_tab >= 0 && p_tab <= 3) {
    g_gfx.active_tab = p_tab;
  }
}

I64 GpuConfigGetTab() {
  return g_gfx.active_tab;
}

U0 GfxBackendPresent(I64 p_x, I64 p_y, I64 p_w, I64 p_h, I64 p_full) {
  if (g_gfx.buffering != GFX_BUFFER_DIRECT_VRAM && g_gfx_cfg.buffer_mode != 1) {
    if (p_full) {
      gfx_swap_buffers();
    } else {
      gfx_swap_rect(p_x, p_y, p_w, p_h);
    }
  } else {
    RenderDirtyReset();
  }
  if (g_gfx.mode == GFX_MODE_GPU_HW) {
    if (VirtioGpuIsAvailable()) {
      if (p_full) {
        VirtioGpuFlushFull();
      } else {
        VirtioGpuFlushRect(p_x, p_y, p_w, p_h);
      }
    }
    g_gfx.ops_counter = g_gfx.ops_counter + 1;
    g_gfx.dma_transfers_bytes = g_gfx.dma_transfers_bytes + (p_w * p_h * 4);
  } else {
    g_gfx.ops_counter = g_gfx.ops_counter + 1;
  }
}

U0 gfx_backend_set_mode(I64 p_mode) {
  GfxBackendSetMode(p_mode);
}

I64 gfx_backend_get_mode() {
  return GfxBackendGetMode();
}

U8* gfx_backend_get_name() {
  return GfxBackendGetName();
}

U0 gfx_backend_present(I64 p_x, I64 p_y, I64 p_w, I64 p_h, I64 p_full) {
  GfxBackendPresent(p_x, p_y, p_w, p_h, p_full);
}

I64 gfx_is_zero_ram_mode() {
  return (g_gfx.buffering == GFX_BUFFER_DIRECT_VRAM || g_gfx_cfg.buffer_mode == 1) ? 1 : 0;
}

U0 gfx_set_zero_ram_mode(I64 en) {
  if (en) {
    GpuSetBuffering(GFX_BUFFER_DIRECT_VRAM);
  } else {
    GpuSetBuffering(GFX_BUFFER_DOUBLE);
  }
}

U0 GfxBackendFastClear(U32 *dst_pixels, I64 num_px, U32 clr_val) {
  I64 fc_idx = 0;
  while (fc_idx + 8 <= num_px) {
    dst_pixels[fc_idx + 0] = clr_val;
    dst_pixels[fc_idx + 1] = clr_val;
    dst_pixels[fc_idx + 2] = clr_val;
    dst_pixels[fc_idx + 3] = clr_val;
    dst_pixels[fc_idx + 4] = clr_val;
    dst_pixels[fc_idx + 5] = clr_val;
    dst_pixels[fc_idx + 6] = clr_val;
    dst_pixels[fc_idx + 7] = clr_val;
    fc_idx = fc_idx + 8;
  }
  while (fc_idx < num_px) {
    dst_pixels[fc_idx] = clr_val;
    fc_idx++;
  }
  g_gfx.dma_transfers_bytes = g_gfx.dma_transfers_bytes + (num_px * 4);
}

U0 GpuConfigPrintDolDoc() {
  doldoc_printf("$FG,CYAN$=== Sovereign HolyC Graphics Backend Hub ===$FG$\n");
  doldoc_printf(" Active Backend:      $FG,YELLOW$%s$FG$\n", g_gfx.name);
  doldoc_printf(" Raster Engine:       $FG,GREEN$%s$FG$\n",
                (g_gfx.raster_engine == RASTER_ENGINE_TILED_L1) ? "Unified L1 Tile NEON" : "Classic Scanline SIMD");
  doldoc_printf(" Tile Geometry:       $FG,CYAN$%lldx%lld$FG$\n", g_gfx.tile_size, g_gfx.tile_size);
  doldoc_printf(" Active SMP Cores:    $FG,PEACH$%lld Cores Parallel$FG$\n", g_gfx.smp_cores);
  doldoc_printf(" Shading / Depth:     $FG,WHITE$%s | %s$FG$\n",
                (g_gfx.shading_mode == RASTER_SHADE_GOURAUD) ? "Gouraud" : "Flat",
                (g_gfx.zprecision == ZBUFFER_PRECISION_16BIT) ? "16-Bit" : "32-Bit");
  doldoc_printf(" Buffering Mode:      $FG,GREEN$%s$FG$\n",
                (g_gfx.buffering == GFX_BUFFER_DOUBLE) ? "Double-Buffered (DDR RAM)" : "Direct VRAM (Zero-RAM)");
  doldoc_printf(" Ops / Transfers:     %lld ops | %lld bytes\n", g_gfx.ops_counter, g_gfx.dma_transfers_bytes);
  doldoc_printf("$FG,CYAN$============================================$FG$\n");
}

U0 GpuConfigMain() {
  doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
  doldoc_print("$FG,WHITE$     ✦ NeoOS GPU Presentation & Buffering Controller ✦$FG$\n");
  doldoc_print("$FG,CYAN$==============================================================$FG$\n");
  GpuConfigPrintDolDoc();
  doldoc_print(" Graphics Presentation Pipeline:\n");
  doldoc_print("  Actions: $BT,\"CPU SW Blit\",LM=\"render cpu\"$  $BT,\"VirtIO GPU DMA\",LM=\"render gpu\"$  $BT,\"SMP Multi-Core\",LM=\"render smp\"$\n\n");
  doldoc_print(" Sovereign L1 NEON Raster Engine:\n");
  doldoc_print("  Actions: $BT,\"Confirm L1 Tile Engine\",LM=\"raster tile\"$  $BT,\"Tile 32x32\",LM=\"tilesize 32\"$  $BT,\"Tile 64x64\",LM=\"tilesize 64\"$\n\n");
  doldoc_print(" Zero-RAM Direct-to-VRAM Buffer:\n");
  doldoc_print("  Actions: $BT,\"Zero-RAM ON\",LM=\"zeroram on\"$  $BT,\"Double-Buffer ON\",LM=\"zeroram off\"$\n");
  doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
  gpu_config_open();
}

I64 GfxBackendSelfTest() {
  doldoc_printf("\n$FG,CYAN$[GFXBACKEND-TEST] Initializing Pure HolyC Graphics Backend Test Suite...$FG$\n");

  // Test 1: Initialization defaults
  GfxBackendInit();
  if (g_gfx.mode != GFX_MODE_CPU_SW ||
      g_gfx.buffering != GFX_BUFFER_DOUBLE ||
      g_gfx.zprecision != ZBUFFER_PRECISION_16BIT ||
      g_gfx.raster_engine != RASTER_ENGINE_TILED_L1 ||
      g_gfx.tile_size != TILE_SIZE_64 ||
      g_gfx.smp_cores != 4 ||
      g_gfx.shading_mode != RASTER_SHADE_GOURAUD ||
      g_gfx.culling != 1) {
    doldoc_printf("$FG,RED$[FAIL] Test 1: Initialization state check failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 1: Default initialization state validated.$FG$\n");

  // Test 2: Mode switching and feature flags
  GfxBackendSetMode(GFX_MODE_GPU_HW);
  if (g_gfx.mode != GFX_MODE_GPU_HW || g_gfx.feature_flags != 0x0F || strcmp(g_gfx.name, "VirtIO-GPU Hardware") != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 2A: VirtIO-GPU mode switch failed!$FG$\n");
    return 0;
  }
  GfxBackendSetMode(GFX_MODE_SMP_TILED);
  if (g_gfx.mode != GFX_MODE_SMP_TILED || g_gfx.feature_flags != 0x07 || strcmp(g_gfx.name, "SMP Multi-Core (4C)") != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 2B: SMP Tiled mode switch failed!$FG$\n");
    return 0;
  }
  GfxBackendSetMode(GFX_MODE_CPU_SW);
  if (g_gfx.mode != GFX_MODE_CPU_SW || g_gfx.feature_flags != 0x01 || strcmp(g_gfx.name, "CPU Software (UEFI)") != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 2C: CPU SW mode switch failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 2: Backend mode switching and feature flags validated.$FG$\n");

  // Test 3: Buffering & raster configuration updates (including Zero-RAM link to RenderGetTargetBuffer)
  GpuSetBuffering(GFX_BUFFER_DIRECT_VRAM);
  if (GpuGetBuffering() != GFX_BUFFER_DIRECT_VRAM || RenderGetTargetBuffer() != gfx_get_frontbuffer()) {
    doldoc_printf("$FG,RED$[FAIL] Test 3A: Direct VRAM buffering failed!$FG$\n");
    return 0;
  }
  GpuSetBuffering(GFX_BUFFER_DOUBLE);
  GpuSetZprecision(ZBUFFER_PRECISION_32BIT);
  if (GpuGetZprecision() != ZBUFFER_PRECISION_32BIT) {
    doldoc_printf("$FG,RED$[FAIL] Test 3B: Zprecision failed!$FG$\n");
    return 0;
  }
  GpuSetTileSize(TILE_SIZE_32);
  if (GpuGetTileSize() != 32) {
    doldoc_printf("$FG,RED$[FAIL] Test 3C: TileSize failed!$FG$\n");
    return 0;
  }
  GpuSetSmpCores(2);
  if (GpuGetSmpCores() != 2) {
    doldoc_printf("$FG,RED$[FAIL] Test 3D: SmpCores failed!$FG$\n");
    return 0;
  }
  GpuSetShading(RASTER_SHADE_FLAT);
  if (GpuGetShading() != RASTER_SHADE_FLAT) {
    doldoc_printf("$FG,RED$[FAIL] Test 3E: Shading failed!$FG$\n");
    return 0;
  }
  GpuSetCulling(0);
  if (GpuGetCulling() != 0) {
    doldoc_printf("$FG,RED$[FAIL] Test 3F: Culling failed!$FG$\n");
    return 0;
  }
  GpuConfigSetTab(2);
  if (GpuConfigGetTab() != 2) {
    doldoc_printf("$FG,RED$[FAIL] Test 3G: Tab switch failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 3: Zero-RAM direct scanout, geometry, shading, and tab configuration validated.$FG$\n");

  // Test 4: Fast clear memory test
  U32 *t_buf = kmalloc(256 * 4);
  if (!t_buf) {
    doldoc_printf("$FG,RED$[FAIL] Test 4: kmalloc failed for test buffer!$FG$\n");
    return 0;
  }
  GfxBackendFastClear(t_buf, 256, 0x11223344);
  I64 chk_i = 0;
  I64 clr_ok = 1;
  while (chk_i < 256) {
    if (t_buf[chk_i] != 0x11223344) {
      clr_ok = 0;
      break;
    }
    chk_i++;
  }
  kfree(t_buf);
  if (!clr_ok || g_gfx.dma_transfers_bytes < 1024) {
    doldoc_printf("$FG,RED$[FAIL] Test 4: FastClear verification failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 4: Fast buffer clear verified across 256 pixels.$FG$\n");

  // Test 5: Presentation multiplexing
  U64 ops_before = g_gfx.ops_counter;
  GfxBackendSetMode(GFX_MODE_GPU_HW);
  GfxBackendPresent(0, 0, 1024, 768, 1);
  GfxBackendPresent(10, 10, 100, 100, 0);
  if (g_gfx.ops_counter != ops_before + 2) {
    doldoc_printf("$FG,RED$[FAIL] Test 5: Presentation ops counter failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 5: Presentation multiplexing verified.$FG$\n");

  GfxBackendInit();
  doldoc_printf("\n[GFXBACKEND-PASS] ALL 5 GRAPHICS BACKEND TESTS PASSED\n\n");
  return 1;
}

if (g_kernel_booting) {
  GfxBackendInit();
} else {
  GfxBackendSelfTest();
}
