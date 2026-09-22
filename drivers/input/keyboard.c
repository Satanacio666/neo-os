#include "keyboard.h"
#include <uefi.h>

#define KEY_BUF_SIZE 256
static int key_buf[KEY_BUF_SIZE];
static volatile int buf_head = 0;
static volatile int buf_tail = 0;

// QEMU ARM64 PL011 UART0 Base Registers
#define PL011_UART_BASE 0x09000000ULL
#define PL011_UARTDR    ((volatile uint32_t*)(PL011_UART_BASE + 0x00))
#define PL011_UARTFR    ((volatile uint32_t*)(PL011_UART_BASE + 0x18))
#define PL011_FR_RXFE   (1U << 4) // Receive FIFO Empty

void uart_putc(char c) {
    *PL011_UARTDR = (uint32_t)c;
}

void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

static void queue_key(int k) {
    int next = (buf_head + 1) % KEY_BUF_SIZE;
    if (next != buf_tail) {
        key_buf[buf_head] = k;
        buf_head = next;
    }
}

void keyboard_init(void) {
    buf_head = 0;
    buf_tail = 0;
    printf("[KEYBOARD] Unified Keyboard Driver initialized (UEFI ConIn + PL011 UART)\n");
}

int keyboard_has_char(void) {
    keyboard_poll();
    return (buf_head != buf_tail);
}

int keyboard_getchar(void) {
    if (!keyboard_has_char()) {
        return 0;
    }
    int k = key_buf[buf_tail];
    buf_tail = (buf_tail + 1) % KEY_BUF_SIZE;
    return k;
}

static int uart_has_rx(void) {
    return (*PL011_UARTFR & PL011_FR_RXFE) == 0;
}

static uint8_t uart_getc(void) {
    return (uint8_t)(*PL011_UARTDR & 0xFF);
}

int keyboard_poll(void) {
    int count = 0;

    // 1. Poll UEFI Console Input
    if (ST && ST->ConIn) {
        efi_input_key_t key;
        while (ST->ConIn->ReadKeyStroke(ST->ConIn, &key) == EFI_SUCCESS) {
            count++;
            if (key.UnicodeChar != 0) {
                if (key.UnicodeChar == '\r') {
                    queue_key('\n');
                } else if (key.UnicodeChar == 8 || key.UnicodeChar == 127) {
                    queue_key(KEY_BACKSPACE);
                } else {
                    queue_key((int)key.UnicodeChar);
                }
            } else if (key.ScanCode != 0) {
                switch (key.ScanCode) {
                    case 1: queue_key(KEY_UP); break;
                    case 2: queue_key(KEY_DOWN); break;
                    case 3: queue_key(KEY_RIGHT); break;
                    case 4: queue_key(KEY_LEFT); break;
                    case 9: queue_key(KEY_PAGE_UP); break;
                    case 10: queue_key(KEY_PAGE_DOWN); break;
                    case 0x17: queue_key(KEY_ESC); break;
                    default: break;
                }
            }
        }
    }

    // 2. Poll PL011 UART Input
    while (uart_has_rx()) {
        count++;
        uint8_t c = uart_getc();
        if (c == 0x1B) {
            // Check for ANSI escape sequence
            if (uart_has_rx()) {
                uint8_t c2 = uart_getc();
                if (c2 == '[') {
                    if (uart_has_rx()) {
                        uint8_t c3 = uart_getc();
                        switch (c3) {
                            case 'A': queue_key(KEY_UP); continue;
                            case 'B': queue_key(KEY_DOWN); continue;
                            case 'C': queue_key(KEY_RIGHT); continue;
                            case 'D': queue_key(KEY_LEFT); continue;
                            default: break;
                        }
                    }
                }
            }
            queue_key(KEY_ESC);
        } else if (c == '\r' || c == '\n') {
            queue_key('\n');
        } else if (c == 8 || c == 127) {
            queue_key(KEY_BACKSPACE);
        } else {
            queue_key(c);
        }
    }

    return count;
}
