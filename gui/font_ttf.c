#include "font_ttf.h"
#include "render.h"
#include "../kernel/mem/kheap.h"

// Hardware-accelerated and bare-metal math functions for stb_truetype
static inline float neo_fabs(float x) {
    float res;
    asm("fabs %s0, %s1" : "=w"(res) : "w"(x));
    return res;
}

static inline float neo_sqrt(float x) {
    if (x <= 0.0f) return 0.0f;
    float res;
    asm("fsqrt %s0, %s1" : "=w"(res) : "w"(x));
    return res;
}

static inline float neo_fmod(float x, float y) {
    if (y == 0.0f) return 0.0f;
    int n = (int)(x / y);
    return x - (float)n * y;
}

static inline float neo_pow(float x, float y) {
    (void)y;
    if (x == 0.0f) return 0.0f;
    if (x < 0.0f) return -neo_pow(-x, y);
    float guess = x;
    if (guess > 1.0f) guess = x / 2.0f;
    for (int i = 0; i < 8; i++) {
        guess = (2.0f * guess + x / (guess * guess)) / 3.0f;
    }
    return guess;
}

static inline float neo_cos(float x) {
    const float PI = 3.1415926535f;
    while (x > PI) x -= 2.0f * PI;
    while (x < -PI) x += 2.0f * PI;
    float x2 = x * x;
    return 1.0f - x2 / 2.0f + (x2 * x2) / 24.0f - (x2 * x2 * x2) / 720.0f;
}

static inline float neo_acos(float x) {
    if (x < -1.0f) x = -1.0f;
    if (x > 1.0f) x = 1.0f;
    const float PI = 3.1415926535f;
    float negate = (x < 0.0f) ? 1.0f : 0.0f;
    x = neo_fabs(x);
    float ret = -0.0187293f;
    ret = ret * x + 0.0742610f;
    ret = ret * x - 0.2121144f;
    ret = ret * x + 1.5707288f;
    ret = ret * neo_sqrt(1.0f - x);
    ret = ret - 2.0f * negate * ret;
    return negate * PI + ret;
}

static inline int neo_ifloor(float x) {
    int i = (int)x;
    return (x < (float)i) ? (i - 1) : i;
}

static inline int neo_iceil(float x) {
    int i = (int)x;
    return (x > (float)i) ? (i + 1) : i;
}

double floor(double x) {
    double res;
    asm("frintm %d0, %d1" : "=w"(res) : "w"(x));
    return res;
}

double ceil(double x) {
    double res;
    asm("frintp %d0, %d1" : "=w"(res) : "w"(x));
    return res;
}

float floorf(float x) {
    float res;
    asm("frintm %s0, %s1" : "=w"(res) : "w"(x));
    return res;
}

float ceilf(float x) {
    float res;
    asm("frintp %s0, %s1" : "=w"(res) : "w"(x));
    return res;
}

#define STBTT_ifloor(x)    neo_ifloor(x)
#define STBTT_iceil(x)     neo_iceil(x)
#define STBTT_malloc(x,u)  ((void)(u), kmalloc(x))
#define STBTT_free(x,u)    ((void)(u), kfree(x))
#define STBTT_assert(x)    ((void)0)
#define STBTT_strlen(x)    strlen(x)
#define STBTT_memcpy       memcpy
#define STBTT_memset       memset
#define STBTT_fabs         neo_fabs
#define STBTT_sqrt         neo_sqrt
#define STBTT_fmod         neo_fmod
#define STBTT_cos          neo_cos
#define STBTT_acos         neo_acos
#define STBTT_pow          neo_pow

#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

#define FONT_ATLAS_W 512
#define FONT_ATLAS_H 512

static uint8_t *g_font_atlas = NULL;
static stbtt_bakedchar g_cdata[96]; // ASCII 32..126
static int g_ttf_ready = 0;
static int g_line_height = 18;
static int g_char_width = 9;

int font_ttf_init(float pixel_height) {
    if (pixel_height <= 0.0f) pixel_height = 16.0f;
    g_line_height = (int)(pixel_height * 1.15f);
    g_char_width = (int)(pixel_height * 0.55f);

    if (!g_font_atlas) {
        g_font_atlas = (uint8_t*)kmalloc(FONT_ATLAS_W * FONT_ATLAS_H);
        if (!g_font_atlas) return -1;
    }
    memset(g_font_atlas, 0, FONT_ATLAS_W * FONT_ATLAS_H);

    int res = stbtt_BakeFontBitmap(g_ubuntu_mono_ttf, 0, pixel_height,
                                   g_font_atlas, FONT_ATLAS_W, FONT_ATLAS_H,
                                   32, 96, g_cdata);
    if (res > 0) {
        g_ttf_ready = 1;
        printf("[FONT] Antialiased TrueType rasterizer ready (Ubuntu Mono %d px, atlas %dx%d)\n",
               (int)pixel_height, FONT_ATLAS_W, FONT_ATLAS_H);
        return 0;
    }
    return -1;
}

int font_ttf_is_ready(void) {
    return g_ttf_ready;
}

int font_ttf_get_char_width(char c) {
    (void)c;
    return g_char_width;
}

int font_ttf_get_line_height(void) {
    return g_line_height;
}

void font_ttf_draw_char(int x, int y, char c, uint32_t color) {
    if (!g_ttf_ready || (unsigned char)c < 32 || (unsigned char)c >= 128) return;

    stbtt_aligned_quad q;
    float fx = (float)x;
    float fy = (float)(y + 13); // Align to 16px font baseline
    stbtt_GetBakedQuad(g_cdata, FONT_ATLAS_W, FONT_ATLAS_H, (unsigned char)c - 32, &fx, &fy, &q, 1);

    int x0 = (int)q.x0;
    int y0 = (int)q.y0;
    int x1 = (int)q.x1;
    int y1 = (int)q.y1;
    int bw = x1 - x0;
    int bh = y1 - y0;
    if (bw <= 0 || bh <= 0 || bw > 64 || bh > 64) return;

    int s0 = (int)(q.s0 * FONT_ATLAS_W + 0.5f);
    int t0 = (int)(q.t0 * FONT_ATLAS_H + 0.5f);

    for (int r = 0; r < bh; r++) {
        int py = y0 + r;
        int ay = t0 + r;
        if (ay < 0 || ay >= FONT_ATLAS_H) continue;

        for (int col = 0; col < bw; col++) {
            int px = x0 + col;
            int ax = s0 + col;
            if (ax < 0 || ax >= FONT_ATLAS_W) continue;

            uint8_t alpha = g_font_atlas[ay * FONT_ATLAS_W + ax];
            if (alpha > 0) {
                uint32_t alpha_color = ((uint32_t)alpha << 24) | (color & 0x00FFFFFF);
                gfx_blend_pixel(px, py, alpha_color);
            }
        }
    }
}

void font_ttf_draw_string(int x, int y, const char *str, uint32_t color) {
    if (!str || !g_ttf_ready) return;

    int cur_x = x;
    int cur_y = y;

    while (*str) {
        if (*str == '\n') {
            cur_x = x;
            cur_y += g_line_height;
        } else if ((unsigned char)*str >= 32 && (unsigned char)*str < 128) {
            font_ttf_draw_char(cur_x, cur_y, *str, color);
            cur_x += g_char_width;
        }
        str++;
    }
}
