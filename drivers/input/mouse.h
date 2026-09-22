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

void mouse_init(int max_width, int max_height);
void mouse_poll(void);
mouse_state_t mouse_get_state(void);
void mouse_draw_cursor(void);
void mouse_set_pos(int x, int y);
void mouse_set_button(int left, int right);

#endif // MOUSE_H
