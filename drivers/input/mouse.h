#ifndef MOUSE_H
#define MOUSE_H

#include <uefi.h>

typedef struct {
    int x;
    int y;
    int left_button;
    int right_button;
    int visible;
} mouse_state_t;

void          mouse_init(int max_width, int max_height);
void          mouse_poll(void);
void          mouse_set_pos(int x, int y);
void          mouse_set_button(int left, int right);
mouse_state_t mouse_get_state(void);

// Backbuffer cursor (legacy — still used in zero-copy mode back==front)
void          mouse_draw_cursor(void);
void          mouse_erase_cursor(void);

// Frontbuffer cursor (preferred — draw AFTER blit, direct VRAM write, no backbuffer pollution)
void          mouse_draw_cursor_front(void);
void          mouse_erase_cursor_front(void);

// Returns the WaitForInput EFI event from the active pointer protocol.
// Use with BS->WaitForEvent() in idle loop for zero-lag mouse wakeup.
efi_event_t   mouse_get_wait_event(void);

#endif // MOUSE_H
