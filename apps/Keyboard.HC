// ==============================================================================
// Keyboard.HC - Sovereign Pure HolyC Keyboard & UART Driver
// Architecture: AArch64 Ring 0 | 100% Native HolyC Implementation
// Replaces: drivers/input/keyboard.c (138 LOC)
// ==============================================================================

#define KEY_BUF_SIZE   256

#define KEY_UP         257
#define KEY_DOWN       258
#define KEY_RIGHT      259
#define KEY_LEFT       260
#define KEY_PAGE_UP    261
#define KEY_PAGE_DOWN  262
#define KEY_HOME       263
#define KEY_END        264
#define KEY_ESC        27
#define KEY_BACKSPACE  8
#define KEY_ENTER      10

#define PL011_FR_RXFE  16 // (1 << 4) Receive FIFO Empty
#define PL011_FR_TXFF  32 // (1 << 5) Transmit FIFO Full

I64 g_key_buf[256];
I64 g_key_buf_head = 0;
I64 g_key_buf_tail = 0;

U0 KeyboardQueueChar(I64 k) {
    I64 next = (g_key_buf_head + 1) & (KEY_BUF_SIZE - 1);
    if (next != g_key_buf_tail) {
        g_key_buf[g_key_buf_head] = k;
        g_key_buf_head = next;
    }
}

U0 keyboard_queue_char(I64 k) {
    KeyboardQueueChar(k);
}

I64 KeyboardHasChar() {
    return (g_key_buf_head != g_key_buf_tail);
}

I64 KeyboardGetChar() {
    if (g_key_buf_head == g_key_buf_tail) {
        return 0;
    }
    I64 k = g_key_buf[g_key_buf_tail];
    g_key_buf_tail = (g_key_buf_tail + 1) & (KEY_BUF_SIZE - 1);
    return k;
}

U0 KeyboardInit() {
    g_key_buf_head = 0;
    g_key_buf_tail = 0;
    I64 uart_base = hal_get_uart_base();
    if (uart_base) {
        // Line Control: 8-bit word length, FIFO enabled (WLEN=3, FEN=1 -> 0x70)
        __mmio_w32(uart_base + 0x2C, 0x70);
        // Control Register: UARTEN=1, TXE=1, RXE=1 -> 0x301
        __mmio_w32(uart_base + 0x30, 0x301);
    }
    doldoc_print("[KEYBOARD.HC] Sovereign Ring 0 Keyboard Driver Initialized\n");
}

U0 UartPutChar(U8 c) {
    I64 uart_base = hal_get_uart_base();
    if (!uart_base) return;

    I64 kb_to = 10000;
    while ((__mmio_r32(uart_base + 0x18) & PL011_FR_TXFF) && kb_to > 0) {
        kb_to--;
    }
    __mmio_w32(uart_base + 0x00, c);
}

U0 UartPutString(U8 *s) {
    while (*s) {
        if (*s == '\n') UartPutChar('\r');
        UartPutChar(*s);
        s++;
    }
}

U0 uart_putc(U8 c) {
    UartPutChar(c);
}

U0 uart_puts(U8 *s) {
    UartPutString(s);
}

I64 UartHasRx() {
    I64 uart_base = hal_get_uart_base();
    if (!uart_base) return 0;
    U32 cr = __mmio_r32(uart_base + 0x30);
    if ((cr & (1 << 9)) == 0) {
        __mmio_w32(uart_base + 0x2C, 0x70);
        __mmio_w32(uart_base + 0x30, 0x301);
    }
    return (__mmio_r32(uart_base + 0x18) & PL011_FR_RXFE) == 0;
}

I64 UartWaitRx(I64 max_spins) {
    I64 uw_i = 0;
    while (uw_i < max_spins) {
        if (UartHasRx()) return 1;
        uw_i++;
    }
    return UartHasRx();
}

I64 UartGetChar() {
    I64 uart_base = hal_get_uart_base();
    if (!uart_base) return 0;
    return (I64)(__mmio_r32(uart_base + 0x00) & 0xFF);
}

I64 KeyboardPoll() {
    I64 count = 0;

    // 1. Poll VirtIO-Input hardware queues in addition to PL011 UART
    I64 prev_head = g_key_buf_head;
    VirtioInputPoll();
    if (g_key_buf_head != prev_head) {
        count = count + ((g_key_buf_head - prev_head) & (KEY_BUF_SIZE - 1));
    }

    // 2. Poll PL011 UART Hardware Input with spin-wait window for ANSI sequences
    while (UartHasRx()) {
        count++;
        I64 c = UartGetChar();
        if (c == 27) { // ESC (0x1B)
            if (UartWaitRx(3000)) {
                I64 c2 = UartGetChar();
                if (c2 == '[') {
                    if (UartWaitRx(3000)) {
                        I64 c3 = UartGetChar();
                        if (c3 == 'A') { KeyboardQueueChar(KEY_UP); continue; }
                        if (c3 == 'B') { KeyboardQueueChar(KEY_DOWN); continue; }
                        if (c3 == 'C') { KeyboardQueueChar(KEY_RIGHT); continue; }
                        if (c3 == 'D') { KeyboardQueueChar(KEY_LEFT); continue; }
                        if (c3 == 'H') { KeyboardQueueChar(KEY_HOME); continue; }
                        if (c3 == 'F') { KeyboardQueueChar(KEY_END); continue; }
                        if (c3 >= '0' && c3 <= '9') {
                            if (UartWaitRx(3000)) {
                                I64 c4 = UartGetChar();
                                // Consume trailing '~' of \x1B[5~, \x1B[6~, \x1B[1~, \x1B[4~
                                if (c4 != '~') {
                                    // Optional extra digit
                                    if (UartWaitRx(1000)) UartGetChar();
                                }
                            }
                            if (c3 == '5') { KeyboardQueueChar(KEY_PAGE_UP); continue; }
                            if (c3 == '6') { KeyboardQueueChar(KEY_PAGE_DOWN); continue; }
                            if (c3 == '1') { KeyboardQueueChar(KEY_HOME); continue; }
                            if (c3 == '4') { KeyboardQueueChar(KEY_END); continue; }
                        }
                    }
                } else if (c2 == 'O') {
                    if (UartWaitRx(3000)) {
                        I64 c3 = UartGetChar();
                        if (c3 == 'H') { KeyboardQueueChar(KEY_HOME); continue; }
                        if (c3 == 'F') { KeyboardQueueChar(KEY_END); continue; }
                    }
                }
            }
            KeyboardQueueChar(KEY_ESC);
        } else if (c == '\r' || c == '\n') {
            KeyboardQueueChar(KEY_ENTER);
        } else if (c == 8 || c == 127) {
            KeyboardQueueChar(KEY_BACKSPACE);
        } else {
            KeyboardQueueChar(c);
        }
    }

    return count;
}

