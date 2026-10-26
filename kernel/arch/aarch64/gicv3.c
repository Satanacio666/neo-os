/*
 * gicv3.c — P5.2 — interface de system registers do GICv3 (ICC_*_EL1).
 *
 * POR QUE EM C: o HolyC nao tem mnemonicos para os registradores de sistema do
 * GICv3 (S3_0_C12_C12_*). Sem eles, o driver Gic.HC so sabe falar com o GICv2
 * por MMIO — e num SoC GICv3 (Snapdragon 860) a primeira escrita em
 * GICC_DEFAULT_BASE (0x08010000) toma Data Abort: medido como
 * `FAR_EL1 = 0x08010004` (= GICC_DEFAULT_BASE + 0x004 = GICC_PMR) no QEMU com
 * `-M virt,gic-version=3`.
 *
 * Estas funcoes sao registradas como simbolos em boot/main.c e chamadas pelo
 * apps/Gic.HC. Todas operam apenas registradores de sistema — nenhum MMIO.
 */

#include <uefi.h>

#define ICC_SRE_EL1     "s3_0_c12_c12_5"
#define ICC_PMR_EL1     "s3_0_c4_c6_0"
#define ICC_IAR1_EL1    "s3_0_c12_c12_0"
#define ICC_EOIR1_EL1   "s3_0_c12_c12_1"
#define ICC_IGRPEN1_EL1 "s3_0_c12_c12_7"
#define ICC_CTLR_EL1    "s3_0_c12_c12_4"
#define ICC_SRE_EL2     "s3_4_c12_c9_5"

uint64_t gicv3_sre_get(void) {
    uint64_t v = 0;
    __asm__ volatile("mrs %0, " ICC_SRE_EL1 : "=r"(v));
    return v;
}

/* Habilita SRE em EL1 e devolve o valor lido de volta (para o caller conferir). */
uint64_t gicv3_sre_enable(void) {
    uint64_t v = 0;
    __asm__ volatile("mrs %0, " ICC_SRE_EL1 : "=r"(v));
    v |= 1ULL;                      /* SRE */
    __asm__ volatile("msr " ICC_SRE_EL1 ", %0" :: "r"(v));
    __asm__ volatile("isb" ::: "memory");
    return gicv3_sre_get();
}

/* ICC_SRE_EL2: precisa de SRE=1 e Enable=1 antes de EL1 tocar em ICC_*_EL1. */
uint64_t gicv3_sre_el2_enable(void) {
    uint64_t v = 0;
    __asm__ volatile("mrs %0, " ICC_SRE_EL2 : "=r"(v));
    v |= 1ULL;                      /* SRE    (bit 0) */
    v |= 8ULL;                      /* Enable (bit 3) */
    __asm__ volatile("msr " ICC_SRE_EL2 ", %0" :: "r"(v));
    __asm__ volatile("isb" ::: "memory");
    return v;
}

void gicv3_pmr_set(uint64_t v) {
    __asm__ volatile("msr " ICC_PMR_EL1 ", %0" :: "r"(v));
    __asm__ volatile("isb" ::: "memory");
}

uint64_t gicv3_pmr_get(void) {
    uint64_t v = 0;
    __asm__ volatile("mrs %0, " ICC_PMR_EL1 : "=r"(v));
    return v;
}

uint64_t gicv3_ctlr_get(void) {
    uint64_t v = 0;
    __asm__ volatile("mrs %0, " ICC_CTLR_EL1 : "=r"(v));
    return v;
}

void gicv3_ctlr_set(uint64_t v) {
    __asm__ volatile("msr " ICC_CTLR_EL1 ", %0" :: "r"(v));
    __asm__ volatile("isb" ::: "memory");
}

uint64_t gicv3_iar1(void) {
    uint64_t v = 0;
    __asm__ volatile("mrs %0, " ICC_IAR1_EL1 : "=r"(v));
    return v;
}

void gicv3_eoir1(uint64_t v) {
    __asm__ volatile("msr " ICC_EOIR1_EL1 ", %0" :: "r"(v));
}

