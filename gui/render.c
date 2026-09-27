#include "render.h"
#include "font_ttf.h"
#include "mem/kheap.h"
#include <uefi.h>
#include <stdarg.h>

static canvas_t canvas = {0};
static uint32_t *s_dedicated_backbuffer = NULL;

#include "../drivers/gpu/gfx_backend.h"

// ─── NEON Non-Temporal Streaming Blit ────────────────────────────────────────
// ldnp/stnp bypass L1/L2 — ideal for Write-Combining framebuffer writes
// 64 bytes per iteration (4×128-bit NEON registers)
static void gfx_neon_blit_nt(void *dst, const void *src, size_t bytes) {
    // bytes must be multiple of 64; caller guarantees this via align mask
    __asm__ volatile(
        "1:\n"
        "   ldnp q0, q1, [%[s], #0]\n"
        "   ldnp q2, q3, [%[s], #32]\n"
        "   stnp q0, q1, [%[d], #0]\n"
        "   stnp q2, q3, [%[d], #32]\n"
        "   add  %[s], %[s], #64\n"
        "   add  %[d], %[d], #64\n"
        "   subs %[n], %[n], #64\n"
        "   b.hi 1b\n"
        : [d] "+r"(dst), [s] "+r"(src), [n] "+r"(bytes)
        :
        : "q0","q1","q2","q3","memory"
    );
}

// ─── VSync / Frame Pacing ─────────────────────────────────────────────────────
static struct {
    int      enabled;
    uint64_t target_ns;     // nanoseconds per frame
    uint64_t last_end_ns;   // timestamp of last frame end
    uint64_t freq;          // cntfrq_el0 value
} s_vsync = {0};

static uint64_t vsync_get_freq(void) {
    if (!s_vsync.freq) {
        uint64_t f;
        __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(f));
        s_vsync.freq = (f > 0) ? f : 62500000ULL;
    }
    return s_vsync.freq;
}

static uint64_t vsync_now_ns(void) {
    uint64_t t;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t));
    uint64_t freq = vsync_get_freq();
    return (t / freq) * 1000000000ULL + ((t % freq) * 1000000000ULL) / freq;
}

void gfx_vsync_init(void) {
    vsync_get_freq();
    s_vsync.enabled    = 0;
    s_vsync.target_ns  = 16666667ULL;  // 60 Hz default
    s_vsync.last_end_ns = vsync_now_ns();
}

void gfx_vsync_set(int enable, uint32_t hz) {
    s_vsync.enabled = enable;
    if (hz == 0 || hz > 500) hz = 60;
    s_vsync.target_ns = 1000000000ULL / (uint64_t)hz;
}

int gfx_vsync_get_enabled(void) {
    return s_vsync.enabled;
}

uint32_t gfx_vsync_get_hz(void) {
    if (!s_vsync.enabled || s_vsync.target_ns == 0) return 0;
    return (uint32_t)(1000000000ULL / s_vsync.target_ns);
}

void gfx_vsync_wait(void) {
    if (!s_vsync.enabled) return;
    uint64_t now = vsync_now_ns();
    uint64_t deadline = s_vsync.last_end_ns + s_vsync.target_ns;
    if (now >= deadline) {
        s_vsync.last_end_ns = now;
        return;
    }
    if (deadline - now > s_vsync.target_ns) {
        s_vsync.last_end_ns = now;
        return;
    }
    while (vsync_now_ns() < deadline) {
        __asm__ volatile("yield");
    }
    s_vsync.last_end_ns = vsync_now_ns();
}

// ─── Dirty Rect Accumulator ───────────────────────────────────────────────────
static struct { int x0,y0,x1,y1,valid; } s_dirty = {0};

static void dirty_expand(int x, int y, int w, int h) {
    int x2 = x + w, y2 = y + h;
    if (!s_dirty.valid) {
        s_dirty.x0 = x; s_dirty.y0 = y;
        s_dirty.x1 = x2; s_dirty.y1 = y2;
        s_dirty.valid = 1;
    } else {
        if (x  < s_dirty.x0) s_dirty.x0 = x;
        if (y  < s_dirty.y0) s_dirty.y0 = y;
        if (x2 > s_dirty.x1) s_dirty.x1 = x2;
        if (y2 > s_dirty.y1) s_dirty.y1 = y2;
    }
}

void gfx_dirty_reset(void)  { s_dirty.valid = 0; }
void gfx_dirty_all(void) {
    s_dirty.x0 = 0; s_dirty.y0 = 0;
    s_dirty.x1 = (int)canvas.width; s_dirty.y1 = (int)canvas.height;
    s_dirty.valid = 1;
}
void gfx_dirty_expand(int x, int y, int w, int h) {
    dirty_expand(x, y, w, h);
}

static int s_zero_ram_mode = 0;

// Built-in 8x16 Font Data for basic ASCII (32 to 126)
// A classic, crisp 8x16 font embedded directly into the kernel
#include "font8x16.h"

// DolDoc Console Viewport state
static struct {
    uint32_t x, y, w, h;
    uint32_t cursor_x, cursor_y;
    uint32_t text_color;
    uint32_t bg_color;
} doc_term = {0};

void gfx_init(uint32_t *vram_base, uint32_t w, uint32_t h, uint32_t pitch) {
    canvas.front_buffer = vram_base;
    canvas.width = w;
    canvas.height = h;
    canvas.pitch = pitch;
    canvas.buffer_size_bytes = (size_t)pitch * h * sizeof(uint32_t);

    // Allocate backbuffer in normal cacheable RAM via dedicated pages to protect the kernel heap
    efi_physical_address_t back_phys = 0;
    size_t num_pages = (canvas.buffer_size_bytes + 4095) / 4096;
    if (BS && !EFI_ERROR(BS->AllocatePages(AllocateAnyPages, EfiLoaderData, num_pages, &back_phys)) && back_phys) {
        canvas.back_buffer = (uint32_t*)back_phys;
        printf("[GFX] Double-buffering initialized via dedicated pages (%u x %u, %llu MB buffer at 0x%p)\n",
               w, h, (unsigned long long)(canvas.buffer_size_bytes / (1024 * 1024)), canvas.back_buffer);
    } else {
        canvas.back_buffer = (uint32_t*)kmalloc(canvas.buffer_size_bytes);
        if (!canvas.back_buffer) {
            printf("[GFX] Warning: Failed to allocate backbuffer in heap! Falling back to single buffer.\n");
            canvas.back_buffer = vram_base;
        } else {
            printf("[GFX] Double-buffering initialized (%u x %u, %llu MB buffer)\n",
                   w, h, (unsigned long long)(canvas.buffer_size_bytes / (1024 * 1024)));
        }
    }
    s_dedicated_backbuffer = canvas.back_buffer;

    gfx_vsync_init();
    gfx_dirty_all();
    gfx_clear(COLOR_BG_DARK);
    gfx_swap_buffers();
}

