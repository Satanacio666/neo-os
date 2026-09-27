#ifndef NEO_WM_H
#define NEO_WM_H

#include <uefi.h>
#include "render.h"

#include "../drivers/input/mouse.h"

#define MAX_WINDOWS 8

typedef struct {
    int x, y, w, h;
    int active;
} damage_rect_t;

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
    int           marked_for_destruction;
    damage_rect_t damage;
    win_render_fn custom_render;
    win_update_fn custom_update;
    win_click_fn  custom_click;
    void         *user_data;
} window_t;

void          wm_init(uint32_t screen_w, uint32_t screen_h);
window_t*     wm_create_window(const char *title, int x, int y, int w, int h);
void          wm_destroy_window(uint32_t id);
void          wm_sweep_destroyed_windows(void);
void          wm_draw_desktop(void);
void          wm_draw_window(window_t *win);
void          wm_draw_all(void);
void          wm_draw_animating_windows(void);
void          wm_draw_tray_only(void);
void          wm_update_tray_clock(void);
int           wm_has_animating_windows(void);
int           wm_is_dirty(void);
void          wm_set_dirty(void);
void          wm_clear_dirty(void);
void          wm_damage_rect(int x, int y, int w, int h);
void          wm_damage_window(window_t *win);
void          wm_damage_client(window_t *win);
damage_rect_t wm_get_damage(void);
void          wm_clear_damage(void);
window_t*     wm_get_active(void);
window_t*     wm_get_window_by_id(uint32_t id);
void          wm_bring_to_front_by_id(uint32_t id);
int           wm_get_window_count(void);
void          wm_handle_mouse(mouse_state_t mouse);

typedef struct {
    uint32_t vsync_hz;
    int      shadows_enabled;
    int      glass_enabled;
    int      rounded_corners;
    int      dirty_rect_blit;
} compositor_config_t;

extern compositor_config_t g_compositor_cfg;

void compositor_config_open(void);
void compositor_config_close(void);
int  compositor_config_is_open(void);
void compositor_config_render(window_t *win, void *user_data);
int  compositor_config_click(window_t *win, int mouse_x, int mouse_y);
void compositor_config_print_doldoc(void);

void compositor_set_vsync(uint32_t hz);
uint32_t compositor_get_vsync(void);
void compositor_set_shadows(int enable);
int  compositor_get_shadows(void);
void compositor_set_glass(int enable);
int  compositor_get_glass(void);

#endif // NEO_WM_H
