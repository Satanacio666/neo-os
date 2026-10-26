#include <uefi.h>
#include "runtime/kheap.h"
#include "runtime/symbols.h"
#include "seed/jit_arm64.h"
#include "seed/seed_fs.h"
#include <stdarg.h>

#define KERNEL_HEAP_DEFAULT (32 * 1024 * 1024)
#define JIT_CODE_POOL_DEFAULT (4 * 1024 * 1024)

// Sized from the UEFI memory map at boot (boot_probe_memory); the defaults above
// are used only if the memory map cannot be read.
uint64_t g_total_ram_bytes = 0;
uint64_t g_free_ram_bytes = 0;
static uint64_t s_kernel_heap_size = KERNEL_HEAP_DEFAULT;
static uint64_t s_jit_code_pool_size = JIT_CODE_POOL_DEFAULT;

/* P8 — tamanhos FIXOS. Ver a nota em main() sobre determinismo de memoria: sem
 * isto o heap e o pool do JIT mudam de endereco a cada boot, e o codigo emitido
 * embute enderecos absolutos — o cache de JIT nunca poderia validar. */
#define NEO_HEAP_BYTES      (64ULL * 1024 * 1024)
#define NEO_JIT_POOL_BYTES  (16ULL * 1024 * 1024)

extern void install_vector_table(void);

/* P5.2 — interface de system registers do GICv3 (kernel/arch/aarch64/gicv3.c) */
extern uint64_t gicv3_sre_get(void);
extern uint64_t gicv3_sre_enable(void);
extern uint64_t gicv3_sre_el2_enable(void);
extern void     gicv3_pmr_set(uint64_t v);
extern uint64_t gicv3_pmr_get(void);
extern uint64_t gicv3_ctlr_get(void);
extern void     gicv3_ctlr_set(uint64_t v);
extern uint64_t gicv3_iar1(void);
extern void     gicv3_eoir1(uint64_t v);
extern void     gicv3_igrpen1_set(uint64_t v);
extern uint64_t gicv3_igrpen1_get(void);
extern uint32_t neo_probe_mmio_read32(uint64_t addr, int *faulted);
extern uint64_t neo_midr_el1(void);
extern uint64_t neo_midr_implementer(void);
extern uint64_t neo_midr_partnum(void);

/* P7.1 — descoberta de armazenamento (boot/runtime/blockio.c) */
extern int      neo_block_probe(void);
extern int      neo_block_count(void);
extern int      neo_block_primary(void);
extern uint32_t neo_block_size(int idx);
extern uint64_t neo_block_last(int idx);
extern uint64_t neo_block_bytes(int idx);
extern int      neo_block_is_removable(int idx);
extern int64_t  neo_block_read(int idx, uint64_t lba, uint64_t count, void *buf);
extern int64_t  neo_block_write(int idx, uint64_t lba, uint64_t count, const void *buf);

/* P7.2 — crash dump em setores crus (boot/runtime/blockio.c) */
extern void neo_crash_dump_to_disk(uint64_t esr, uint64_t elr, uint64_t far, uint64_t spsr);
extern void neo_crash_set_heap(uint64_t base);
extern void neo_crash_set_module(uint64_t idx, const char *name);

/* E1 — descoberta da descricao de hardware (boot/runtime/fwdesc.c) */
extern int      neo_fwdesc_probe(void);
extern int      neo_fwdesc_has_dtb(void);
extern int      neo_fwdesc_has_acpi(void);
extern uint32_t neo_fwdesc_fdt_size(void);

/* E2 — descoberta de hardware por ACPI (boot/runtime/acpi.c) */
extern int      acpi_discover(void *rsdp_ptr);
extern void     acpi_report(void);
extern uint64_t acpi_gicd_base(void);
extern uint64_t acpi_gicr_base(void);
extern uint64_t acpi_uart_base(void);
extern uint32_t acpi_uart_type(void);
extern uint32_t acpi_gic_version(void);
extern uint32_t acpi_timer_virt(void);
extern uint32_t acpi_timer_phys(void);
extern uint64_t acpi_gicc_base(void);
extern uint32_t acpi_source(void);
extern uint64_t acpi_virtio_base(void);
extern uint32_t acpi_virtio_stride(void);
extern uint32_t acpi_virtio_slots(void);
extern uint32_t acpi_cpu_count(void);

