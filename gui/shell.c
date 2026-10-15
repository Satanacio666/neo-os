#include "shell.h"
#include "render.h"
#include "wm.h"
#include "../compiler/jit_arm64.h"
#include "../drivers/input/keyboard.h"
#include "../kernel/mem/kheap.h"
#include "../fs/redsea.h"
#include <uefi.h>

static holyc_shell_run_cmd_t s_holyc_run_cmd = NULL;
static holyc_shell_poll_t    s_holyc_poll = NULL;

void shell_register_holyc(holyc_shell_run_cmd_t run_cmd, holyc_shell_poll_t poll_fn) {
    s_holyc_run_cmd = run_cmd;
    s_holyc_poll = poll_fn;
}

void shell_init(void) {
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$ NeoOS DolDoc 2.0 / Native HolyC Interactive Shell (Ring 0)$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" Architecture: ARMv8-A (AArch64) SASOS | Identity Paging 1:1\n");
    doldoc_print(" Actions: $BT,\"✦ NeoMenu\",LM=\"menu\"$ $BT,\"HolyBench\",LM=\"run HolyBenchmark.HC\"$ $BT,\"Files\",LM=\"filer\"$ $BT,\"Editor\",LM=\"run Editor.HC\"$ $BT,\"Top\",LM=\"top\"$ $BT,\"GPU\",LM=\"run GpuConfig.HC\"$ $BT,\"Help\",LM=\"help\"$\n");
    doldoc_print(" Apps: $FG,YELLOW$run HolyBenchmark.HC$FG$, $FG,YELLOW$filer$FG$, $FG,YELLOW$run Editor.HC$FG$, $FG,YELLOW$top$FG$, $FG,YELLOW$menu$FG$, $FG,YELLOW$help$FG$\n\n");
    doldoc_printf("$FG,CYAN$neo:%s>$FG,WHITE$ ", redsea_get_pwd());
    doldoc_draw_cursor(1);
    gfx_swap_buffers();
}

static const char* skip_leading_ws(const char *s) {
    while (*s && (*s == ' ' || *s == '\t' || *s == '\n' || *s == '\r')) s++;
    return s;
}

void shell_run_command(const char *raw_cmd) {
    if (s_holyc_run_cmd) {
        s_holyc_run_cmd(raw_cmd);
        return;
    }

    const char *cmd = skip_leading_ws(raw_cmd);
    if (!*cmd) {
        doldoc_printf("$FG,CYAN$neo:%s>$FG,WHITE$ ", redsea_get_pwd());
        return;
    }

    if (strcmp(cmd, "clear") == 0 || strcmp(cmd, "cls") == 0) {
        doldoc_clear();
    } else if (strcmp(cmd, "ls") == 0 || strcmp(cmd, "dir") == 0) {
        redsea_list_dir();
    } else {
        int64_t val = jit_compile_and_run(cmd);
        doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", (long long)val, (unsigned long long)val);
    }
    doldoc_printf("$FG,CYAN$neo:%s>$FG,WHITE$ ", redsea_get_pwd());
}

void shell_poll(void) {
    if (s_holyc_poll) {
        s_holyc_poll();
        return;
    }

    static char buf[256];
    static int len = 0;
    while (keyboard_has_char()) {
        int c = keyboard_getchar();
        if (c == '\n') {
            doldoc_putc('\n');
            buf[len] = '\0';
            shell_run_command(buf);
            len = 0;
            buf[0] = '\0';
        } else if (c == 8 || c == 127) {
            if (len > 0) {
                len--;
                buf[len] = '\0';
                doldoc_backspace();
            }
        } else if (c >= 32 && c < 127 && len < 255) {
            buf[len++] = (char)c;
            buf[len] = '\0';
            doldoc_putc((char)c);
        }
    }
}

void shell_task_recover(void) {
    doldoc_print("\n$FG,RED$[KERNEL BSOD RECOVERY]$FG$ HolyC Ring 0 execution aborted cleanly.\n");
    doldoc_print(" Unwound task execution context. System operational.\n");
    doldoc_printf("$FG,CYAN$neo:%s>$FG,WHITE$ ", redsea_get_pwd());
    doldoc_draw_cursor(1);
    gfx_dirty_all();
    gfx_swap_buffers();
}