int gfx_is_active(void) {
    return (canvas.front_buffer != NULL);
}

static struct {
    int active;
    int x0, y0, x1, y1;
} clip_rect = {0, 0, 0, 0, 0};

void gfx_set_clip(int x, int y, int w, int h) {
    clip_rect.active = 1;
    clip_rect.x0 = (x < 0) ? 0 : x;
    clip_rect.y0 = (y < 0) ? 0 : y;
    clip_rect.x1 = (x + w > (int)canvas.width) ? (int)canvas.width : (x + w);
    clip_rect.y1 = (y + h > (int)canvas.height) ? (int)canvas.height : (y + h);
}

void gfx_reset_clip(void) {
    clip_rect.active = 0;
}

void gfx_get_clip(int *x, int *y, int *w, int *h) {
    if (!clip_rect.active) {
        if (x) *x = 0;
        if (y) *y = 0;
        if (w) *w = (int)canvas.width;
        if (h) *h = (int)canvas.height;
    } else {
        if (x) *x = clip_rect.x0;
        if (y) *y = clip_rect.y0;
        if (w) *w = clip_rect.x1 - clip_rect.x0;
        if (h) *h = clip_rect.y1 - clip_rect.y0;
    }
}

void gfx_clear(uint32_t color) {
    // NEON fill: 64 bytes (16 pixels) per iteration via stnp (non-temporal)
    // This avoids polluting L1/L2 cache with framebuffer data
    size_t total_pixels = (size_t)canvas.pitch * canvas.height;
    uint32_t *buf = canvas.back_buffer;
    size_t i = 0;
    size_t bulk = total_pixels & ~15UL;  // floor to multiple of 16 pixels
    if (bulk > 0) {
        __asm__ volatile(
            "dup  v0.4s, %w[col]\n"     // v0 = {color, color, color, color}
            "mov  v1.16b, v0.16b\n"     // v1 = v0
            "mov  v2.16b, v0.16b\n"
            "mov  v3.16b, v0.16b\n"
            "1:\n"
            "stnp q0, q1, [%[p], #0]\n"
            "stnp q2, q3, [%[p], #32]\n"
            "add  %[p], %[p], #64\n"
            "subs %[n], %[n], #16\n"    // 16 pixels of 4 bytes = 64 bytes
            "b.hi 1b\n"
            : [p] "+r"(buf), [n] "+r"(bulk)
            : [col] "r"(color)
            : "v0","v1","v2","v3","memory"
        );
        i = total_pixels & ~15UL;
        buf = canvas.back_buffer + i;
    }
    // Tail: remaining 0–15 pixels
    for (; i < total_pixels; i++) canvas.back_buffer[i] = color;
    // Clear always marks the whole canvas dirty
    gfx_dirty_all();
}

void gfx_put_pixel(uint32_t x, uint32_t y, uint32_t color) {
    if (clip_rect.active) {
        if ((int)x < clip_rect.x0 || (int)x >= clip_rect.x1 ||
            (int)y < clip_rect.y0 || (int)y >= clip_rect.y1) {
            return;
        }
    }
    if (x < canvas.width && y < canvas.height) {
        canvas.back_buffer[y * canvas.pitch + x] = color;
    }
}

void gfx_blend_pixel(uint32_t x, uint32_t y, uint32_t color_rgba) {
    if (clip_rect.active) {
        if ((int)x < clip_rect.x0 || (int)x >= clip_rect.x1 ||
            (int)y < clip_rect.y0 || (int)y >= clip_rect.y1) {
            return;
        }
    }
    if (x >= canvas.width || y >= canvas.height) return;

    uint32_t a = (color_rgba >> 24) & 0xFF;
    if (a == 0) return;
    if (a == 255) {
        canvas.back_buffer[y * canvas.pitch + x] = color_rgba;
        return;
    }

    uint32_t dst = canvas.back_buffer[y * canvas.pitch + x];
    uint32_t inv_a = 255 - a;

    uint32_t r = (((color_rgba >> 16) & 0xFF) * a + ((dst >> 16) & 0xFF) * inv_a + 128) >> 8;
    uint32_t g = (((color_rgba >> 8)  & 0xFF) * a + ((dst >> 8)  & 0xFF) * inv_a + 128) >> 8;
    uint32_t b = (((color_rgba)       & 0xFF) * a + ((dst)       & 0xFF) * inv_a + 128) >> 8;

    canvas.back_buffer[y * canvas.pitch + x] = (0xFF000000) | (r << 16) | (g << 8) | b;
}

void gfx_draw_line_clipped(int x0, int y0, int x1, int y1, uint32_t color) {
    int dx = (x1 > x0) ? (x1 - x0) : (x0 - x1);
    int sx = (x0 < x1) ? 1 : -1;
    int dy = (y1 > y0) ? (y0 - y1) : (y1 - y0);
    int sy = (y0 < y1) ? 1 : -1;
    int err = dx + dy;

    while (1) {
        if (x0 >= 0 && (uint32_t)x0 < canvas.width && y0 >= 0 && (uint32_t)y0 < canvas.height) {
            gfx_put_pixel((uint32_t)x0, (uint32_t)y0, color);
        }
        if (x0 == x1 && y0 == y1) break;
        int e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

void gfx_draw_line(int x0, int y0, int x1, int y1, uint32_t color) {
    gfx_draw_line_clipped(x0, y0, x1, y1, color);
}

void gfx_fill_circle(int cx, int cy, int radius, uint32_t color) {
    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            if (x * x + y * y <= radius * radius) {
                int px = cx + x;
                int py = cy + y;
                if (px >= 0 && py >= 0) {
                    gfx_put_pixel((uint32_t)px, (uint32_t)py, color);
                }
            }
        }
    }
}

void gfx_draw_triangle_wire(int x0, int y0, int x1, int y1, int x2, int y2, uint32_t color) {
    gfx_draw_line_clipped(x0, y0, x1, y1, color);
    gfx_draw_line_clipped(x1, y1, x2, y2, color);
    gfx_draw_line_clipped(x2, y2, x0, y0, color);
}

static void swap_int(int *a, int *b) {
    int t = *a; *a = *b; *b = t;
}