/* E4 — descoberta por Device Tree (boot/runtime/fdt.c) */
extern int  fdt_discover(void *blob, int only_missing);
extern void fdt_report(void);

/* E5 — identidade e perfil como dado (boot/runtime/profile.c) */
extern const char *disco_identity(void);
/* E6 — fatos de registrador de sistema (CTR_EL0). Nao vem de tabela nenhuma. */
extern void     disco_read_system_facts(void);
extern uint32_t disco_dcache_line(void);
extern int      profile_load(void);
extern void     profile_defaults(void);
extern uint32_t profile_loaded(void);
extern uint32_t profile_tile_size(void);
extern uint32_t profile_morton(void);
extern uint32_t profile_smp_cores(void);
extern uint32_t profile_errata(void);
extern uint32_t profile_throttle_us(void);
extern const char *profile_name(void);
extern void    *g_acpi_rsdp;
extern void    *g_fdt_blob;
extern void     gicv3_bpr1_set(uint64_t v);
extern uint64_t gicv3_bpr1_get(void);
extern int      neo_pl011_available(void);
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

// Defined further down (boot_probe_memory / the pool allocations in main); the
// tier-0 panic reporter above uses them for its heap-relative fault offset.
extern uint64_t g_uefi_heap_base;
extern uint64_t g_uefi_heap_size;

#ifndef NEO_P08_VECTORS
#define NEO_P08_VECTORS 1
#endif

static inline void aarch64_enable_fp(void) {
    uint64_t val;
    asm volatile("mrs %0, cpacr_el1" : "=r"(val));
    val |= (3ULL << 20); // Enable FP/ASIMD
    asm volatile("msr cpacr_el1, %0\nisb" :: "r"(val));
}

// ---------------------------------------------------------------------------
// P0.8 — Ring-0 execution environment + tier-0 fault reporting.
//
// The HolyC self-hosted compiler allocates its own executable code buffer out of
// the Seed Heap (apps/Compiler.HC: `g_hc_code = kmalloc(HC_CODE_CAPACITY * 4)`)
// and `CompilerCompileAndRun` dispatches into it with `BLR`. A SASOS therefore
// needs an *executable* heap. With the Seed Heap requested as EfiLoaderData the
// firmware maps its pages with PXN/UXN=1 (and SCTLR_EL1.WXN makes every writable
// page non-executable), so the first `BLR` into freshly emitted code raised an
// Instruction Abort (EC=0x21) that the firmware's VBAR_EL1 reported as an opaque
// "Synchronous Exception at 0x...".
//
// Root fix: (1) request the heap as EfiLoaderCode, (2) clear SCTLR_EL1.WXN,
// (3) drop stale TLB entries so the new attributes take effect.
static void neo_harden_exec_env(void)
{
    uint64_t sctlr;
    asm volatile("mrs %0, sctlr_el1" : "=r"(sctlr));
    if (sctlr & (1ULL << 19)) {
        sctlr &= ~(1ULL << 19);
        asm volatile("msr sctlr_el1, %0" :: "r"(sctlr));
        printf("[BOOT] SCTLR_EL1.WXN was set by firmware -> cleared\r\n");
    }
    asm volatile("dsb sy\nisb");
    asm volatile("tlbi vmalle1\ndsb sy\nisb");
    printf("[BOOT] Ring-0 exec env: heap=0x%016llX (%llu MB, EfiLoaderCode) WXN=%llu\r\n",
           (unsigned long long)g_uefi_heap_base,
           (unsigned long long)(g_uefi_heap_size / (1024 * 1024)),
           (unsigned long long)((sctlr >> 19) & 1));
}

// apps/Exceptions.HC installs the real Ring-0 handler — but only as module 5 of
// Stage 1, i.e. AFTER Compiler.HC/HalPlatform.HC/Timer.HC/Gic.HC. Until then
// g_arch_vectors[0] is NULL and a synchronous fault fell through to the
// firmware's vectors. This hook keeps the diagnosis in-house: it dumps the full
// syndrome over the UART and halts (never eret-loops on the fault).
void (*g_early_panic_hook)(uint64_t esr, uint64_t elr, uint64_t far, uint64_t spsr) = 0;

