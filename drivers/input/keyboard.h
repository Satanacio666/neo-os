#ifndef KEYBOARD_H
#define KEYBOARD_H

#include <uefi.h>

#define KEY_UP        0x101
#define KEY_DOWN      0x102
#define KEY_RIGHT     0x103
#define KEY_LEFT      0x104
#define KEY_PAGE_UP   0x105
#define KEY_PAGE_DOWN 0x106
#define KEY_ESC       0x1B
#define KEY_BACKSPACE '\b'
#define KEY_ENTER     '\n'

void keyboard_init(void);
int keyboard_poll(void);
int keyboard_has_char(void);
int keyboard_getchar(void);
void uart_putc(char c);
void uart_puts(const char *s);

#endif // KEYBOARD_H
