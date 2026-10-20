#include <uefi.h>
#include "../kernel/mem/kheap.h"
#include "../kernel/symbols/symbols.h"
#include "seed/jit_arm64.h"
#include "../kernel/arch/aarch64/hal_platform.h"
#include "../drivers/block/virtio_blk.h"
#include "../fs/redsea.h"
#include <stdarg.h>

#define KERNEL_HEAP_DEFAULT (32 * 1024 * 1024)
#define JIT_CODE_POOL_DEFAULT (4 * 1024 * 1024)

// Sized from the UEFI memory map at boot (boot_probe_memory); the defaults above
// are used only if the memory map cannot be read.
uint64_t g_total_ram_bytes = 0;
uint64_t g_free_ram_bytes = 0;
static uint64_t s_kernel_heap_size = KERNEL_HEAP_DEFAULT;
static uint64_t s_jit_code_pool_size = JIT_CODE_POOL_DEFAULT;

extern void install_vector_table(void);
extern void enable_interrupts(void);
extern void disable_interrupts(void);
extern void cpu_switch_context(void *prev, void *next);
extern int64_t psci_call_hvc(uint64_t func, uint64_t arg1, uint64_t arg2, uint64_t arg3);
extern int64_t psci_call_smc(uint64_t func, uint64_t arg1, uint64_t arg2, uint64_t arg3);
extern uint64_t smp_get_mpidr(void);
extern uint64_t smp_get_sctlr(void);
extern uint64_t smp_get_tcr(void);
extern uint64_t smp_get_mair(void);
extern uint64_t smp_get_ttbr0(void);
extern uint64_t smp_get_vbar(void);
extern void smp_spin_lock(volatile uint32_t *lock);
extern void smp_spin_unlock(volatile uint32_t *lock);
extern void smp_entry(void);
extern uint64_t g_arch_vectors[8];
extern uint64_t g_mmu_config[5];
extern void doldoc_register_holyc(void *ops);

static inline void aarch64_enable_fp(void) {
    uint64_t val;
    asm volatile("mrs %0, cpacr_el1" : "=r"(val));
    val |= (3ULL << 20); // Enable FP/ASIMD
    asm volatile("msr cpacr_el1, %0\nisb" :: "r"(val));
}



void uart_putc(char c) {
    putchar(c);
}

void uart_puts(const char *s) {
    if (!s) return;
    while (*s) {
        if (*s == '\n') putchar('\r');
        putchar(*s++);
    }
}

#include "../gui/font8x16.h"

const uint8_t* font_get_8x16_data(void) {
    return (const uint8_t*)font8x16_data;
}

static void boot_uart_doldoc_print(const char *str) {
    if (!str) return;
    for (const char *p = str; *p; p++) {
        if (*p == '$') {
            p++;
            while (*p && *p != '$') p++;
            if (*p == '$') continue;
        }
        putchar(*p);
    }
}

void doldoc_print(const char *str) {
    int64_t *p_booting = (int64_t*)symbols_lookup("g_kernel_booting");
    if (p_booting && *p_booting != 0) {
        boot_uart_doldoc_print(str);
        return;
    }
    void (*fn)(const char *) = (void (*)(const char *))symbols_lookup("doldoc_print");
    if (fn && fn != doldoc_print && fn != (void*)symbols_unresolved_trap && fn != (void*)boot_uart_doldoc_print) {
        fn(str);
    } else {
        boot_uart_doldoc_print(str);
    }
}

void doldoc_printf(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char buf[1024];
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    doldoc_print(buf);
}

static int s_gfx_active = 0;
int gfx_is_active(void) {
    return s_gfx_active;
}

// Global UEFI GOP Display parameters accessible to HolyC
uint32_t *g_uefi_fb = NULL;
uint64_t  g_uefi_width = 0;
uint64_t  g_uefi_height = 0;
uint64_t  g_uefi_pitch = 0;
uint64_t  g_uefi_heap_base = 0;
uint64_t  g_uefi_heap_size = 0;

static uint8_t s_mmap_buf[256 * 1024];