static const char *neo_ec_name(uint64_t ec)
{
    switch (ec) {
    case 0x00: return "Unknown";
    case 0x01: return "Trapped WFI/WFE";
    case 0x07: return "SVE/SIMD/FP access";
    case 0x0E: return "Illegal Execution state";
    case 0x18: return "Trapped MSR/MRS";
    case 0x20: return "Instruction Abort (lower EL)";
    case 0x21: return "Instruction Abort (same EL)";
    case 0x22: return "PC Alignment fault";
    case 0x24: return "Data Abort (lower EL)";
    case 0x25: return "Data Abort (same EL)";
    case 0x26: return "SP Alignment fault";
    case 0x2C: return "FP/SIMD exception";
    case 0x3C: return "BRK (breakpoint)";
    default:   return "Reserved";
    }
}

// P0.8 regression guard (D35): prove the Seed Heap is executable BEFORE the .HC
// handover, by emitting a real ARM64 stub into kmalloc'd heap memory and calling
// it. The self-hosted compiler does exactly this with `g_hc_code`; if the heap
// ever stops being EfiLoaderCode the boot must fail HERE, loudly, instead of
// aborting at heap + 0x47CC98 in the middle of compiling HalPlatform.HC.
static void neo_verify_heap_executable(void)
{
    void *p = kmalloc(4096);
    if (!p) {
        printf("[P0.8] WARN: heap self-test skipped (kmalloc returned NULL)\n");
        return;
    }
    volatile uint32_t *stub = (volatile uint32_t *)p;
    stub[0] = 0xD2800B40u;   // mov  x0, #0x5A
    stub[1] = 0xD65F03C0u;   // ret
    asm volatile("dc cvau, %0" :: "r"(stub));
    asm volatile("dsb ish");
    asm volatile("ic ivau, %0" :: "r"(stub));
    asm volatile("dsb ish\nisb");

    uint64_t (*fn)(void) = (uint64_t (*)(void))stub;
    uint64_t r = fn();
    if (r != 0x5A) {
        printf("[P0.8] FATAL: Seed Heap self-test returned 0x%llX (want 0x5A)\n",
               (unsigned long long)r);
        while (1) { asm volatile("wfi"); }
    }
    printf("[BOOT] Seed Heap executable self-test: PASS (ret=0x%llX)\n",
           (unsigned long long)r);
}

// P2.3 — Prova de ida e volta no ESP: grava, relê e compara.
//
// Não é fatal de propósito: um ESP pode ser legitimamente somente-leitura, e
// nesse caso o cache de JIT (P2.4) simplesmente não é gravado — o boot segue
// compilando normalmente. Falha aqui = aviso, nunca parada.
static void neo_verify_esp_write(void)
{
    static const char pattern[] = "NEOOS-ESP-WRITE-SELFTEST-v1";
    char back[64];

    int64_t w = seed_write_file("SEEDTEST.TMP", pattern, sizeof(pattern));
    if (w != (int64_t)sizeof(pattern)) {
        printf("[P2.3] WARN: ESP nao gravavel (write=%lld) — cache de JIT indisponivel\r\n",
               (long long)w);
        return;
    }
    int64_t r = seed_read_file("SEEDTEST.TMP", back, sizeof(back));
    if (r != (int64_t)sizeof(pattern) || memcmp(back, pattern, sizeof(pattern)) != 0) {
        printf("[P2.3] FAIL: ida-e-volta no ESP nao bate (r=%lld)\r\n", (long long)r);
        return;
    }
    printf("[BOOT] ESP write self-test: PASS (%lld bytes, fnv1a=0x%08X)\r\n",
           (long long)r, seed_fnv1a(back, (size_t)r));
}

