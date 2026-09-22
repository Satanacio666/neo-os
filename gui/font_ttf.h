#ifndef NEO_FONT_TTF_H
#define NEO_FONT_TTF_H

#include <uefi.h>

extern const unsigned char g_ubuntu_mono_ttf[];
extern const unsigned int g_ubuntu_mono_ttf_len;

int  font_ttf_init(float pixel_height);
void font_ttf_draw_char(int x, int y, char c, uint32_t color);
void font_ttf_draw_string(int x, int y, const char *str, uint32_t color);
int  font_ttf_get_char_width(char c);
int  font_ttf_get_line_height(void);
int  font_ttf_is_ready(void);

#endif // NEO_FONT_TTF_H