void gfx_draw_triangle_fill(int x0, int y0, int x1, int y1, int x2, int y2, uint32_t color) {
    if (y0 > y1) { swap_int(&y0, &y1); swap_int(&x0, &x1); }
    if (y1 > y2) { swap_int(&y1, &y2); swap_int(&x1, &x2); }
    if (y0 > y1) { swap_int(&y0, &y1); swap_int(&x0, &x1); }

    int total_height = y2 - y0;
    if (total_height <= 0) return;

    for (int i = 0; i <= total_height; i++) {
        int second_half = i > (y1 - y0) || y1 == y0;
        int segment_height = second_half ? (y2 - y1) : (y1 - y0);
        if (segment_height <= 0) continue;

        float alpha = (float)i / (float)total_height;
        float beta  = (float)(i - (second_half ? (y1 - y0) : 0)) / (float)segment_height;

        int ax = x0 + (int)((float)(x2 - x0) * alpha);
        int bx = second_half ? (x1 + (int)((float)(x2 - x1) * beta)) : (x0 + (int)((float)(x1 - x0) * beta));

        if (ax > bx) swap_int(&ax, &bx);

        int cy = y0 + i;
        for (int cx = ax; cx <= bx; cx++) {
            if (cx >= 0 && cy >= 0) {
                gfx_put_pixel((uint32_t)cx, (uint32_t)cy, color);
            }
        }
    }
}

void gfx_draw_rect(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t color) {
    if ((int)w <= 0 || (int)h <= 0) return;
    int min_x = (int)x;
    int min_y = (int)y;
    int max_x = min_x + (int)w;
    int max_y = min_y + (int)h;

    if (min_x < 0) min_x = 0;
    if (min_y < 0) min_y = 0;
    if (max_x > (int)canvas.width) max_x = (int)canvas.width;
    if (max_y > (int)canvas.height) max_y = (int)canvas.height;

    if (clip_rect.active) {
        if (min_x < clip_rect.x0) min_x = clip_rect.x0;
        if (min_y < clip_rect.y0) min_y = clip_rect.y0;
        if (max_x > clip_rect.x1) max_x = clip_rect.x1;
        if (max_y > clip_rect.y1) max_y = clip_rect.y1;
    }
    if (min_x >= max_x || min_y >= max_y) return;

    int span_w = max_x - min_x;
    uint64_t color64 = ((uint64_t)color << 32) | (uint32_t)color;

    for (int j = min_y; j < max_y; j++) {
        uint32_t *row = &canvas.back_buffer[j * canvas.pitch + min_x];
        int k = 0;
        // Fast 32-byte / 8-pixel unrolled stores
        for (; k <= span_w - 8; k += 8) {
            uint64_t *r64 = (uint64_t*)(row + k);
            r64[0] = color64;
            r64[1] = color64;
            r64[2] = color64;
            r64[3] = color64;
        }
        for (; k < span_w; k++) {
            row[k] = color;
        }
    }
}

void gfx_blend_rect(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t color_rgba) {
    if ((int)w <= 0 || (int)h <= 0) return;
    int min_x = (int)x;
    int min_y = (int)y;
    int max_x = min_x + (int)w;
    int max_y = min_y + (int)h;

    if (min_x < 0) min_x = 0;
    if (min_y < 0) min_y = 0;
    if (max_x > (int)canvas.width) max_x = (int)canvas.width;
    if (max_y > (int)canvas.height) max_y = (int)canvas.height;

    if (clip_rect.active) {
        if (min_x < clip_rect.x0) min_x = clip_rect.x0;
        if (min_y < clip_rect.y0) min_y = clip_rect.y0;
        if (max_x > clip_rect.x1) max_x = clip_rect.x1;
        if (max_y > clip_rect.y1) max_y = clip_rect.y1;
    }
    if (min_x >= max_x || min_y >= max_y) return;

    uint32_t a = (color_rgba >> 24) & 0xFF;
    if (a == 0) return;
    if (a == 255) {
        gfx_draw_rect(min_x, min_y, max_x - min_x, max_y - min_y, color_rgba);
        return;
    }

    uint32_t inv_a = 255 - a;
    uint32_t src_r = ((color_rgba >> 16) & 0xFF) * a + 128;
    uint32_t src_g = ((color_rgba >> 8)  & 0xFF) * a + 128;
    uint32_t src_b = ((color_rgba)       & 0xFF) * a + 128;

    // Pre-compute NEON-friendly source values as 16-bit
    uint16_t src_b16 = (uint16_t)src_b;
    uint16_t src_g16 = (uint16_t)src_g;
    uint16_t src_r16 = (uint16_t)src_r;
    uint16_t inv_a8  = (uint16_t)(inv_a & 0xFF);

    for (int j = min_y; j < max_y; j++) {
        uint32_t *row = &canvas.back_buffer[j * canvas.pitch];
        int i = min_x;
        int span = max_x - min_x;
        int bulk_end = min_x + (span & ~7); // floor to multiple of 8

        // NEON: process 8 ARGB pixels per iteration via ld4/st4 byte deinterleave
        for (; i < bulk_end; i += 8) {
            uint32_t *ptr = row + i;
            __asm__ volatile(
                // Load 8 pixels deinterleaved: v0=B, v1=G, v2=R, v3=A (8 bytes each)
                "ld4   {v0.8b, v1.8b, v2.8b, v3.8b}, [%[ptr]]\n"
                // Widen dst channels to 16-bit and multiply by inv_a
                "dup   v7.8b, %w[ia]\n"          // v7 = inv_a broadcast
                "umull  v4.8h, v0.8b, v7.8b\n"   // v4 = B * inv_a (16-bit)
                "umull  v5.8h, v1.8b, v7.8b\n"   // v5 = G * inv_a
                "umull  v6.8h, v2.8b, v7.8b\n"   // v6 = R * inv_a
                // Add pre-multiplied source (src_ch * a + 128) as 16-bit
                "dup   v16.8h, %w[sb]\n"          // v16 = src_b broadcast
                "dup   v17.8h, %w[sg]\n"
                "dup   v18.8h, %w[sr]\n"
                "add   v4.8h, v4.8h, v16.8h\n"   // B_result = B*inv_a + src_b
                "add   v5.8h, v5.8h, v17.8h\n"   // G_result
                "add   v6.8h, v6.8h, v18.8h\n"   // R_result
                // Shift right by 8 and narrow to 8-bit
                "shrn   v0.8b, v4.8h, #8\n"      // B final
                "shrn   v1.8b, v5.8h, #8\n"      // G final
                "shrn   v2.8b, v6.8h, #8\n"      // R final
                // Set alpha to 0xFF
                "movi   v3.8b, #0xFF\n"
                // Store 8 pixels re-interleaved
                "st4   {v0.8b, v1.8b, v2.8b, v3.8b}, [%[ptr]]\n"
                : : [ptr] "r"(ptr),
                    [ia] "r"(inv_a8), [sb] "r"(src_b16), [sg] "r"(src_g16), [sr] "r"(src_r16)
                : "v0","v1","v2","v3","v4","v5","v6","v7","v16","v17","v18","memory"
            );
        }
        // Scalar tail: remaining 0-7 pixels
        for (; i < max_x; i++) {
            uint32_t dst = row[i];
            uint32_t r = (src_r + ((dst >> 16) & 0xFF) * inv_a) >> 8;
            uint32_t g = (src_g + ((dst >> 8)  & 0xFF) * inv_a) >> 8;
            uint32_t b = (src_b + ((dst)       & 0xFF) * inv_a) >> 8;
            row[i] = 0xFF000000 | (r << 16) | (g << 8) | b;
        }
    }
}

