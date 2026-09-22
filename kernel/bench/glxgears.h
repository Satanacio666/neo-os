#ifndef NEO_GLXGEARS_H
#define NEO_GLXGEARS_H

#include <uefi.h>
#include "../../gui/wm.h"
#include "../math/gears3d.h"

typedef struct {
    int          active;
    uint32_t     win_id;
    uint32_t     win_b_id;
    int          is_dual;
    int          wireframe;
    int          smp_mode;
    
    // 3 Authentic Gears
    gear_mesh_t  gear1; // Red (20 teeth)
    gear_mesh_t  gear2; // Green (10 teeth)
    gear_mesh_t  gear3; // Blue (10 teeth)
    
    // Camera View Angles (Interactive via Mouse Drag)
    float        view_rotx;
    float        view_roty;
    float        view_rotz;
    float        gear_angle;
    
    // Mouse Drag State
    int          dragging;
    int          last_mouse_x;
    int          last_mouse_y;
    
    // Software Z-Buffers
    zbuffer_t    zbuffer;
    zbuffer_t    zbuffer_b;
    
    // 100% REAL Empirical Hardware Timer FPS Telemetry
    uint64_t     total_frames;
    uint64_t     period_frames;
    uint64_t     period_start_ticks;
    float        measured_fps;
    uint64_t     frame_time_us;
    char         fps_report[128];
} glxgears_state_t;

extern glxgears_state_t g_glxgears;

void glxgears_init(void);
int  glxgears_start(int wireframe, int smp_mode, int dual_mode);
void glxgears_stop(void);
int  glxgears_is_active(void);
void glxgears_render_viewport(window_t *win, void *user_data);

#endif // NEO_GLXGEARS_H
