#ifndef NEO_HOLYGL_H
#define NEO_HOLYGL_H

#include "math3d.h"
#include <uefi.h>

// ─── OpenGL 1.3 / 2.0 Constants ───────────────────────────────────────────────

#define GL_POINTS                         0x0000
#define GL_LINES                          0x0001
#define GL_LINE_LOOP                      0x0002
#define GL_LINE_STRIP                     0x0003
#define GL_TRIANGLES                      0x0004
#define GL_TRIANGLE_STRIP                 0x0005
#define GL_TRIANGLE_FAN                   0x0006
#define GL_QUADS                          0x0007
#define GL_QUAD_STRIP                     0x0008
#define GL_POLYGON                        0x0009

#define GL_MODELVIEW                      0x1700
#define GL_PROJECTION                     0x1701

#define GL_DEPTH_TEST                     0x0B71
#define GL_CULL_FACE                      0x0B44
#define GL_LIGHTING                       0x0B50

#define GL_COLOR_BUFFER_BIT               0x00004000
#define GL_DEPTH_BUFFER_BIT               0x00000100

#define HOLYGL_MAX_VERTICES               4096
#define HOLYGL_MODELVIEW_STACK_DEPTH      16
#define HOLYGL_PROJECTION_STACK_DEPTH     4

// ─── HolyGL Core State Structure ──────────────────────────────────────────────

typedef struct {
    float x, y, z, w;
    float nx, ny, nz;
    float u, v;
    uint32_t color;
} holygl_vertex_t;

typedef struct {
    uint32_t        matrix_mode;
    mat4_t          modelview_stack[HOLYGL_MODELVIEW_STACK_DEPTH];
    int             modelview_depth;
    mat4_t          projection_stack[HOLYGL_PROJECTION_STACK_DEPTH];
    int             projection_depth;

    mat4_t          mvp;
    int             mvp_dirty;

    int             depth_test;
    int             cull_face;
    int             lighting;

    uint32_t        current_color;
    vec3_t          current_normal;
    vec2_t          current_uv;

    int             in_begin;
    uint32_t        primitive_mode;
    holygl_vertex_t vertex_buffer[HOLYGL_MAX_VERTICES];
    int             vertex_count;

    int             vp_x, vp_y, vp_w, vp_h;
    zbuffer_t      *zbuffer;
    uint32_t       *target_buffer;
    uint32_t        pitch;
    int             scene_active;
} holygl_context_t;

extern holygl_context_t g_holygl;

// ─── OpenGL 1.3 / 2.0 API Prototypes ──────────────────────────────────────────

void holygl_init(void);
void holygl_set_target(int x, int y, int w, int h, zbuffer_t *zb, uint32_t *target, uint32_t pitch);

void glViewport(int x, int y, int width, int height);
void glMatrixMode(uint32_t mode);
void glLoadIdentity(void);
void glPushMatrix(void);
void glPopMatrix(void);
void glTranslatef(float x, float y, float z);
void glRotatef(float angle, float x, float y, float z);
void glScalef(float x, float y, float z);
void gluPerspective(float fovy, float aspect, float zNear, float zFar);

void glClear(uint32_t mask);
void glClearColor(float red, float green, float blue, float alpha);
void glEnable(uint32_t cap);
void glDisable(uint32_t cap);

void glColor4f(float red, float green, float blue, float alpha);
void glColor3f(float red, float green, float blue);
void glColor3ub(uint8_t r, uint8_t g, uint8_t b);
void glNormal3f(float nx, float ny, float nz);
void glTexCoord2f(float u, float v);

void glBegin(uint32_t mode);
void glVertex3f(float x, float y, float z);
void glVertex2f(float x, float y);
void glEnd(void);
void glFlush(void);

#endif // NEO_HOLYGL_H