void gicv3_igrpen1_set(uint64_t v) {
    __asm__ volatile("msr " ICC_IGRPEN1_EL1 ", %0" :: "r"(v));
    __asm__ volatile("isb" ::: "memory");
}

uint64_t gicv3_igrpen1_get(void) {
    uint64_t v = 0;
    __asm__ volatile("mrs %0, " ICC_IGRPEN1_EL1 : "=r"(v));
    return v;
}

/* ---------------------------------------------------------------------------
 * P5.2 — Sonda de MMIO com recuperacao.
 *
 * Descobrir a versao do GIC exige ler GICD_PIDR2 (offset 0xFFE8). No GICv2 do
 * QEMU o distribuidor e mapeado em apenas 4 KB (0x08000000..0x08000FFF), entao
 * 0xFFE8 cai FORA da regiao e a leitura toma Data Abort — medido:
 *   EC=0x25 Data Abort · FAR_EL1 = 0x0800FFE8
 *
 * Em vez de derrubar o boot, o handler tier-0 (kernel/arch/aarch64/vectors.S,
 * early_sync_panic) detecta g_mmio_probe_active, marca g_mmio_probe_faulted,
 * avanca ELR_EL1 em 4 e retoma. O load tem de ser UMA instrucao de 4 bytes —
 * por isso o acesso e por `volatile uint32_t*` puro.
 * ------------------------------------------------------------------------- */

volatile int g_mmio_probe_active  = 0;
volatile int g_mmio_probe_faulted = 0;

uint32_t neo_probe_mmio_read32(uint64_t addr, int *faulted) {
    uint32_t v = 0;
    g_mmio_probe_faulted = 0;
    g_mmio_probe_active  = 1;
    __asm__ volatile("dmb sy" ::: "memory");
    v = *(volatile uint32_t*)addr;      /* uma unica ldr w — ver acima */
    __asm__ volatile("dmb sy" ::: "memory");
    g_mmio_probe_active = 0;
    if (faulted) *faulted = g_mmio_probe_faulted;
    return v;
}

/* ICC_BPR1_EL1 — binary point do Grupo 1. Sem zerar isto, o agrupamento de
 * prioridade preempca de forma inesperada entre PPIs/SPIs. */
void gicv3_bpr1_set(uint64_t v) {
    __asm__ volatile("msr s3_0_c12_c12_3, %0" :: "r"(v));
    __asm__ volatile("isb" ::: "memory");
}

uint64_t gicv3_bpr1_get(void) {
    uint64_t v = 0;
    __asm__ volatile("mrs %0, s3_0_c12_c12_3" : "=r"(v));
    return v;
}

/* ---------------------------------------------------------------------------
 * P1.2 — Identidade do silicio, para o HolyC escolher a plataforma.
 *
 * MIDR_EL1: [31:24] implementer, [23:20] variant, [19:16] architecture,
 * [15:4] partnum, [3:0] revision.
 *
 * Valores medidos/verificados:
 *   QEMU virt, -cpu cortex-a72 : implementer 0x41 (ARM), part 0xD08
 *   POCO X3 Pro (SM8150/vayu)  : implementer 0x51 (Qualcomm), part 0x804/0x805
 *   APM X-Gene (CloudLab m400) : implementer 0x50, part 0x000
 *
 * RESSALVA HONESTA: 0x41/0xD08 tambem e o Cortex-A72 real (RPi4, RK3399 big).
 * Para esses, MIDR sozinho nao distingue de QEMU. Como o QEMU e o alvo de
 * desenvolvimento e os alvos de hardware usam outros implementers, a escolha
 * pratica e: 0x51 -> SM8150, resto -> QEMU virt. Um discriminador melhor
 * (DTB/ACPI ou FirmwareVendor) fica registrado como pendencia.
 * ------------------------------------------------------------------------- */

uint64_t neo_midr_el1(void) {
    uint64_t v = 0;
    __asm__ volatile("mrs %0, midr_el1" : "=r"(v));
    return v;
}

uint64_t neo_midr_implementer(void) {
    return (neo_midr_el1() >> 24) & 0xFFULL;
}

uint64_t neo_midr_partnum(void) {
    return (neo_midr_el1() >> 4) & 0xFFFULL;
}