static uint64_t boot_clamp_u64(uint64_t v, uint64_t lo, uint64_t hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

// Read the UEFI memory map and size the kernel heap / JIT code pool from the
// available RAM instead of hardcoded constants. Falls back to the defaults if the
// map cannot be read.
static void boot_probe_memory(void) {
    uintn_t mmap_size = sizeof(s_mmap_buf);
    uintn_t map_key = 0;
    uintn_t desc_size = 0;
    uint32_t desc_ver = 0;
    efi_status_t st = BS->GetMemoryMap(&mmap_size, (efi_memory_descriptor_t*)s_mmap_buf,
                                       &map_key, &desc_size, &desc_ver);
    if (EFI_ERROR(st) || desc_size == 0) {
        printf("[BOOT] GetMemoryMap failed (0x%llX); using default pool sizes\r\n",
               (unsigned long long)st);
        return;
    }
    uint64_t free_bytes = 0, total_bytes = 0;
    for (uint8_t *p = s_mmap_buf; p < s_mmap_buf + mmap_size; p += desc_size) {
        efi_memory_descriptor_t *d = (efi_memory_descriptor_t*)p;
        uint64_t bytes = d->NumberOfPages * 4096ULL;
        if (d->Type == EfiConventionalMemory) free_bytes += bytes;
        if (d->Type != EfiReservedMemoryType && d->Type != EfiUnusableMemory) total_bytes += bytes;
    }
    g_total_ram_bytes = total_bytes;
    g_free_ram_bytes = free_bytes;
    s_kernel_heap_size = boot_clamp_u64(free_bytes / 4, 16ULL * 1024 * 1024, 64ULL * 1024 * 1024);
    s_jit_code_pool_size = boot_clamp_u64(free_bytes / 128, 4ULL * 1024 * 1024, 16ULL * 1024 * 1024);
    printf("[BOOT] Memory map: total %llu MB, free %llu MB -> heap %llu MB, JIT pool %llu MB\r\n",
           (unsigned long long)(total_bytes / (1024 * 1024)),
           (unsigned long long)(free_bytes / (1024 * 1024)),
           (unsigned long long)(s_kernel_heap_size / (1024 * 1024)),
           (unsigned long long)(s_jit_code_pool_size / (1024 * 1024)));
}

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    aarch64_enable_fp();
    hal_platform_init();
    printf("[DEBUG BASE] main is at 0x%016llX\n", (unsigned long long)main);

    printf("\n======================================================\n");
    printf(" NeoOS AArch64 (ARMv8-A Ring 0 / EL1)\n");
    printf(" Tier-0 Minimal Immutable UEFI Bootstrap Launcher\n");
    printf("======================================================\n\n");

    // 1. Locate UEFI Graphics Output Protocol (GOP)
    efi_guid_t gopGuid = EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID;
    efi_gop_t *gop = NULL;
    efi_status_t status = BS->LocateProtocol(&gopGuid, NULL, (void**)&gop);
    if (EFI_ERROR(status) || !gop) {
        printf("FATAL: UEFI GOP Protocol not available!\n");
        return 1;
    }

    uint32_t chosen_mode = 0;
    uint32_t max_modes = gop->Mode ? gop->Mode->MaxMode : 0;
    uint32_t best_area = 0;

    for (uint32_t m = 0; m < max_modes; m++) {
        efi_gop_mode_info_t *info = NULL;
        uintn_t info_size = 0;
        if (gop->QueryMode(gop, m, &info_size, &info) == EFI_SUCCESS && info) {
            uint32_t area = info->HorizontalResolution * info->VerticalResolution;
            if (info->HorizontalResolution == 1280 && info->VerticalResolution == 720) {
                chosen_mode = m;
                best_area = area * 2;
            } else if (area > best_area) {
                best_area = area;
                chosen_mode = m;
            }
        }
    }
    gop->SetMode(gop, chosen_mode);

    g_uefi_fb = (uint32_t*)gop->Mode->FrameBufferBase;
    g_uefi_width = gop->Mode->Information->HorizontalResolution;
    g_uefi_height = gop->Mode->Information->VerticalResolution;
    g_uefi_pitch = gop->Mode->Information->PixelsPerScanLine;
    s_gfx_active = 1;
    printf("[BOOT] GOP FrameBufferBase: 0x%016llX (%llux%llu, pitch %llu)\r\n",
           (unsigned long long)g_uefi_fb, (unsigned long long)g_uefi_width,
           (unsigned long long)g_uefi_height, (unsigned long long)g_uefi_pitch);

    // Size the heap / JIT pool from the real UEFI memory map.
    boot_probe_memory();

    // 2. Allocate Physical Memory Pools via UEFI Boot Services
    efi_physical_address_t heap_phys = 0;
    efi_status_t h_status = BS->AllocatePages(AllocateAnyPages, EfiLoaderData, s_kernel_heap_size / 4096, &heap_phys);
    if (EFI_ERROR(h_status) || !heap_phys) {
        printf("FATAL: Could not allocate kernel heap!\n");
        return 1;
    }
    kheap_init((void*)heap_phys, s_kernel_heap_size);
    g_uefi_heap_base = (uint64_t)heap_phys;
    g_uefi_heap_size = s_kernel_heap_size;

    // 3. Allocate Dedicated JIT Executable Pool (EfiLoaderCode)
    efi_physical_address_t jit_code_phys = 0;
    efi_status_t j_status = BS->AllocatePages(AllocateAnyPages, EfiLoaderCode, s_jit_code_pool_size / 4096, &jit_code_phys);
    if (!EFI_ERROR(j_status) && jit_code_phys) {
        jit_init_code_pool((void*)jit_code_phys, s_jit_code_pool_size);
    }

    // 3b. Allocate Dedicated Kernel Execution Stack (EfiLoaderData, 4 MB)
    efi_physical_address_t stack_phys = 0;
    const size_t KERNEL_STACK_SIZE = 4 * 1024 * 1024;
    uint64_t g_kernel_sp = 0;
    efi_status_t s_status = BS->AllocatePages(AllocateAnyPages, EfiLoaderData, KERNEL_STACK_SIZE / 4096, &stack_phys);
    if (!EFI_ERROR(s_status) && stack_phys) {
        g_kernel_sp = ((uint64_t)stack_phys + KERNEL_STACK_SIZE - 64) & ~15ULL;
        printf("[BOOT] Dedicated Kernel Execution Stack: 4 MB @ 0x%016llX (SP: 0x%016llX)\n",
               (unsigned long long)stack_phys, (unsigned long long)g_kernel_sp);
    }

    // 4. Initialize Cold-Boot JIT & Dynamic Symbol Registry (SIC Engine)
    symbols_init();
    jit_init();

    // Register Tier-0 Hardware Pointers & Vector Trampoline Table
    symbols_register("g_uefi_fb", (void*)&g_uefi_fb, SYM_VAR);
    symbols_register("g_uefi_width", (void*)&g_uefi_width, SYM_VAR);
    symbols_register("g_uefi_height", (void*)&g_uefi_height, SYM_VAR);
    symbols_register("g_uefi_pitch", (void*)&g_uefi_pitch, SYM_VAR);
    symbols_register("g_uefi_heap_base", (void*)&g_uefi_heap_base, SYM_VAR);
    symbols_register("g_uefi_heap_size", (void*)&g_uefi_heap_size, SYM_VAR);
    symbols_register("g_total_ram_bytes", (void*)&g_total_ram_bytes, SYM_VAR);
    symbols_register("g_free_ram_bytes", (void*)&g_free_ram_bytes, SYM_VAR);
    symbols_register("g_arch_vectors", (void*)g_arch_vectors, SYM_VAR);
    symbols_register("g_mmu_config", (void*)g_mmu_config, SYM_VAR);
    symbols_register("font_get_8x16_data", (void*)font_get_8x16_data, SYM_FUNC);

    // Memory & Seed JIT
    symbols_register("kmalloc", (void*)kmalloc, SYM_FUNC);
    symbols_register("kfree", (void*)kfree, SYM_FUNC);
    symbols_register("symbols_lookup", (void*)symbols_lookup, SYM_FUNC);
    symbols_register("symbols_register", (void*)symbols_register, SYM_FUNC);
    symbols_register("symbols_count", (void*)symbols_count, SYM_FUNC);
    symbols_register("jit_eval", (void*)jit_eval, SYM_FUNC);
    symbols_register("jit_compile_and_run", (void*)jit_compile_and_run, SYM_FUNC);
    symbols_register("doldoc_print", (void*)boot_uart_doldoc_print, SYM_FUNC);
    symbols_register("doldoc_printf", (void*)doldoc_printf, SYM_FUNC);
    symbols_register("doldoc_register_holyc", (void*)doldoc_register_holyc, SYM_FUNC);
    symbols_register("hal_flush_cache", (void*)hal_flush_cache, SYM_FUNC);
    symbols_register("uart_putc", (void*)uart_putc, SYM_FUNC);
    symbols_register("uart_puts", (void*)uart_puts, SYM_FUNC);

    // Minimal libc primitives from UEFI
    symbols_register("strcmp", (void*)strcmp, SYM_FUNC);
    symbols_register("strncmp", (void*)strncmp, SYM_FUNC);
    symbols_register("strlen", (void*)strlen, SYM_FUNC);
    symbols_register("strcpy", (void*)strcpy, SYM_FUNC);
    symbols_register("strncpy", (void*)strncpy, SYM_FUNC);
    symbols_register("memset", (void*)memset, SYM_FUNC);
    symbols_register("memcpy", (void*)memcpy, SYM_FUNC);
    symbols_register("strcat", (void*)strcat, SYM_FUNC);
    symbols_register("memcmp", (void*)memcmp, SYM_FUNC);
    symbols_register("memmove", (void*)memmove, SYM_FUNC);
    symbols_register("strstr", (void*)strstr, SYM_FUNC);
    symbols_register("atoi", (void*)atoi, SYM_FUNC);
    symbols_register("snprintf", (void*)snprintf, SYM_FUNC);

    // Assembly Hardware Primitives (vectors.S, smp_entry.S, switch.S)
    symbols_register("psci_call_hvc", (void*)psci_call_hvc, SYM_FUNC);
    symbols_register("psci_call_smc", (void*)psci_call_smc, SYM_FUNC);
    symbols_register("smp_get_mpidr", (void*)smp_get_mpidr, SYM_FUNC);
    symbols_register("smp_get_sctlr", (void*)smp_get_sctlr, SYM_FUNC);
    symbols_register("smp_get_tcr", (void*)smp_get_tcr, SYM_FUNC);
    symbols_register("smp_get_mair", (void*)smp_get_mair, SYM_FUNC);
    symbols_register("smp_get_ttbr0", (void*)smp_get_ttbr0, SYM_FUNC);
    symbols_register("smp_get_vbar", (void*)smp_get_vbar, SYM_FUNC);
    symbols_register("smp_spin_lock", (void*)smp_spin_lock, SYM_FUNC);
    symbols_register("smp_spin_unlock", (void*)smp_spin_unlock, SYM_FUNC);
    symbols_register("smp_entry", (void*)smp_entry, SYM_FUNC);
    symbols_register("cpu_switch_context", (void*)cpu_switch_context, SYM_FUNC);
    symbols_register("install_vector_table", (void*)install_vector_table, SYM_FUNC);
    symbols_register("enable_interrupts", (void*)enable_interrupts, SYM_FUNC);
    symbols_register("disable_interrupts", (void*)disable_interrupts, SYM_FUNC);

    // 5. Initialize Cold-Boot Storage to Load KernelInit.HC
    virtio_blk_init();
    redsea_init(0);
    symbols_register("redsea_read_file", (void*)redsea_read_file, SYM_FUNC);
    symbols_register("redsea_write_file", (void*)redsea_write_file, SYM_FUNC);
    symbols_register("redsea_list_dir", (void*)redsea_list_dir, SYM_FUNC);
    symbols_register("symbols_report_unresolved", (void*)symbols_report_unresolved, SYM_FUNC);
    symbols_register("symbols_sic_cell", (void*)symbols_sic_cell, SYM_FUNC);
    symbols_register("symbols_var_cell", (void*)symbols_var_cell, SYM_FUNC);

    // 6. Sovereign Handover: Read and Execute apps/KernelInit.HC
    printf("[BOOT] Sovereign Handover: Loading apps/KernelInit.HC from RedSea disk...\r\n");
    static char kinit_src[65536];
    size_t kinit_len = 0;
    if (redsea_read_file("KernelInit.HC", kinit_src, sizeof(kinit_src) - 1, &kinit_len) == 0) {
        kinit_src[kinit_len] = '\0';
        printf("[BOOT] Compiling and Executing KernelInit.HC (%llu bytes)...\r\n", (unsigned long long)kinit_len);
        int64_t res = 0;
        if (g_kernel_sp) {
            register uint64_t r_sp asm("x20") = g_kernel_sp;
            register const char *r_src asm("x21") = kinit_src;
            asm volatile(
                "mov x19, sp\n"
                "mov sp, %1\n"
                "mov x0, %2\n"
                "bl  jit_compile_and_run\n"
                "mov %0, x0\n"
                "mov sp, x19\n"
                : "=r"(res)
                : "r"(r_sp), "r"(r_src)
                : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7",
                  "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15",
                  "x16", "x17", "x18", "x19", "x30", "memory"
            );
        } else {
            res = jit_compile_and_run(kinit_src);
        }
        printf("[BOOT] Sovereign KernelInit returned: %lld\r\n", (long long)res);
    } else {
        printf("[FATAL] Could not read KernelInit.HC from RedSea disk!\r\n");
    }

    // 7. Halt if HolyC ever yields back to firmware
    while (1) {
        asm volatile("wfi");
    }

    return 0;
}