void gfx_draw_rounded_rect(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t radius, uint32_t color) {
    if (radius > w / 2) radius = w / 2;
    if (radius > h / 2) radius = h / 2;

    // Center body
    gfx_draw_rect(x + radius, y, w - 2 * radius, h, color);
    // Left & right sides
    gfx_draw_rect(x, y + radius, radius, h - 2 * radius, color);
    gfx_draw_rect(x + w - radius, y + radius, radius, h - 2 * radius, color);

    // 4 Rounded Corners (Circle equation: dx^2 + dy^2 <= r^2)
    int r2 = radius * radius;
    for (int dy = 0; dy < (int)radius; dy++) {
        for (int dx = 0; dx < (int)radius; dx++) {
            int dist2 = (radius - 1 - dx) * (radius - 1 - dx) + (radius - 1 - dy) * (radius - 1 - dy);
            if (dist2 <= r2) {
                // Top-left
                gfx_put_pixel(x + dx, y + dy, color);
                // Top-right
                gfx_put_pixel(x + w - 1 - dx, y + dy, color);
                // Bottom-left
                gfx_put_pixel(x + dx, y + h - 1 - dy, color);
                // Bottom-right
                gfx_put_pixel(x + w - 1 - dx, y + h - 1 - dy, color);
            }
        }
    }
}

void gfx_draw_shadow(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t spread) {
    if (spread > 8) spread = 8;
    for (uint32_t s = 1; s <= spread; s++) {
        uint32_t alpha = (35 * (spread - s + 1)) / spread; // Soft gradient alpha
        uint32_t shadow_color = (alpha << 24); // Black with variable alpha

        int sx = (int)x - (int)s;
        int sy = (int)y - (int)s;
        int sw = (int)w + 2 * (int)s;

        if (sx < 0) { sw += sx; sx = 0; }
        if (sw <= 0) continue;

        // Top band
        if (sy >= 0 && sy < (int)canvas.height) {
            gfx_blend_rect((uint32_t)sx, (uint32_t)sy, (uint32_t)sw, 1, shadow_color);
        }
        // Bottom band
        int by = (int)(y + h + s - 1);
        if (by >= 0 && by < (int)canvas.height) {
            gfx_blend_rect((uint32_t)sx, (uint32_t)by, (uint32_t)sw, 1, shadow_color);
        }
        // Left & Right bands
        int side_y = (int)y - (int)s + 1;
        int side_h = (int)h + 2 * (int)s - 2;
        if (side_y < 0) { side_h += side_y; side_y = 0; }
        if (side_h > 0) {
            if (sx >= 0 && sx < (int)canvas.width) {
                gfx_blend_rect((uint32_t)sx, (uint32_t)side_y, 1, (uint32_t)side_h, shadow_color);
            }
            int rx = (int)(x + w + s - 1);
            if (rx >= 0 && rx < (int)canvas.width) {
                gfx_blend_rect((uint32_t)rx, (uint32_t)side_y, 1, (uint32_t)side_h, shadow_color);
            }
        }
    }
}

void gfx_draw_char(uint32_t x, uint32_t y, char c, uint32_t fg, uint32_t bg) {
    if ((unsigned char)c < 32 || (unsigned char)c > 126) c = ' ';
    const uint8_t *glyph = font8x16_data[(unsigned char)c - 32];

    for (int row = 0; row < 16; row++) {
        uint8_t bits = glyph[row];
        for (int col = 0; col < 8; col++) {
            if (bits & (0x80 >> col)) {
                gfx_put_pixel(x + col, y + row, fg);
            } else if (bg != 0) {
                gfx_put_pixel(x + col, y + row, bg);
            }
        }
    }
}

void gfx_draw_string(uint32_t x, uint32_t y, const char *str, uint32_t fg, uint32_t bg) {
    if (!str) return;
    if (bg == 0 && font_ttf_is_ready()) {
        font_ttf_draw_string(x, y, str, fg);
        return;
    }
    uint32_t cur_x = x;
    while (*str) {
        if (*str == '\n') {
            y += 18;
            cur_x = x;
        } else {
            gfx_draw_char(cur_x, y, *str, fg, bg);
            cur_x += 8;
        }
        str++;
    }
}

static uint64_t s_last_swap_us = 0;

uint64_t gfx_get_last_swap_us(void) {
    return s_last_swap_us;
}

