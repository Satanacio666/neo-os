#ifndef NEO_RENDER_H
#define NEO_RENDER_H

#include <uefi.h>

// Color Palette (KDE Breeze Dark / DolDoc 2.0)
#define COLOR_BG_DARK           0xFF232629  // Dark gray background
#define COLOR_WINDOW_BODY       0xFF31363B  // Window surface
#define COLOR_ACCENT_CYAN       0xFF3DAEE9  // Active title / cyan highlight
#define COLOR_ACCENT_BLUE       0xFF1D99F3  // Blue accent
#define COLOR_PANEL_HEADER      0xFF2A2E32  // Header / taskbar
#define COLOR_TEXT_WHITE        0xFFFCFCFC  // White text
#define COLOR_TEXT_MUTED        0xFFBDC3C7  // Muted gray text
#define COLOR_BORDER_DARK       0xFF1B1E20  // Border dark
#define COLOR_BTN_CLOSE         0xFFDA4453  // Close button red
#define COLOR_BTN_MAX           0xFF27AE60  // Maximize button green
#define COLOR_BTN_MIN           0xFFF67400  // Minimize button orange
#define COLOR_GREEN_TERMINAL    0xFF2ECC71  // Bright terminal green
#define COLOR_GOLD_ACCENT       0xFFF1C40F  // Golden yellow
#define COLOR_EMERALD_GREEN     0xFF00E676  // Neon emerald
#define COLOR_MAGENTA           0xFFE056FD  // Neon magenta
#define COLOR_NEON_CYAN         0xFF00F0FF  // Electric cyan
#define COLOR_BRIGHT_GOLD       0xFFFFD700  // Bright gold

typedef struct {
    uint32_t *front_buffer; // Hardware VRAM (GOP)
    uint32_t *back_buffer;  // RAM working buffer
    uint32_t width;
    uint32_t height;
    uint32_t pitch;
    size_t   buffer_size_bytes;
} canvas_t;

void     gfx_init(uint32_t *vram_base, uint32_t w, uint32_t h, uint32_t pitch);
void     gfx_clear(uint32_t color);
void     gfx_set_clip(int x, int y, int w, int h);
void     gfx_reset_clip(void);
void     gfx_get_clip(int *x, int *y, int *w, int *h);
void     gfx_put_pixel(uint32_t x, uint32_t y, uint32_t color);
void     gfx_blend_pixel(uint32_t x, uint32_t y, uint32_t color_rgba);
void     gfx_draw_line(int x0, int y0, int x1, int y1, uint32_t color);
void     gfx_draw_line_clipped(int x0, int y0, int x1, int y1, uint32_t color);
void     gfx_draw_triangle_wire(int x0, int y0, int x1, int y1, int x2, int y2, uint32_t color);
void     gfx_draw_triangle_fill(int x0, int y0, int x1, int y1, int x2, int y2, uint32_t color);
void     gfx_fill_circle(int cx, int cy, int radius, uint32_t color);
void     gfx_draw_rect(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t color);
void     gfx_blend_rect(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t color_rgba);
void     gfx_draw_rounded_rect(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t radius, uint32_t color);
void     gfx_draw_shadow(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t spread);
void     gfx_draw_char(uint32_t x, uint32_t y, char c, uint32_t fg, uint32_t bg);
void     gfx_draw_string(uint32_t x, uint32_t y, const char *str, uint32_t fg, uint32_t bg);
void     gfx_swap_buffers(void);
void     gfx_swap_rect(int x, int y, int w, int h);
uint32_t gfx_get_pixel(int x, int y);
uint32_t* gfx_get_backbuffer(void);
uint32_t* gfx_get_frontbuffer(void);
uint32_t* gfx_get_backbuffer_ptr(int x, int y);
uint32_t gfx_get_canvas_pitch(void);
uint32_t gfx_get_canvas_width(void);
uint32_t gfx_get_canvas_height(void);
void     gfx_set_zero_ram_mode(int enable);
int      gfx_is_zero_ram_mode(void);

// VSync / Frame Pacing (cntvct_el0 based, no hardware dependency)
void     gfx_vsync_init(void);
void     gfx_vsync_set(int enable, uint32_t hz);  // hz: 0=default(60), or 30/60/120/144/240
int      gfx_vsync_get_enabled(void);
uint32_t gfx_vsync_get_hz(void);
void     gfx_vsync_wait(void);                    // call after gfx_swap_buffers

// Dirty Rect Tracking
void     gfx_dirty_reset(void);
void     gfx_dirty_all(void);
void     gfx_dirty_expand(int x, int y, int w, int h);
uint64_t gfx_get_last_swap_us(void);

// Draw cursor directly onto the frontbuffer (after blit) — no backbuffer pollution
void     gfx_draw_cursor_to_front(int x, int y, const uint8_t bitmap[16][16]);

// DolDoc 2.0 Console Stream & Interactive APIs
void     doldoc_init(uint32_t x, uint32_t y, uint32_t w, uint32_t h);
void     doldoc_move(uint32_t x, uint32_t y, uint32_t w, uint32_t h);
void     doldoc_redraw(void);
void     doldoc_clear(void);
void     doldoc_putc(char c);
void     doldoc_backspace(void);
void     doldoc_draw_cursor(int visible);
void     doldoc_swap_cursor(void);
void     doldoc_swap_term(void);
void     doldoc_print(const char *str);
void     doldoc_printf(const char *fmt, ...);
int      doldoc_handle_click(int mouse_x, int mouse_y);
void     doldoc_scroll_up(int lines);
void     doldoc_scroll_down(int lines);
int      doldoc_get_scroll_offset(void);

#endif // NEO_RENDER_H
