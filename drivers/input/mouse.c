#include "mouse.h"
#include "../../gui/render.h"
#include <uefi.h>

// ─── EFI Protocol GUIDs ───────────────────────────────────────────────────────

static efi_guid_t simple_pointer_guid = EFI_SIMPLE_POINTER_PROTOCOL_GUID;

static efi_guid_t abs_pointer_guid = {
    0x8d59c32b, 0xc655, 0x4ae9, { 0x9b, 0x15, 0xf2, 0x59, 0x04, 0x99, 0x2a, 0x43 }
};

// ─── Absolute Pointer Protocol ────────────────────────────────────────────────

typedef struct {
    uint64_t CurrentX;
    uint64_t CurrentY;
    uint64_t CurrentZ;
    uint32_t ActiveButtons;
} efi_absolute_pointer_state_t;

typedef struct {
    uint64_t AbsoluteMinX;
    uint64_t AbsoluteMinY;
    uint64_t AbsoluteMinZ;
    uint64_t AbsoluteMaxX;
    uint64_t AbsoluteMaxY;
    uint64_t AbsoluteMaxZ;
    uint32_t Attributes;
} efi_absolute_pointer_mode_t;

typedef struct _efi_absolute_pointer_protocol {
    efi_status_t (EFIAPI *Reset)(struct _efi_absolute_pointer_protocol *This, boolean_t ExtendedVerification);
    efi_status_t (EFIAPI *GetState)(struct _efi_absolute_pointer_protocol *This, efi_absolute_pointer_state_t *State);
    efi_event_t  WaitForInput;
    efi_absolute_pointer_mode_t *Mode;
} efi_absolute_pointer_protocol_t;

// ─── Protocol Instances ───────────────────────────────────────────────────────

static efi_simple_pointer_protocol_t   *pointer_proto    = NULL;
static efi_absolute_pointer_protocol_t *abs_pointer_proto = NULL;

// Exported event handle — callers (main loop) use this with WaitForEvent
static efi_event_t s_mouse_wait_event = NULL;

static mouse_state_t g_mouse = {0};
static int screen_w = 1280;
static int screen_h = 720;

// ─── Save-Under Cursor State ──────────────────────────────────────────────────
// Back-buffer save (for drawing into backbuffer before blit)
static uint32_t s_cursor_save_under[16][16];
static int      s_cursor_saved_x  = -1;
static int      s_cursor_saved_y  = -1;
static int      s_cursor_is_drawn = 0;

// Front-buffer save (for drawing cursor AFTER blit, directly on VRAM)
static uint32_t s_front_save_under[16][16];
static int      s_front_saved_x  = -1;
static int      s_front_saved_y  = -1;
static int      s_front_is_drawn = 0;

// ─── 16×16 Cursor Bitmap ─────────────────────────────────────────────────────
// 0 = transparent, 1 = black outline, 2 = white fill
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

// ─── Init ─────────────────────────────────────────────────────────────────────

void mouse_init(int max_width, int max_height) {
    screen_w = max_width;
    screen_h = max_height;
    g_mouse.x = screen_w / 2;
    g_mouse.y = screen_h / 2;
    g_mouse.visible = 1;
    g_mouse.left_button = g_mouse.right_button = 0;
    s_cursor_is_drawn = s_front_is_drawn = 0;
    s_mouse_wait_event = NULL;

    uintn_t n_handles = 0;
    efi_handle_t *handles = NULL;

    // 1. Try Absolute Pointer Protocol via LocateHandleBuffer
    //    LocateProtocol() only returns globally-registered instances.
    //    QEMU USB tablet registers on a device-specific handle — must enumerate.
    if (!EFI_ERROR(BS->LocateHandleBuffer(ByProtocol, &abs_pointer_guid, NULL, &n_handles, &handles)) && n_handles > 0) {
        for (uintn_t i = 0; i < n_handles; i++) {
            efi_absolute_pointer_protocol_t *p = NULL;
            if (!EFI_ERROR(BS->HandleProtocol(handles[i], &abs_pointer_guid, (void**)&p)) && p) {
                abs_pointer_proto = p;
                abs_pointer_proto->Reset(abs_pointer_proto, 0);
                // Save WaitForInput event for use in WaitForEvent (zero-lag wakeup)
                if (!s_mouse_wait_event) s_mouse_wait_event = abs_pointer_proto->WaitForInput;
                printf("[MOUSE] AbsolutePointer (USB tablet) found on handle[%u]\n", (unsigned)i);
                break;
            }
        }
        BS->FreePool(handles);
    }
    if (!abs_pointer_proto)
        printf("[MOUSE] AbsolutePointer not found — trying SimplePointer\n");

    // 2. Try Simple Pointer Protocol (relative mouse)
    n_handles = 0; handles = NULL;
    if (!EFI_ERROR(BS->LocateHandleBuffer(ByProtocol, &simple_pointer_guid, NULL, &n_handles, &handles)) && n_handles > 0) {
        for (uintn_t i = 0; i < n_handles; i++) {
            efi_simple_pointer_protocol_t *p = NULL;
            if (!EFI_ERROR(BS->HandleProtocol(handles[i], &simple_pointer_guid, (void**)&p)) && p) {
                pointer_proto = p;
                pointer_proto->Reset(pointer_proto, 0);
                if (!s_mouse_wait_event) s_mouse_wait_event = pointer_proto->WaitForInput;
                printf("[MOUSE] SimplePointer found on handle[%u]\n", (unsigned)i);
                break;
            }
        }
        BS->FreePool(handles);
    }

    if (!abs_pointer_proto && !pointer_proto)
        printf("[MOUSE] WARNING: No pointer protocol found — mouse disabled\n");

    printf("[MOUSE] Cursor @ (%d, %d), WaitEvent: %p\n",
           g_mouse.x, g_mouse.y, (void*)s_mouse_wait_event);
}