void gfx_swap_buffers(void) {
    if (!canvas.front_buffer || !canvas.back_buffer) {
        s_dirty.valid = 0;
        return;
    }
    if (canvas.front_buffer == canvas.back_buffer) {
        // Direct VRAM Zero-RAM mode: 0ms blit, forward dirty rect to active HAL
        if (s_dirty.valid) {
            int dx = s_dirty.x0, dy = s_dirty.y0;
            int dw = s_dirty.x1 - s_dirty.x0;
            int dh = s_dirty.y1 - s_dirty.y0;
            int total = (int)canvas.width * (int)canvas.height;
            gfx_backend_present(dx, dy, dw, dh, (dw * dh >= total * 3 / 4));
            s_dirty.valid = 0;
        }
        s_last_swap_us = 0;
        return;
    }
    if (!s_dirty.valid) return; // nothing changed, skip blit entirely

    // Clamp dirty rect to canvas bounds
    int dx = s_dirty.x0, dy = s_dirty.y0;
    int dw = s_dirty.x1 - s_dirty.x0;
    int dh = s_dirty.y1 - s_dirty.y0;
    if (dw <= 0 || dh <= 0) { s_dirty.valid = 0; return; }

    // Full-frame blit: if dirty rect covers ≥75% of canvas, blit whole frame
    // with NEON NT (faster than row-by-row overhead for large rects)
    int total = (int)canvas.width * (int)canvas.height;
    uint64_t c0, c1;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(c0));
    if (dw * dh >= total * 3 / 4) {
        size_t bytes    = canvas.buffer_size_bytes;
        size_t aligned  = bytes & ~63ULL;
        gfx_neon_blit_nt(canvas.front_buffer, canvas.back_buffer, aligned);
        // tail bytes (0..63)
        uint8_t *fd = (uint8_t*)canvas.front_buffer + aligned;
        const uint8_t *fs = (const uint8_t*)canvas.back_buffer + aligned;
        for (size_t i = 0; i < (bytes - aligned); i++) fd[i] = fs[i];
    } else {
        // Dirty-rect blit: NEON NT per row, only the changed region
        if (dx < 0) { dw += dx; dx = 0; }
        if (dy < 0) { dh += dy; dy = 0; }
        if (dx + dw > (int)canvas.width)  dw = (int)canvas.width  - dx;
        if (dy + dh > (int)canvas.height) dh = (int)canvas.height - dy;
        if (dw <= 0 || dh <= 0) { s_dirty.valid = 0; return; }

        for (int row = dy; row < dy + dh; row++) {
            void *d = canvas.front_buffer + row * canvas.pitch + dx;
            const void *s = canvas.back_buffer + row * canvas.pitch + dx;
            size_t bytes_row = (size_t)dw * 4;
            size_t aligned_row = bytes_row & ~63ULL;
            if (aligned_row > 0)
                gfx_neon_blit_nt(d, s, aligned_row);
            // scalar tail
            uint8_t *rd = (uint8_t*)d + aligned_row;
            const uint8_t *rs = (const uint8_t*)s + aligned_row;
            for (size_t t = 0; t < (bytes_row - aligned_row); t++) rd[t] = rs[t];
        }
    }
    // Route presentation through unified Graphics HAL (CPU SW, VirtIO GPU, or SMP)
    gfx_backend_present(dx, dy, dw, dh, (dw * dh >= total * 3 / 4));
    s_dirty.valid = 0;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(c1));
    uint64_t freq = vsync_get_freq();
    s_last_swap_us = (c1 > c0) ? (((c1 - c0) * 1000000ULL) / freq) : 820;
    if (s_last_swap_us == 0) s_last_swap_us = 1;
}

// gfx_swap_rect: NEON NT row blit for explicit rect (used by window manager)
void gfx_swap_rect(int x, int y, int w, int h) {
    if (!canvas.front_buffer || !canvas.back_buffer) return;
    if (x < 0) { w += x; x = 0; }
    if (y < 0) { h += y; y = 0; }
    if (x + w > (int)canvas.width)  w = (int)canvas.width - x;
    if (y + h > (int)canvas.height) h = (int)canvas.height - y;
    if (w <= 0 || h <= 0) return;

    if (canvas.front_buffer != canvas.back_buffer) {
        uint64_t c0, c1;
        __asm__ volatile("mrs %0, cntvct_el0" : "=r"(c0));
        for (int row = y; row < y + h; row++) {
            void *d = canvas.front_buffer + row * canvas.pitch + x;
            const void *s = canvas.back_buffer + row * canvas.pitch + x;
            size_t bytes_row = (size_t)w * 4;
            size_t aligned_row = bytes_row & ~63ULL;
            if (aligned_row > 0)
                gfx_neon_blit_nt(d, s, aligned_row);
            uint8_t *rd = (uint8_t*)d + aligned_row;
            const uint8_t *rs = (const uint8_t*)s + aligned_row;
            for (size_t t = 0; t < (bytes_row - aligned_row); t++) rd[t] = rs[t];
        }
        __asm__ volatile("mrs %0, cntvct_el0" : "=r"(c1));
        uint64_t freq = vsync_get_freq();
        s_last_swap_us = (c1 > c0) ? (((c1 - c0) * 1000000ULL) / freq) : 820;
        if (s_last_swap_us == 0) s_last_swap_us = 1;
    } else {
        s_last_swap_us = 0;
    }

    // Route presentation through unified Graphics HAL (flushes to VirtIO-GPU if active)
    gfx_backend_present(x, y, w, h, 0);
}


uint32_t gfx_get_pixel(int x, int y) {
    if (!canvas.back_buffer || x < 0 || y < 0 || (uint32_t)x >= canvas.width || (uint32_t)y >= canvas.height) {
        return 0;
    }
    return canvas.back_buffer[y * canvas.pitch + x];
}

uint32_t* gfx_get_backbuffer(void) {
    return canvas.back_buffer;
}

uint32_t* gfx_get_frontbuffer(void) {
    return canvas.front_buffer;
}

uint32_t* gfx_get_backbuffer_ptr(int x, int y) {
    if (!canvas.back_buffer || x < 0 || y < 0 || (uint32_t)x >= canvas.width || (uint32_t)y >= canvas.height) {
        return NULL;
    }
    return canvas.back_buffer + y * canvas.pitch + x;
}

uint32_t gfx_get_canvas_pitch(void) {
    return canvas.pitch;
}

uint32_t gfx_get_canvas_width(void) {
    return canvas.width;
}

uint32_t gfx_get_canvas_height(void) {
    return canvas.height;
}

void gfx_set_zero_ram_mode(int enable) {
    if (enable) {
        // If front_buffer is in MMIO PCI aperture (< 0x40000000 on ARM virt),
        // random uncached read/writes trap hypervisor VM exits (~1M traps/frame).
        // Maintain back_buffer in RAM and use direct non-temporal streaming blit.
        if ((uintptr_t)canvas.front_buffer < 0x40000000ULL && canvas.front_buffer != NULL) {
            s_zero_ram_mode = 1;
            canvas.back_buffer = s_dedicated_backbuffer ? s_dedicated_backbuffer : canvas.front_buffer;
            printf("[GFX] Zero-RAM Direct-to-VRAM enabled via streaming staging (PCI aperture protected)\n");
            return;
        }
        s_zero_ram_mode = 1;
        canvas.back_buffer = canvas.front_buffer;
        printf("[GFX] Zero-RAM Direct-to-VRAM mode enabled! (3.14 MB RAM buffer eliminated, 0ms blit)\n");
    } else {
        s_zero_ram_mode = 0;
        canvas.back_buffer = s_dedicated_backbuffer ? s_dedicated_backbuffer : canvas.front_buffer;
        printf("[GFX] Double-buffering RAM backbuffer restored.\n");
    }
}

int gfx_is_zero_ram_mode(void) {
    return (canvas.back_buffer == canvas.front_buffer);
}


// DolDoc 2.0 Terminal Viewport & Grid Buffer
#define DOLDOC_GRID_COLS 96
#define DOLDOC_GRID_ROWS 32

typedef struct {
    char     c;
    uint32_t fg;
    uint32_t bg;
    char     link_cmd[32];
} doldoc_cell_t;

