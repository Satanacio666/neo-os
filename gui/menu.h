#ifndef NEO_MENU_H
#define NEO_MENU_H

#include <uefi.h>
#include "wm.h"

void menu_init(void);
void menu_open(void);
void menu_close(void);
void menu_toggle(void);
int  menu_is_open(void);
void menu_render(window_t *win, void *user_data);
int  menu_handle_click(window_t *win, int mouse_x, int mouse_y);

#endif // NEO_MENU_H
