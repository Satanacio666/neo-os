#ifndef NEO_APPS_GUI_H
#define NEO_APPS_GUI_H

#include "wm.h"

void filer_open(void);
void filer_close(void);
int  filer_is_open(void);
void filer_render(window_t *win, void *user_data);
int  filer_click(window_t *win, int mouse_x, int mouse_y);

void editor_open(const char *filename);
void editor_close(void);
int  editor_is_open(void);
void editor_render(window_t *win, void *user_data);
int  editor_click(window_t *win, int mouse_x, int mouse_y);

#endif // NEO_APPS_GUI_H
