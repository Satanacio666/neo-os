#include "mouse.h"
#include "../../gui/render.h"
#include <uefi.h>

static efi_guid_t simple_pointer_guid = EFI_SIMPLE_POINTER_PROTOCOL_GUID;
static efi_simple_pointer_protocol_t *pointer_proto = NULL;
static mouse_state_t g_mouse = {0};
static int screen_w = 1024;
static int screen_h = 768;

void mouse_init(int max_width, int max_height) {
    screen_w = max_width;
    screen_h = max_height;
    g_mouse.x = screen_w / 2;
    g_mouse.y = screen_h / 2;
    g_mouse.visible = 1;
    g_mouse.left_button = 0;
    g_mouse.right_button = 0;
    pointer_proto = NULL;
    printf("[MOUSE] Pointer subsystem initialized (Software cursor @ %d, %d)\n", g_mouse.x, g_mouse.y);
}

void mouse_poll(void) {
    // Software mouse state maintained; hardware updates handled via events or API
}

void mouse_set_pos(int x, int y) {
    g_mouse.x = x;
    g_mouse.y = y;
    if (g_mouse.x < 0) g_mouse.x = 0;
    if (g_mouse.y < 0) g_mouse.y = 0;
    if (g_mouse.x >= screen_w) g_mouse.x = screen_w - 1;
    if (g_mouse.y >= screen_h) g_mouse.y = screen_h - 1;
}

void mouse_set_button(int left, int right) {
    g_mouse.left_button = left ? 1 : 0;
    g_mouse.right_button = right ? 1 : 0;
}

mouse_state_t mouse_get_state(void) {
    return g_mouse;
}

// 16x16 Cursor Bitmap (0 = transparent, 1 = black border, 2 = white fill)
static const uint8_t cursor_bitmap[16][16] = {
    {1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 2, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 2, 2, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 2, 2, 2, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 2, 2, 2, 2, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 2, 2, 2, 2, 2, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0},
    {1, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0},
    {1, 2, 1, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 1, 0, 1, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    {1, 0, 0, 0, 1, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0},
    {0, 0, 0, 0, 0, 1, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0},
    {0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0},
    {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
};

void mouse_draw_cursor(void) {
    if (!g_mouse.visible) return;

    for (int r = 0; r < 16; r++) {
        for (int c = 0; c < 16; c++) {
            uint8_t pixel = cursor_bitmap[r][c];
            if (pixel == 0) continue;

            int px = g_mouse.x + c;
            int py = g_mouse.y + r;

            if (px < 0 || px >= screen_w || py < 0 || py >= screen_h) continue;

            uint32_t color = 0;
            if (pixel == 1) {
                color = 0xFF1B1E20; // Dark border
            } else if (pixel == 2) {
                color = 0xFFFCFCFC; // Bright white interior
            }

            gfx_put_pixel(px, py, color);
        }
    }
}