// ─── WaitForEvent handle (for main loop zero-lag idle) ────────────────────────
efi_event_t mouse_get_wait_event(void) {
    return s_mouse_wait_event;
}

// ─── Position Clamping ────────────────────────────────────────────────────────
void mouse_set_pos(int x, int y) {
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x >= screen_w) x = screen_w - 1;
    if (y >= screen_h) y = screen_h - 1;

    if (g_mouse.x != x || g_mouse.y != y) {
        if (s_front_is_drawn) {
            mouse_erase_cursor_front();
        }
        g_mouse.x = x;
        g_mouse.y = y;
        mouse_draw_cursor_front();
    }
}

// ─── Poll ────────────────────────────────────────────────────────────────────
void mouse_poll(void) {
    // 1. Absolute Pointer (USB tablet — QEMU -device usb-tablet)
    if (abs_pointer_proto) {
        efi_absolute_pointer_state_t state;
        if (abs_pointer_proto->GetState(abs_pointer_proto, &state) == EFI_SUCCESS) {
            if (abs_pointer_proto->Mode &&
                abs_pointer_proto->Mode->AbsoluteMaxX > abs_pointer_proto->Mode->AbsoluteMinX &&
                abs_pointer_proto->Mode->AbsoluteMaxY > abs_pointer_proto->Mode->AbsoluteMinY) {

                uint64_t range_x = abs_pointer_proto->Mode->AbsoluteMaxX - abs_pointer_proto->Mode->AbsoluteMinX;
                uint64_t range_y = abs_pointer_proto->Mode->AbsoluteMaxY - abs_pointer_proto->Mode->AbsoluteMinY;
                int new_x = (int)(((state.CurrentX - abs_pointer_proto->Mode->AbsoluteMinX) * (uint64_t)screen_w) / range_x);
                int new_y = (int)(((state.CurrentY - abs_pointer_proto->Mode->AbsoluteMinY) * (uint64_t)screen_h) / range_y);
                mouse_set_pos(new_x, new_y);
            }
            g_mouse.left_button  = (state.ActiveButtons & 1) ? 1 : 0;
            g_mouse.right_button = (state.ActiveButtons & 2) ? 1 : 0;
            return;
        }
    }

    // 2. Simple Pointer (relative mouse)
    if (pointer_proto) {
        efi_simple_pointer_state_t state;
        if (pointer_proto->GetState(pointer_proto, &state) == EFI_SUCCESS) {
            if (state.RelativeMovementX != 0 || state.RelativeMovementY != 0) {
                int dx = state.RelativeMovementX / 128;
                int dy = state.RelativeMovementY / 128;
                if (dx == 0 && state.RelativeMovementX != 0) dx = (state.RelativeMovementX > 0) ? 1 : -1;
                if (dy == 0 && state.RelativeMovementY != 0) dy = (state.RelativeMovementY > 0) ? 1 : -1;
                mouse_set_pos(g_mouse.x + dx, g_mouse.y + dy);
            }
            g_mouse.left_button  = state.LeftButton  ? 1 : 0;
            g_mouse.right_button = state.RightButton ? 1 : 0;
        }
    }
}