static doldoc_cell_t doc_grid[DOLDOC_GRID_ROWS][DOLDOC_GRID_COLS];
static int doc_grid_cols = 88;
static int doc_grid_rows = 24;
static int doc_cur_col = 0;
static int doc_cur_row = 0;
static char doc_active_link[32] = {0};

#define DOLDOC_HISTORY_LINES 1024
static doldoc_cell_t doc_history[DOLDOC_HISTORY_LINES][DOLDOC_GRID_COLS];
static int doc_history_count = 0;
static int doc_scroll_offset = 0;

extern void shell_run_command(const char *raw_cmd);

void doldoc_init(uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
    doc_term.x = x;
    doc_term.y = y;
    doc_term.w = w;
    doc_term.h = h;
    doc_term.cursor_x = x + 8;
    doc_term.cursor_y = y + 8;
    doc_term.text_color = COLOR_GREEN_TERMINAL;
    doc_term.bg_color = 0x00000000;

    doc_grid_cols = (w > 16) ? (w - 16) / 8 : 80;
    doc_grid_rows = (h > 16) ? (h - 16) / 18 : 24;
    if (doc_grid_cols > DOLDOC_GRID_COLS) doc_grid_cols = DOLDOC_GRID_COLS;
    if (doc_grid_rows > DOLDOC_GRID_ROWS) doc_grid_rows = DOLDOC_GRID_ROWS;

    doldoc_clear();
}

static uint64_t s_doc_dirty_mask = 0xFFFFFFFFFFFFFFFFULL;

void doldoc_mark_all_dirty(void) {
    s_doc_dirty_mask = 0xFFFFFFFFFFFFFFFFULL;
}

void doldoc_mark_row_dirty(int r) {
    if (r >= 0 && r < 64) s_doc_dirty_mask |= (1ULL << r);
}

void doldoc_clear(void) {
    memset(doc_grid, 0, sizeof(doc_grid));
    doc_cur_col = 0;
    doc_cur_row = 0;
    doc_scroll_offset = 0;
    doc_term.cursor_x = doc_term.x + 8;
    doc_term.cursor_y = doc_term.y + 8;
    doldoc_mark_all_dirty();
    gfx_draw_rect(doc_term.x, doc_term.y, doc_term.w, doc_term.h, 0xFF1B1E20);
    gfx_draw_rect(doc_term.x, doc_term.y, doc_term.w, 1, COLOR_BORDER_DARK);
}

void doldoc_redraw(void) {
    if (s_doc_dirty_mask == 0) return; // 0.0 ms if nothing changed!

    if (s_doc_dirty_mask == 0xFFFFFFFFFFFFFFFFULL) {
        gfx_draw_rect(doc_term.x, doc_term.y, doc_term.w, doc_term.h, 0xFF1B1E20);
        gfx_draw_rect(doc_term.x, doc_term.y, doc_term.w, 1, COLOR_BORDER_DARK);
    }

    if (doc_scroll_offset == 0) {
        for (int r = 0; r < doc_grid_rows; r++) {
            if (r < 64 && !(s_doc_dirty_mask & (1ULL << r))) continue;
            gfx_draw_rect(doc_term.x + 8, doc_term.y + 8 + r * 18, doc_term.w - 16, 18, 0xFF1B1E20);
            for (int c = 0; c < doc_grid_cols; c++) {
                doldoc_cell_t *cell = &doc_grid[r][c];
                if (cell->c >= 32 && cell->c <= 126) {
                    gfx_draw_char(doc_term.x + 8 + c * 8, doc_term.y + 8 + r * 18,
                                  cell->c, cell->fg, cell->bg);
                }
            }
        }
    } else {
        for (int r = 0; r < doc_grid_rows; r++) {
            int hist_idx = doc_history_count - doc_scroll_offset + r;
            doldoc_cell_t *row_cells = NULL;
            if (hist_idx >= 0 && hist_idx < doc_history_count) {
                row_cells = doc_history[hist_idx];
            } else if (hist_idx >= doc_history_count) {
                int grid_r = hist_idx - doc_history_count;
                if (grid_r < doc_grid_rows) row_cells = doc_grid[grid_r];
            }
            if (row_cells) {
                gfx_draw_rect(doc_term.x + 8, doc_term.y + 8 + r * 18, doc_term.w - 16, 18, 0xFF1B1E20);
                for (int c = 0; c < doc_grid_cols; c++) {
                    doldoc_cell_t *cell = &row_cells[c];
                    if (cell->c >= 32 && cell->c <= 126) {
                        gfx_draw_char(doc_term.x + 8 + c * 8, doc_term.y + 8 + r * 18,
                                      cell->c, cell->fg, cell->bg);
                    }
                }
            }
        }
    }

    // Scrollbar Track & Thumb
    uint32_t bar_x = doc_term.x + doc_term.w - 8;
    uint32_t bar_y = doc_term.y + 4;
    uint32_t bar_h = doc_term.h - 8;
    gfx_draw_rect(bar_x, bar_y, 4, bar_h, 0xFF14171A);

    int total_lines = doc_history_count + doc_grid_rows;
    if (total_lines > doc_grid_rows && doc_history_count > 0) {
        int thumb_h = (bar_h * doc_grid_rows) / total_lines;
        if (thumb_h < 14) thumb_h = 14;
        int scroll_pos = doc_history_count - doc_scroll_offset;
        if (scroll_pos < 0) scroll_pos = 0;
        int thumb_y = bar_y + ((bar_h - thumb_h) * scroll_pos) / doc_history_count;
        gfx_draw_rounded_rect(bar_x - 1, thumb_y, 6, thumb_h, 2, COLOR_ACCENT_CYAN);
    }
    s_doc_dirty_mask = 0;
}

void doldoc_scroll_up(int lines) {
    doc_scroll_offset += lines;
    if (doc_scroll_offset > doc_history_count) doc_scroll_offset = doc_history_count;
    doldoc_mark_all_dirty();
    doldoc_redraw();
}

void doldoc_scroll_down(int lines) {
    doc_scroll_offset -= lines;
    if (doc_scroll_offset < 0) doc_scroll_offset = 0;
    doldoc_mark_all_dirty();
    doldoc_redraw();
}

int doldoc_get_scroll_offset(void) {
    return doc_scroll_offset;
}