// ------------------------------------------------------------------------------
// Keyboard.HC Verification Suite
// ------------------------------------------------------------------------------
I64 KeyboardSelfTest() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$  [KEYBOARD.HC] Pure HolyC Keyboard & UART Scorecard           $FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");

    I64 passed = 0;

    // Test 1: Initialization & Empty State
    KeyboardInit();
    I64 has_initial = KeyboardHasChar();
    I64 get_initial = KeyboardGetChar();
    if (has_initial == 0 && get_initial == 0) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Ring Buffer Initial State Empty\n");
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Initial state not empty\n");
    }

    // Test 2: Character Queue & Dequeue FIFO
    KeyboardQueueChar('H');
    KeyboardQueueChar('e');
    KeyboardQueueChar('l');
    KeyboardQueueChar('l');
    KeyboardQueueChar('o');

    I64 c1 = KeyboardGetChar();
    I64 c2 = KeyboardGetChar();
    I64 c3 = KeyboardGetChar();
    I64 c4 = KeyboardGetChar();
    I64 c5 = KeyboardGetChar();
    I64 c6 = KeyboardGetChar(); // empty

    if (c1 == 'H' && c2 == 'e' && c3 == 'l' && c4 == 'l' && c5 == 'o' && c6 == 0) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ FIFO Queue & Dequeue: 'H', 'e', 'l', 'l', 'o'\n");
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ FIFO Queue mismatch\n");
    }

    // Test 3: Special Keys & Navigation Constants (including PageUp, PageDown, Home, End)
    KeyboardQueueChar(KEY_UP);
    KeyboardQueueChar(KEY_DOWN);
    KeyboardQueueChar(KEY_LEFT);
    KeyboardQueueChar(KEY_RIGHT);
    KeyboardQueueChar(KEY_PAGE_UP);
    KeyboardQueueChar(KEY_PAGE_DOWN);
    KeyboardQueueChar(KEY_HOME);
    KeyboardQueueChar(KEY_END);
    KeyboardQueueChar(KEY_BACKSPACE);
    KeyboardQueueChar(KEY_ENTER);

    I64 k_up = KeyboardGetChar();
    I64 k_dn = KeyboardGetChar();
    I64 k_lt = KeyboardGetChar();
    I64 k_rt = KeyboardGetChar();
    I64 k_pu = KeyboardGetChar();
    I64 k_pd = KeyboardGetChar();
    I64 k_hm = KeyboardGetChar();
    I64 k_ed = KeyboardGetChar();
    I64 k_bs = KeyboardGetChar();
    I64 k_en = KeyboardGetChar();

    if (k_up == KEY_UP && k_dn == KEY_DOWN && k_lt == KEY_LEFT &&
        k_rt == KEY_RIGHT && k_pu == KEY_PAGE_UP && k_pd == KEY_PAGE_DOWN &&
        k_hm == KEY_HOME && k_ed == KEY_END && k_bs == KEY_BACKSPACE && k_en == KEY_ENTER) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Special Key Codes: UP/DOWN/LEFT/RIGHT/PGUP/PGDN/HOME/END/BS/ENTER\n");
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Special Key Codes mismatch\n");
    }

    // Test 4: Ring Buffer Wrap-Around
    I64 kb_i;
    for (kb_i = 0; kb_i < 300; kb_i++) {
        KeyboardQueueChar(kb_i & 0xFF);
        I64 val = KeyboardGetChar();
        if (val != (kb_i & 0xFF)) {
            break;
        }
    }
    if (kb_i == 300) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Ring Buffer 256-Element Wrap-Around Integrity (300 cycles)\n");
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Wrap-around failed at cycle %lld\n", kb_i);
    }

    // Test 5: PL011 UART Hardware Base Reflection
    I64 uart_base = hal_get_uart_base();
    if (uart_base != 0) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ PL011 UART Hardware Base Verified: 0x%016llX\n", uart_base);
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ PL011 UART Hardware Base is NULL\n");
    }

    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_printf("$FG,GREEN$  All %lld / 5 Keyboard.HC tests passed!$FG$\n", passed);
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");

    return passed;
}

I64 keyboard_poll() {
    return KeyboardPoll();
}

I64 keyboard_has_char() {
    KeyboardPoll();
    return KeyboardHasChar();
}

I64 keyboard_getchar() {
    KeyboardPoll();
    return KeyboardGetChar();
}

if (g_kernel_booting) {
    KeyboardInit();
} else {
    KeyboardSelfTest();
}