void neo_early_panic(uint64_t esr, uint64_t elr, uint64_t far, uint64_t spsr)
{
    uint64_t ec = (esr >> 26) & 0x3F;
    uint64_t iss = esr & 0x1FFFFFF;
    printf("\r\n");
    printf("========== NeoOS TIER-0 SYNC FAULT (pre-.HC) ==========\r\n");
    printf(" ESR_EL1 : 0x%016llX  EC=0x%02llX %s\r\n", esr, ec, neo_ec_name(ec));
    printf(" ISS     : 0x%08llX  IFSC/DFSC=0x%02llX\r\n", iss, iss & 0x3F);
    printf(" ELR_EL1 : 0x%016llX\r\n", elr);
    printf(" FAR_EL1 : 0x%016llX\r\n", far);
    printf(" SPSR_EL1: 0x%016llX\r\n", spsr);
    printf(" heap    : 0x%016llX  (faulting PC - heap_base = 0x%llX)\r\n",
           (unsigned long long)g_uefi_heap_base,
           (unsigned long long)(elr - g_uefi_heap_base));
    printf("=========== <<<BSOD:TIER0>>> HALTED ===========\r\n");

    // P7.2 — Grava o dump em setores CRUS, fora da FAT, ANTES de travar.
    // Caminho de falha: sem alocacao, sem heap, sem driver FAT — so
    // BlockIo->WriteBlocks para a zona reservada no fim da midia.
    // Leitura offline: scripts/read-crash-dump.py
    neo_crash_dump_to_disk(esr, elr, far, spsr);
    printf("=========== dump gravado em LBA %d ===========\r\n", (int)NEO_CRASH_ZONE_LBA);

    while (1) {
        asm volatile("wfi");
    }
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

    // P8 — DETERMINISMO DE MEMORIA (pre-requisito do cache de JIT).
    //
    // ANTES: os tamanhos vinham da memoria LIVRE, que varia entre boots porque o
    // firmware deixa estados ligeiramente diferentes. Medido em dois boots:
    //   Scratch @ 0xB812A000 | Persistent Pool 15952 KB
    //   Scratch @ 0xB6FB4000 | Persistent Pool 15964 KB
    // O codigo emitido embute enderecos ABSOLUTOS (heap, funcoes do EFI, pool).
    // Com o pool mudando de lugar a cada boot, qualquer cache validado por ancora
    // de endereco NUNCA acertaria — seria peso morto com aparencia de otimizacao.
    //
    // AGORA: tamanhos FIXOS. O heap e o pool ficam no mesmo endereco em todo
    // boot, e o cache pode validar. O ganho de "adaptar o tamanho a memoria livre"
    // era ilusorio: 64 MB de heap e 16 MB de pool sao o teto do clamp de qualquer
    // forma, e o pool nunca passa de ~16 MB em uso real.
    s_kernel_heap_size   = NEO_HEAP_BYTES;
    s_jit_code_pool_size = NEO_JIT_POOL_BYTES;
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

    // Mask IRQ/FIQ/SError/Debug from the very first instruction. EDK2 hands off with
    // DAIF masked, but U-Boot may not: an unmasked timer IRQ taken before
    // disable_interrupts() would vector through the firmware's VBAR (the NeoOS vectors
    // are not installed yet) and reset the whole boot. Measured symptom without this:
    // the app re-entered main() dozens of times, each preceded by a U-Boot restart.
    asm volatile("msr daifset, #0xf" ::: "memory");

    aarch64_enable_fp();
    printf("[DEBUG BASE] main is at 0x%016llX\n", (unsigned long long)main);

    // P1.1 / D36: the NeoOS is designed for EL1, but the handoff EL is firmware-dependent
    // (AAVMF/EDK2 enters at EL1; U-Boot and Renegade EDK2 enter at EL2). At EL2 every EL1
    // write is silently ignored and the boot derails. The drop itself happens LATER, after
    // every UEFI Boot Services call is done — see the P1.1/P4.3 block below.
    extern uint32_t neo_get_current_el(void);
    extern uint32_t neo_ensure_el1(void);
    uint32_t el_at_entry = neo_get_current_el();
    printf("[BOOT] CurrentEL at entry = EL%u\r\n", (unsigned)el_at_entry);

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
    //    P0.8: the Seed Heap MUST be executable. apps/Compiler.HC (self-hosted)
    //    allocates its JIT code buffer from this heap with kmalloc() and calls
    //    into it; EfiLoaderData pages are mapped non-executable by EDK2 2024.11+.
    efi_physical_address_t heap_phys = 0;
    efi_status_t h_status = BS->AllocatePages(AllocateAnyPages, EfiLoaderCode, s_kernel_heap_size / 4096, &heap_phys);
    if (EFI_ERROR(h_status) || !heap_phys) {
        printf("FATAL: Could not allocate kernel heap!\n");
        return 1;
    }
    kheap_init((void*)heap_phys, s_kernel_heap_size);
    g_uefi_heap_base = (uint64_t)heap_phys;

    // P7.2 — contexto para o crash dump: a base do heap entra no cabecalho, o que
    // permite ver de imediato se o PC da falha caiu dentro do heap (JIT) ou fora.
    neo_crash_set_heap((uint64_t)heap_phys);
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
    symbols_register("symbols_is_defined", (void*)symbols_is_defined, SYM_FUNC);
    symbols_register("symbols_is_func", (void*)symbols_is_func, SYM_FUNC);
    symbols_register("symbols_is_var", (void*)symbols_is_var, SYM_FUNC);
    symbols_register("symbols_count", (void*)symbols_count, SYM_FUNC);
    symbols_register("jit_eval", (void*)jit_eval, SYM_FUNC);
    symbols_register("jit_compile_and_run", (void*)jit_compile_and_run, SYM_FUNC);
    symbols_register("doldoc_print", (void*)boot_uart_doldoc_print, SYM_FUNC);
    symbols_register("doldoc_printf", (void*)doldoc_printf, SYM_FUNC);
    symbols_register("doldoc_register_holyc", (void*)doldoc_register_holyc, SYM_FUNC);
    // hal_flush_cache is owned by apps/HalPlatform.HC (P2.1); no C implementation.
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

    // P5.2 — GICv3: interface de system registers (ICC_*_EL1). O HolyC nao tem
    // mnemonicos para eles; o apps/Gic.HC chama estas funcoes pelo nome.
    symbols_register("gicv3_sre_get", (void*)gicv3_sre_get, SYM_FUNC);
    symbols_register("gicv3_sre_enable", (void*)gicv3_sre_enable, SYM_FUNC);
    symbols_register("gicv3_sre_el2_enable", (void*)gicv3_sre_el2_enable, SYM_FUNC);
    symbols_register("gicv3_pmr_set", (void*)gicv3_pmr_set, SYM_FUNC);
    symbols_register("gicv3_pmr_get", (void*)gicv3_pmr_get, SYM_FUNC);
    symbols_register("gicv3_ctlr_get", (void*)gicv3_ctlr_get, SYM_FUNC);
    symbols_register("gicv3_ctlr_set", (void*)gicv3_ctlr_set, SYM_FUNC);
    symbols_register("gicv3_iar1", (void*)gicv3_iar1, SYM_FUNC);
    symbols_register("gicv3_eoir1", (void*)gicv3_eoir1, SYM_FUNC);
    symbols_register("gicv3_igrpen1_set", (void*)gicv3_igrpen1_set, SYM_FUNC);
    symbols_register("gicv3_igrpen1_get", (void*)gicv3_igrpen1_get, SYM_FUNC);
    // P5.2 — sonda de MMIO com recuperacao pelo tier-0 (vectors.S).
    symbols_register("neo_probe_mmio_read32", (void*)neo_probe_mmio_read32, SYM_FUNC);
    symbols_register("gicv3_bpr1_set", (void*)gicv3_bpr1_set, SYM_FUNC);
    symbols_register("gicv3_bpr1_get", (void*)gicv3_bpr1_get, SYM_FUNC);
    // P5.1 — guarda do PL011 para os modulos HolyC (Keyboard.HC / HalPlatform.HC).
    symbols_register("neo_pl011_available", (void*)neo_pl011_available, SYM_FUNC);
    // P1.2 — identidade do silicio (MIDR_EL1), para o HolyC escolher a plataforma.
    symbols_register("neo_midr_el1", (void*)neo_midr_el1, SYM_FUNC);
    symbols_register("neo_midr_implementer", (void*)neo_midr_implementer, SYM_FUNC);
    symbols_register("neo_midr_partnum", (void*)neo_midr_partnum, SYM_FUNC);

    // P7.1 — armazenamento via EFI_BLOCK_IO. O apps/RedSea.HC consome
    // neo_block_read e neo_block_write; o resto e diagnostico e escolha do primario.
    symbols_register("neo_block_probe", (void*)neo_block_probe, SYM_FUNC);
    symbols_register("neo_block_count", (void*)neo_block_count, SYM_FUNC);
    symbols_register("neo_block_primary", (void*)neo_block_primary, SYM_FUNC);
    symbols_register("neo_block_size", (void*)neo_block_size, SYM_FUNC);
    symbols_register("neo_block_last", (void*)neo_block_last, SYM_FUNC);
    symbols_register("neo_block_bytes", (void*)neo_block_bytes, SYM_FUNC);
    symbols_register("neo_block_is_removable", (void*)neo_block_is_removable, SYM_FUNC);
    symbols_register("neo_block_read", (void*)neo_block_read, SYM_FUNC);
    symbols_register("neo_block_write", (void*)neo_block_write, SYM_FUNC);

    // P7.2 — crash dump. O KernelInit.HC chama neo_crash_set_module antes de cada
    // compilacao, para o dump dizer QUAL modulo estava ativo quando falhou.
    symbols_register("neo_crash_dump_to_disk", (void*)neo_crash_dump_to_disk, SYM_FUNC);
    symbols_register("neo_crash_set_heap", (void*)neo_crash_set_heap, SYM_FUNC);
    symbols_register("neo_crash_set_module", (void*)neo_crash_set_module, SYM_FUNC);

    // E1 — descoberta de hardware pelo firmware (DTB/ACPI). O HolyC consulta isto
    // para saber se ha descricao utilizavel antes de cair em defaults.
    symbols_register("neo_fwdesc_probe", (void*)neo_fwdesc_probe, SYM_FUNC);
    symbols_register("neo_fwdesc_has_dtb", (void*)neo_fwdesc_has_dtb, SYM_FUNC);
    symbols_register("neo_fwdesc_has_acpi", (void*)neo_fwdesc_has_acpi, SYM_FUNC);
    symbols_register("neo_fwdesc_fdt_size", (void*)neo_fwdesc_fdt_size, SYM_FUNC);

    // E2 — descoberta por ACPI. A HAL consulta estes acessores; se a descoberta
    // falhar ou nao existir, todos devolvem 0 e a HAL cai em defaults seguros.
    symbols_register("acpi_discover", (void*)acpi_discover, SYM_FUNC);
    symbols_register("acpi_report", (void*)acpi_report, SYM_FUNC);
    symbols_register("acpi_gicd_base", (void*)acpi_gicd_base, SYM_FUNC);
    symbols_register("acpi_gicr_base", (void*)acpi_gicr_base, SYM_FUNC);
    symbols_register("acpi_uart_base", (void*)acpi_uart_base, SYM_FUNC);
    symbols_register("acpi_uart_type", (void*)acpi_uart_type, SYM_FUNC);
    symbols_register("acpi_gic_version", (void*)acpi_gic_version, SYM_FUNC);
    symbols_register("acpi_timer_virt", (void*)acpi_timer_virt, SYM_FUNC);
    symbols_register("acpi_timer_phys", (void*)acpi_timer_phys, SYM_FUNC);
    symbols_register("acpi_gicc_base", (void*)acpi_gicc_base, SYM_FUNC);
    symbols_register("acpi_source", (void*)acpi_source, SYM_FUNC);
    symbols_register("acpi_cpu_count", (void*)acpi_cpu_count, SYM_FUNC);

    // E4 — descoberta por Device Tree. O FDT e o unico que traz dispositivos de
    // placa (virtio-mmio), que o ACPI nao descreve.
    symbols_register("fdt_discover", (void*)fdt_discover, SYM_FUNC);
    symbols_register("fdt_report", (void*)fdt_report, SYM_FUNC);
    symbols_register("acpi_virtio_base", (void*)acpi_virtio_base, SYM_FUNC);
    symbols_register("acpi_virtio_stride", (void*)acpi_virtio_stride, SYM_FUNC);
    symbols_register("acpi_virtio_slots", (void*)acpi_virtio_slots, SYM_FUNC);

    // E5 — identidade e perfil. O HolyC le estes para ajustar politica (tiling,
    // SMP, erratas) sem que a politica contamine a descoberta.
    symbols_register("disco_identity", (void*)disco_identity, SYM_FUNC);
    symbols_register("disco_read_system_facts", (void*)disco_read_system_facts, SYM_FUNC);
    symbols_register("disco_dcache_line", (void*)disco_dcache_line, SYM_FUNC);
    symbols_register("profile_load", (void*)profile_load, SYM_FUNC);
    symbols_register("profile_defaults", (void*)profile_defaults, SYM_FUNC);
    symbols_register("profile_loaded", (void*)profile_loaded, SYM_FUNC);
    symbols_register("profile_tile_size", (void*)profile_tile_size, SYM_FUNC);
    symbols_register("profile_morton", (void*)profile_morton, SYM_FUNC);
    symbols_register("profile_smp_cores", (void*)profile_smp_cores, SYM_FUNC);
    symbols_register("profile_errata", (void*)profile_errata, SYM_FUNC);
    symbols_register("profile_throttle_us", (void*)profile_throttle_us, SYM_FUNC);
    symbols_register("profile_name", (void*)profile_name, SYM_FUNC);
    symbols_register("enable_interrupts", (void*)enable_interrupts, SYM_FUNC);
    symbols_register("disable_interrupts", (void*)disable_interrupts, SYM_FUNC);

    // 5. Initialize Cold-Boot Storage.
    //    P2.2/P2.4: the seed reads the OS's own .HC sources from the FAT32 ESP via
    //    the UEFI firmware's FAT driver. The block device and filesystem are owned
    //    entirely by the .HC drivers (VirtioBlk.HC / RedSea.HC) — no C HAL, block
    //    driver or filesystem.
    if (seed_fs_init() != 0) {
        printf("[BOOT] WARN: UEFI filesystem (ESP) unavailable; cannot read .HC sources.\r\n");
    }
    symbols_register("seed_read_file", (void*)seed_read_file, SYM_FUNC);
    // P2.3: escrita no ESP pelo driver FAT do firmware — fundação do cache de JIT
    // (P2.4) e da validação de ida e volta do RedSea sobre EFI_BLOCK_IO (P3.2).
    symbols_register("seed_write_file", (void*)seed_write_file, SYM_FUNC);
    symbols_register("seed_delete_file", (void*)seed_delete_file, SYM_FUNC);
    symbols_register("seed_fnv1a", (void*)seed_fnv1a, SYM_FUNC);
    neo_verify_esp_write();

    // P7.1 — Descoberta de armazenamento via EFI_BLOCK_IO_PROTOCOL.
    // Precisa rodar AQUI: e uma chamada a Boot Services, e depois do drop elas
    // nao podem mais ser feitas. E tambem aqui que descobrimos, na propria POCO,
    // o que o Renegade EDK2 expoe — sem supor nada sobre UFS ou USB.
    neo_block_probe();

    // E1 — Descoberta da descricao de hardware entregue pelo firmware (DTB/ACPI).
    // E o alicerce da universalidade: a partir daqui a plataforma deixa de ser
    // uma tabela escrita a mao e passa a ser lida do que o firmware descreve.
    neo_fwdesc_probe();

    // E2 — Se o firmware entregou ACPI, extrai GIC/UART/timer/CPUs das tabelas.
    // Se nao entregou (ou o parse falhar), os acessores ficam em 0 e a HAL cai em
    // defaults seguros. Essa e a invariante da universalidade: perfil/descoberta
    // ausente => boota igual. Nunca "boota ou nao".
    if (neo_fwdesc_has_acpi()) {
        if (acpi_discover(g_acpi_rsdp) == 0) acpi_report();
    }
    // E4 — O FDT complementa o ACPI: preenche o que faltar, inclusive os
    // dispositivos de PLACA (virtio-mmio), que o ACPI nao descreve. Num sistema
    // com os dois, o ACPI manda nos campos arquiteturais e o FDT traz o resto —
    // por isso only_missing = 1 quando o ACPI ja rodou.
    if (neo_fwdesc_has_dtb()) {
        if (fdt_discover(g_fdt_blob, acpi_source() != 0) == 0) fdt_report();
    }

    // E6 — FATOS DE REGISTRADOR DE SISTEMA. Nao vem de ACPI nem de FDT: sao
    // leituras diretas de registradores de arquitetura, validas em qualquer
    // AArch64. Por serem fatos fisicos, nao pertencem ao perfil (politica).
    disco_read_system_facts();
    printf("[BOOT] DCache line = %u bytes (CTR_EL0.DminLine)\n",
           (unsigned)disco_dcache_line());

    // E5 — PERFIL COMO DADO. Precisa rodar AQUI: e uma leitura via Boot Services
    // (FAT), e depois do drop elas nao podem mais ser feitas. E antes da
    // pre-carga, que substitui seed_read_file pela cache de RAM.
    //
    // INVARIANTE: perfil ausente => defaults seguros => boota igual. Nunca
    // "boota ou nao". Se a CORRECAO do boot depender do perfil, o sistema virou
    // uma lista de hardware suportado com outro nome.
    profile_load();
    // P2.3: the filesystem is owned by apps/RedSea.HC (no C redsea.c).
    symbols_register("symbols_report_unresolved", (void*)symbols_report_unresolved, SYM_FUNC);
    symbols_register("symbols_unresolved_count", (void*)symbols_unresolved_count, SYM_FUNC);
    symbols_register("symbols_sic_cell", (void*)symbols_sic_cell, SYM_FUNC);
    symbols_register("symbols_var_cell", (void*)symbols_var_cell, SYM_FUNC);
    symbols_register("symbols_foreach", (void*)symbols_foreach, SYM_FUNC);

    // 6. Sovereign Handover: Read and Execute holyc/KernelInit.HC (from the ESP)
    // P3.5: keep IRQs masked for the whole .HC boot. The firmware may leave the
    // timer/GIC live; an IRQ before the scheduler (Sched.HC) is loaded would call
    // the not-yet-defined SchedOnTick. IRQs are unmasked only at Stage 7.
    disable_interrupts();

    // -----------------------------------------------------------------------
    // P1.1 / P4.3 — Pre-carga + troca de console + drop EL2->EL1.
    //
    // ORDEM OBRIGATORIA. A partir do drop nao se pode mais chamar Boot Services:
    // o firmware foi inicializado no EL de entrada (EL2 sob U-Boot/Renegade) e o
    // seu codigo, executado a partir de EL1, toma excecao e derruba o boot
    // (medido: "Resetting CPU ..." do U-Boot, 27 vezes, sempre logo apos o drop).
    //
    // Por isso, nesta ordem exata:
    //   1. pre-carregar a arvore holyc\ inteira para RAM  (ultimo uso do FAT);
    //   2. desligar o ConOut                             (ultimo uso do console UEFI);
    //   3. so entao descer para EL1.
    // -----------------------------------------------------------------------
    {
        extern int seed_preload_all(void);
        int preloaded = seed_preload_all();
        printf("[BOOT] P4.3 preload: %d arquivos carregados em RAM\r\n", preloaded);

        // Ultimo uso do console UEFI. A partir daqui o firmware nao pode mais ser
        // chamado (ver o cabecalho acima): o console passa a ser o espelho cru da
        // UART e o framebuffer, quando ativo.
        extern int g_uefi_console_enabled;
        g_uefi_console_enabled = 0;

        uint32_t drop_ret = neo_ensure_el1();
        printf("[BOOT] CurrentEL: entry=EL%u -> drop=%s -> now=EL%u\r\n",
               (unsigned)el_at_entry,
               drop_ret == 2 ? "EL2->EL1" : (drop_ret == 1 ? "no-op (already EL1)" : "?"),
               (unsigned)neo_get_current_el());
    }

    // P0.8: take the exception vectors BEFORE any .HC module runs (KernelInit.HC
    // compiles Compiler.HC, HalPlatform.HC, Timer.HC, Gic.HC ... before
    // apps/Exceptions.HC installs the Ring-0 handler). Installed here — with IRQs
    // already masked — so a fault in those first modules is reported by our own
    // tier-0 handler (ESR/ELR/FAR/SPSR) instead of the firmware's VBAR_EL1.
#if NEO_P08_VECTORS
    g_early_panic_hook = neo_early_panic;
    neo_harden_exec_env();
    install_vector_table();
    asm volatile("isb");
    neo_verify_heap_executable();
#endif

    printf("[BOOT] Sovereign Handover: Loading holyc/KernelInit.HC from the ESP...\r\n");
    static char kinit_src[65536];
    int64_t kinit_len = seed_read_file("KernelInit.HC", kinit_src, sizeof(kinit_src) - 1);
    if (kinit_len > 0) {
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
        printf("[FATAL] Could not read holyc/KernelInit.HC from the ESP!\r\n");
    }

    // 7. Halt if HolyC ever yields back to firmware
    while (1) {
        asm volatile("wfi");
    }

    return 0;
}