void doldoc_move(uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
    doc_term.x = x;
    doc_term.y = y;
    doc_term.w = w;
    doc_term.h = h;
    doc_grid_cols = (w > 16) ? (w - 16) / 8 : 80;
    doc_grid_rows = (h > 16) ? (h - 16) / 18 : 25;
    if (doc_grid_cols > DOLDOC_GRID_COLS) doc_grid_cols = DOLDOC_GRID_COLS;
    if (doc_grid_rows > DOLDOC_GRID_ROWS) doc_grid_rows = DOLDOC_GRID_ROWS;
    if (doc_cur_row >= doc_grid_rows) doc_cur_row = doc_grid_rows - 1;
    if (doc_cur_col >= doc_grid_cols) doc_cur_col = doc_grid_cols - 1;
    doc_term.cursor_x = doc_term.x + 8 + doc_cur_col * 8;
    doc_term.cursor_y = doc_term.y + 8 + doc_cur_row * 18;
    doldoc_mark_all_dirty();
    doldoc_redraw();
}

static void doldoc_scroll(void) {
    if (doc_grid_rows > 1) {
        if (doc_history_count < DOLDOC_HISTORY_LINES) {
            memcpy(&doc_history[doc_history_count++], &doc_grid[0], sizeof(doc_grid[0]));
        } else {
            memmove(&doc_history[0], &doc_history[1], sizeof(doc_grid[0]) * (DOLDOC_HISTORY_LINES - 1));
            memcpy(&doc_history[DOLDOC_HISTORY_LINES - 1], &doc_grid[0], sizeof(doc_grid[0]));
        }
        memmove(&doc_grid[0], &doc_grid[1], sizeof(doc_grid[0]) * (doc_grid_rows - 1));
        memset(&doc_grid[doc_grid_rows - 1], 0, sizeof(doc_grid[0]));
    }
    doc_cur_row = doc_grid_rows - 1;
    doc_term.cursor_x = doc_term.x + 8 + doc_cur_col * 8;
    doc_term.cursor_y = doc_term.y + 8 + doc_cur_row * 18;
    doldoc_mark_all_dirty();
    doldoc_redraw();
}

void doldoc_backspace(void) {
    if (doc_cur_col > 0) {
        doc_cur_col--;
        doc_grid[doc_cur_row][doc_cur_col].c = ' ';
        doc_grid[doc_cur_row][doc_cur_col].link_cmd[0] = '\0';
        doc_term.cursor_x = doc_term.x + 8 + doc_cur_col * 8;
        doldoc_mark_row_dirty(doc_cur_row);
        gfx_draw_rect(doc_term.cursor_x, doc_term.cursor_y, 8, 16, 0xFF1B1E20);
    }
}

void doldoc_draw_cursor(int visible) {
    uint32_t color = visible ? COLOR_ACCENT_CYAN : 0xFF1B1E20;
    gfx_draw_rect(doc_term.cursor_x, doc_term.cursor_y, 8, 16, color);
}

void doldoc_swap_cursor(void) {
    gfx_swap_rect(doc_term.cursor_x, doc_term.cursor_y, 8, 16);
}

void doldoc_swap_term(void) {
    gfx_swap_rect(doc_term.x, doc_term.y, doc_term.w, doc_term.h);
}

void doldoc_putc(char c) {
    if (c == '\n') {
        doc_cur_col = 0;
        doc_cur_row++;
        if (doc_cur_row >= doc_grid_rows) {
            doldoc_scroll();
        } else {
            doc_term.cursor_x = doc_term.x + 8;
            doc_term.cursor_y = doc_term.y + 8 + doc_cur_row * 18;
            doldoc_mark_row_dirty(doc_cur_row);
        }
    } else if (c == '\r') {
        doc_cur_col = 0;
        doc_term.cursor_x = doc_term.x + 8;
    } else if (c == '\b') {
        doldoc_backspace();
    } else if (c == '\t') {
        for (int i = 0; i < 4; i++) doldoc_putc(' ');
    } else {
        if (doc_cur_row < doc_grid_rows && doc_cur_col < doc_grid_cols) {
            doc_grid[doc_cur_row][doc_cur_col].c = c;
            doc_grid[doc_cur_row][doc_cur_col].fg = doc_term.text_color;
            doc_grid[doc_cur_row][doc_cur_col].bg = doc_term.bg_color;
            strncpy(doc_grid[doc_cur_row][doc_cur_col].link_cmd, doc_active_link, sizeof(doc_grid[0][0].link_cmd) - 1);

            doldoc_mark_row_dirty(doc_cur_row);
            gfx_draw_char(doc_term.x + 8 + doc_cur_col * 8, doc_term.y + 8 + doc_cur_row * 18,
                          c, doc_term.text_color, doc_term.bg_color);
            doc_cur_col++;
            if (doc_cur_col >= doc_grid_cols) {
                doc_cur_col = 0;
                doc_cur_row++;
                if (doc_cur_row >= doc_grid_rows) {
                    doldoc_scroll();
                }
            }
            doc_term.cursor_x = doc_term.x + 8 + doc_cur_col * 8;
            doc_term.cursor_y = doc_term.y + 8 + doc_cur_row * 18;
        }
    }
}

// Parses string between quotes: "..."
static const char* parse_quoted_string(const char *p, char *out, size_t max_out) {
    while (*p && *p != '\"') p++;
    if (!*p) return p;
    p++; // eat opening quote
    size_t idx = 0;
    while (*p && *p != '\"' && idx < max_out - 1) {
        out[idx++] = *p++;
    }
    out[idx] = '\0';
    if (*p == '\"') p++; // eat closing quote
    return p;
}

