#ifndef NEO_WM_H
#define NEO_WM_H

#include <uefi.h>
#include "render.h"

#include "../drivers/input/mouse.h"

#define MAX_WINDOWS 8

struct window;
typedef void (*win_render_fn)(struct window *win, void *user_data);
typedef void (*win_update_fn)(struct window *win, void *user_data);
typedef int  (*win_click_fn)(struct window *win, int mouse_x, int mouse_y);

typedef struct window {
    uint32_t      id;
    char          title[64];
    int           x;
    int           y;
    int           width;
    int           height;
    int           is_active;
    int           is_minimized;
    int           is_maximized;
    int           saved_x;
    int           saved_y;
    int           saved_w;
    int           saved_h;
    win_render_fn custom_render;
    win_update_fn custom_update;
    win_click_fn  custom_click;
    void         *user_data;
} window_t;

void      wm_init(uint32_t screen_w, uint32_t screen_h);
window_t* wm_create_window(const char *title, int x, int y, int w, int h);
void      wm_destroy_window(uint32_t id);
void      wm_draw_desktop(void);
void      wm_draw_window(window_t *win);
void      wm_draw_all(void);
void      wm_draw_animating_windows(void);
int       wm_is_dirty(void);
void      wm_set_dirty(void);
void      wm_clear_dirty(void);
window_t* wm_get_active(void);
window_t* wm_get_window_by_id(uint32_t id);
int       wm_get_window_count(void);
void      wm_handle_mouse(mouse_state_t mouse);

#endif // NEO_WM_H