void mouse_set_button(int left, int right) {
    g_mouse.left_button  = left  ? 1 : 0;
    g_mouse.right_button = right ? 1 : 0;
}

mouse_state_t mouse_get_state(void) { return g_mouse; }

// ─── Backbuffer Cursor (used when in double-buffer mode pre-blit) ─────────────

void mouse_erase_cursor(void) {
    if (!s_cursor_is_drawn) return;
    for (int r = 0; r < 16; r++) {
        for (int c = 0; c < 16; c++) {
            if (!cursor_bitmap[r][c]) continue;
            int px = s_cursor_saved_x + c;
            int py = s_cursor_saved_y + r;
            if (px < 0 || px >= screen_w || py < 0 || py >= screen_h) continue;
            gfx_put_pixel((uint32_t)px, (uint32_t)py, s_cursor_save_under[r][c]);
        }
    }
    s_cursor_is_drawn = 0;
}

void mouse_draw_cursor(void) {
    if (!g_mouse.visible) return;
    if (s_cursor_is_drawn) mouse_erase_cursor();

    // Save background
    for (int r = 0; r < 16; r++) {
        for (int c = 0; c < 16; c++) {
            int px = g_mouse.x + c, py = g_mouse.y + r;
            s_cursor_save_under[r][c] = (px >= 0 && px < screen_w && py >= 0 && py < screen_h)
                ? gfx_get_pixel(px, py) : 0;
        }
    }
    s_cursor_saved_x = g_mouse.x;
    s_cursor_saved_y = g_mouse.y;
    s_cursor_is_drawn = 1;

    // Draw cursor into backbuffer
    for (int r = 0; r < 16; r++) {
        for (int c = 0; c < 16; c++) {
            uint8_t p = cursor_bitmap[r][c];
            if (!p) continue;
            int px = g_mouse.x + c, py = g_mouse.y + r;
            if (px < 0 || px >= screen_w || py < 0 || py >= screen_h) continue;
            gfx_put_pixel((uint32_t)px, (uint32_t)py, (p == 1) ? 0xFF1B1E20 : 0xFFFCFCFC);
        }
    }
}

// ─── Frontbuffer Cursor (PREFERRED: draw AFTER blit, directly on VRAM) ────────
// This approach keeps the backbuffer clean — no ghost cursor artifacts.

void mouse_erase_cursor_front(void) {
    if (!s_front_is_drawn) return;
    uint32_t *front = gfx_get_frontbuffer();
    uint32_t pitch  = gfx_get_canvas_pitch();
    if (!front) return;

    for (int r = 0; r < 16; r++) {
        for (int c = 0; c < 16; c++) {
            if (!cursor_bitmap[r][c]) continue;
            int px = s_front_saved_x + c;
            int py = s_front_saved_y + r;
            if (px < 0 || px >= screen_w || py < 0 || py >= screen_h) continue;
            front[py * pitch + px] = s_front_save_under[r][c];
        }
    }
    s_front_is_drawn = 0;
}

void mouse_draw_cursor_front(void) {
    if (!g_mouse.visible) return;
    uint32_t *front = gfx_get_frontbuffer();
    uint32_t pitch  = gfx_get_canvas_pitch();
    if (!front) { mouse_draw_cursor(); return; } // fallback to backbuffer

    if (s_front_is_drawn) mouse_erase_cursor_front();

    // Save frontbuffer pixels under cursor
    for (int r = 0; r < 16; r++) {
        for (int c = 0; c < 16; c++) {
            int px = g_mouse.x + c, py = g_mouse.y + r;
            s_front_save_under[r][c] = (px >= 0 && px < screen_w && py >= 0 && py < screen_h)
                ? front[py * pitch + px] : 0;
        }
    }
    s_front_saved_x = g_mouse.x;
    s_front_saved_y = g_mouse.y;
    s_front_is_drawn = 1;

    // Draw cursor directly onto frontbuffer (VRAM)
    for (int r = 0; r < 16; r++) {
        for (int c = 0; c < 16; c++) {
            uint8_t p = cursor_bitmap[r][c];
            if (!p) continue;
            int px = g_mouse.x + c, py = g_mouse.y + r;
            if (px < 0 || px >= screen_w || py < 0 || py >= screen_h) continue;
            front[py * pitch + px] = (p == 1) ? 0xFF1B1E20 : 0xFFFCFCFC;
        }
    }
}