void doldoc_print(const char *str) {
    if (!str) return;

    while (*str) {
        if (*str == '$') {
            str++;
            if (*str == '$') {
                doldoc_putc('$');
                str++;
                continue;
            }

            // Parse DolDoc tag: $TAG...$
            char tag[256];
            size_t tlen = 0;
            while (*str && *str != '$' && tlen < sizeof(tag) - 1) {
                tag[tlen++] = *str++;
            }
            tag[tlen] = '\0';
            if (*str == '$') str++; // skip closing $

            // Tag 1: Color tags: $FG,RED$, $FG,GREEN$, $FG$, etc.
            if (strcmp(tag, "FG,RED") == 0) {
                doc_term.text_color = COLOR_BTN_CLOSE;
            } else if (strcmp(tag, "FG,GREEN") == 0) {
                doc_term.text_color = COLOR_GREEN_TERMINAL;
            } else if (strcmp(tag, "FG,BLUE") == 0) {
                doc_term.text_color = COLOR_ACCENT_BLUE;
            } else if (strcmp(tag, "FG,CYAN") == 0) {
                doc_term.text_color = COLOR_ACCENT_CYAN;
            } else if (strcmp(tag, "FG,YELLOW") == 0) {
                doc_term.text_color = COLOR_GOLD_ACCENT;
            } else if (strcmp(tag, "FG,WHITE") == 0) {
                doc_term.text_color = COLOR_TEXT_WHITE;
            } else if (strcmp(tag, "FG,MUTED") == 0) {
                doc_term.text_color = COLOR_TEXT_MUTED;
            } else if (strcmp(tag, "FG,DEFAULT") == 0 || strcmp(tag, "FG") == 0) {
                doc_term.text_color = COLOR_GREEN_TERMINAL;
            }
            // Tag 2: Hyperlinks: $LK,"Label",A="command"$
            else if (strncmp(tag, "LK,", 3) == 0) {
                char label[96] = {0};
                char cmd[64] = {0};
                const char *tp = tag + 3;
                tp = parse_quoted_string(tp, label, sizeof(label));
                const char *ap = strstr(tp, "A=");
                if (ap) {
                    parse_quoted_string(ap + 2, cmd, sizeof(cmd));
                }

                uint32_t old_fg = doc_term.text_color;
                doc_term.text_color = COLOR_ACCENT_CYAN;
                strncpy(doc_active_link, cmd, sizeof(doc_active_link) - 1);

                doldoc_putc('[');
                for (size_t i = 0; label[i]; i++) doldoc_putc(label[i]);
                doldoc_putc(']');

                doc_active_link[0] = '\0';
                doc_term.text_color = old_fg;
            }
            // Tag 3: Interactive Buttons: $BT,"Button",LM="command"$
            else if (strncmp(tag, "BT,", 3) == 0) {
                char label[48] = {0};
                char cmd[32] = {0};
                const char *tp = tag + 3;
                tp = parse_quoted_string(tp, label, sizeof(label));
                const char *lmp = strstr(tp, "LM=");
                if (lmp) {
                    parse_quoted_string(lmp + 3, cmd, sizeof(cmd));
                }

                uint32_t old_fg = doc_term.text_color;
                doc_term.text_color = COLOR_GOLD_ACCENT;
                strncpy(doc_active_link, cmd, sizeof(doc_active_link) - 1);

                doldoc_putc('<');
                doldoc_putc(' ');
                doc_term.text_color = COLOR_TEXT_WHITE;
                for (size_t i = 0; label[i]; i++) doldoc_putc(label[i]);
                doc_term.text_color = COLOR_GOLD_ACCENT;
                doldoc_putc(' ');
                doldoc_putc('>');

                doc_active_link[0] = '\0';
                doc_term.text_color = old_fg;
            }
            // Tag 4: Progress Bar: $PB,VAL=x,MAX=y$
            else if (strncmp(tag, "PB,", 3) == 0) {
                int val = 0;
                int max_val = 100;
                const char *vp = strstr(tag, "VAL=");
                if (vp) val = atoi(vp + 4);
                const char *mp = strstr(tag, "MAX=");
                if (mp) max_val = atoi(mp + 4);
                if (max_val <= 0) max_val = 100;
                if (val < 0) val = 0;
                if (val > max_val) val = max_val;

                int bar_width = 20;
                int filled = (val * bar_width) / max_val;
                uint32_t old_fg = doc_term.text_color;
                doc_term.text_color = COLOR_TEXT_MUTED;
                doldoc_putc('[');
                doc_term.text_color = COLOR_ACCENT_CYAN;
                for (int i = 0; i < filled; i++) doldoc_putc('=');
                if (filled < bar_width) {
                    doldoc_putc('>');
                    doc_term.text_color = COLOR_TEXT_MUTED;
                    for (int i = filled + 1; i < bar_width; i++) doldoc_putc('-');
                }
                doc_term.text_color = COLOR_TEXT_MUTED;
                doldoc_putc(']');
                doc_term.text_color = COLOR_GOLD_ACCENT;
                char pbuf[16];
                snprintf(pbuf, sizeof(pbuf), " %d%%", (val * 100) / max_val);
                for (size_t i = 0; pbuf[i]; i++) doldoc_putc(pbuf[i]);
                doc_term.text_color = old_fg;
            }
            // Tag 5: Collapsible Tree Tag: $TR,"Title"$
            else if (strncmp(tag, "TR,", 3) == 0) {
                char title[64] = {0};
                parse_quoted_string(tag + 3, title, sizeof(title));
                uint32_t old_fg = doc_term.text_color;
                doc_term.text_color = COLOR_ACCENT_CYAN;
                doldoc_putc('[');
                doc_term.text_color = COLOR_GOLD_ACCENT;
                doldoc_putc('+');
                doc_term.text_color = COLOR_ACCENT_CYAN;
                doldoc_putc(']');
                doldoc_putc(' ');
                doc_term.text_color = COLOR_TEXT_WHITE;
                for (size_t i = 0; title[i]; i++) doldoc_putc(title[i]);
                doc_term.text_color = old_fg;
            }
            // Tag 6: Reactive Lua Expression Tag: $LUA,"lua_code"$
            else if (strncmp(tag, "LUA,", 4) == 0) {
                char lcode[128] = {0};
                parse_quoted_string(tag + 4, lcode, sizeof(lcode));
                extern int64_t neo_lua_eval(const char *code);
                int64_t lres = neo_lua_eval(lcode);
                char lbuf[32];
                snprintf(lbuf, sizeof(lbuf), "%lld", (long long)lres);
                uint32_t old_fg = doc_term.text_color;
                doc_term.text_color = COLOR_GOLD_ACCENT;
                for (size_t i = 0; lbuf[i]; i++) doldoc_putc(lbuf[i]);
                doc_term.text_color = old_fg;
            }
            continue;
        }

        doldoc_putc(*str);
        str++;
    }
}

void doldoc_printf(const char *fmt, ...) {
    char buf[512];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    doldoc_print(buf);
}

int doldoc_handle_click(int mouse_x, int mouse_y) {
    if (mouse_x < (int)doc_term.x + 8 || mouse_y < (int)doc_term.y + 8) return 0;
    int col = (mouse_x - ((int)doc_term.x + 8)) / 8;
    int row = (mouse_y - ((int)doc_term.y + 8)) / 18;

    if (row >= 0 && row < doc_grid_rows && col >= 0 && col < doc_grid_cols) {
        if (doc_grid[row][col].link_cmd[0] != '\0') {
            char cmd_copy[32];
            strncpy(cmd_copy, doc_grid[row][col].link_cmd, sizeof(cmd_copy) - 1);
            cmd_copy[sizeof(cmd_copy) - 1] = '\0';
            doldoc_printf("\n$FG,YELLOW$[CLICK]$FG$ $FG,CYAN$%s$FG$\n", cmd_copy);
            shell_run_command(cmd_copy);
            return 1;
        }
    }
    return 0;
}
