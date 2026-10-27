/*
 * fdt.c — E4 — descoberta de hardware por Device Tree (FDT).
 *
 * Segundo produtor do MESMO contrato (boot/runtime/discovery.h). Nao inventa
 * estrutura nova: preenche os campos que o ACPI ja preenche, e acrescenta o que
 * o ACPI NAO tem — dispositivos de PLACA (virtio-mmio), que nao aparecem em
 * ACPI nenhuma porque sao a topologia desta placa, nao arquitetura ARM.
 *
 * Medido no E1: QEMU+U-Boot entrega DTB (FDT v17, 8192 B) e NAO entrega ACPI;
 * QEMU+AAVMF entrega ACPI e nao entrega DTB. Por isso os dois caminhos existem
 * e se completam: ACPI primeiro (autoridade quando presente), FDT depois
 * preenchendo o que faltar.
 *
 * REGRAS DO FORMATO (todas big-endian):
 *   - Cabecalho de 40 bytes: magic d00dfeed, totalsize, off_dt_struct,
 *     off_dt_strings, off_mem_rsvmap, version, last_comp_version, boot_cpuid,
 *     size_dt_strings, size_dt_struct.
 *   - Bloco de estrutura: tokens de 32 bits, todos alinhados em 4 bytes.
 *       1 BEGIN_NODE -> nome (NUL, com padding ate 4)
 *       2 END_NODE
 *       3 PROP       -> u32 len, u32 nameoff, valor (padding ate 4)
 *       4 NOP
 *       9 END
 *   - Nomes de propriedade vem da tabela de strings em off_dt_strings+nameoff.
 *
 * ARMADILHA EVITADA: o `reg` de um no e interpretado com o #address-cells e o
 * #size-cells DO PAI, nao do proprio no. Por isso o parser mantem uma pilha de
 * contexto por nivel, herdada na entrada do no.
 *
 * ARMADILHA EVITADA 2: o DT especifica o PPI do timer como numero RELATIVO
 * (offset a partir de 16), nao como INTID. `<1 11 ...>` e o timer virtual
 * => INTID 27. Esquecer o +16 daria 11 e o handler nunca dispararia.
 */

#include <uefi.h>
#include "discovery.h"

#define FDT_MAGIC          0xd00dfeedu
#define FDT_BEGIN_NODE     0x1u
#define FDT_END_NODE       0x2u
#define FDT_PROP           0x3u
#define FDT_NOP            0x4u
#define FDT_END            0x9u

#define FDT_MAX_DEPTH      12
#define FDT_COMPAT_MAX     80

/* --------------------------------------------------------------------------
 * Leitura big-endian sem risco de desalinhamento (memcpy + bswap).
 * ------------------------------------------------------------------------ */

static uint32_t be32(const uint8_t *p) {
    uint32_t v;
    __builtin_memcpy(&v, p, 4);
    return __builtin_bswap32(v);
}

static const uint8_t *align4p(const uint8_t *p) {
    return (const uint8_t*)(((uintptr_t)p + 3u) & ~(uintptr_t)3u);
}

static int str_eq(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a == 0 && *b == 0;
}

/* Le `ncells` celulas big-endian a partir da celula `cell_off`. */
static uint64_t read_cells(const uint8_t *val, uint32_t len,
                           uint32_t cell_off, uint32_t ncells) {
    uint64_t v = 0;
    for (uint32_t i = 0; i < ncells; i++) {
        uint32_t off = (cell_off + i) * 4u;
        if (off + 4u > len) return 0;
        v = (v << 32) | (uint64_t)be32(val + off);
    }
    return v;
}

/* --------------------------------------------------------------------------
 * Contexto por nivel (pilha de nos)
 * ------------------------------------------------------------------------ */

typedef struct {
    uint32_t addr_cells;
    uint32_t size_cells;
    char     compat[FDT_COMPAT_MAX];
    /* Valores colhidos DURANTE o no, aplicados so no END_NODE.
     *
     * MOTIVO (medido, nao suposto): no DTB do QEMU o `compatible` vem DEPOIS de
     * `reg`:
     *     virtio_mmio@a000000 {
     *         interrupts = <0x00 0x10 0x01>;
     *         reg        = <0x00 0xa000000 0x00 0x200>;
     *         compatible = "virtio,mmio";
     *     };
     * Aplicar no proprio `reg` consultaria um compatible ainda VAZIO e nao
     * casaria dispositivo nenhum — foi exatamente o que aconteceu na primeira
     * versao deste parser. */
    uint64_t reg0, reg1;
    uint32_t int_phys, int_virt;
    int      has_reg;
    int      has_int;
} fdt_level_t;

static fdt_level_t lv[FDT_MAX_DEPTH];

static uint32_t g_fdt_cpus      = 0;
static uint32_t g_fdt_virtio_n  = 0;

/* --------------------------------------------------------------------------
 * Aplicacao dos dispositivos encontrados
 * ------------------------------------------------------------------------ */

static void apply_gic(const char *compat, uint64_t addr0, uint64_t addr1) {
    if (str_eq(compat, "arm,gic-v3")) {
        g_discovered_plat.gicd_base   = addr0;
        g_discovered_plat.gicr_base   = addr1;
        g_discovered_plat.gic_version = 3;
        g_discovered_plat.gicc_base   = 0;      /* GICv3 nao tem GICC por MMIO */
    } else if (str_eq(compat, "arm,cortex-a15-gic") || str_eq(compat, "arm,gic-400")) {
        g_discovered_plat.gicd_base   = addr0;
        g_discovered_plat.gicc_base   = addr1;
        g_discovered_plat.gic_version = 2;
        g_discovered_plat.gicr_base   = 0;
    }
}

static void apply_uart(const char *compat, uint64_t addr) {
    if (str_eq(compat, "arm,pl011")) {
        g_discovered_plat.uart_base = addr;
        g_discovered_plat.uart_type = 1;
    } else if (str_eq(compat, "ns16550a") || str_eq(compat, "ns16550") ||
               str_eq(compat, "snps,dw-apb-uart")) {
        g_discovered_plat.uart_base = addr;
        g_discovered_plat.uart_type = 2;
    }
}

static void apply_virtio(uint64_t addr) {
    if (!g_discovered_plat.virtio_base) {
        g_discovered_plat.virtio_base = addr;
    } else if (addr > g_discovered_plat.virtio_base) {
        /* MENOR delta positivo e o stride real. Pegar o delta do ultimo no daria
         * (n-1) x stride — foi o que aconteceu na primeira versao: 0x3E00 em vez
         * de 0x200 com 32 nos. */
        uint32_t stride = (uint32_t)(addr - g_discovered_plat.virtio_base);
        if (stride && (g_discovered_plat.virtio_stride == 0 ||
                       stride < g_discovered_plat.virtio_stride))
            g_discovered_plat.virtio_stride = stride;
    }
    g_fdt_virtio_n++;
}

/* --------------------------------------------------------------------------
 * Parser
 * ------------------------------------------------------------------------ */

int fdt_discover(void *blob, int only_missing) {
    if (!blob) return -1;
    const uint8_t *base = (const uint8_t*)blob;

    if (be32(base) != FDT_MAGIC) return -1;

    uint32_t totalsize    = be32(base + 4);
    uint32_t off_struct   = be32(base + 8);
    uint32_t off_strings  = be32(base + 12);
    uint32_t size_strings = be32(base + 32);
    uint32_t size_struct  = be32(base + 36);
    uint32_t version      = be32(base + 20);

    if (totalsize < 40 || off_struct + size_struct > totalsize) return -1;
    if (off_strings + size_strings > totalsize) return -1;

    /* Limpa so o que este parser produz — se only_missing, preserva o ACPI. */
    if (!only_missing) {
        g_discovered_plat.gicd_base = g_discovered_plat.gicr_base = 0;
        g_discovered_plat.gicc_base = 0;
        g_discovered_plat.gic_version = 0;
        g_discovered_plat.uart_base = 0;
        g_discovered_plat.uart_type = 0;
        g_discovered_plat.timer_virt_irq = g_discovered_plat.timer_phys_irq = 0;
        g_discovered_plat.cpu_count = 0;
    }
    g_discovered_plat.virtio_base = 0;
    g_discovered_plat.virtio_slots = 0;
    g_discovered_plat.virtio_stride = 0;

    /* Defaults do spec para a raiz: #address-cells = 2, #size-cells = 1. */
    for (int i = 0; i < FDT_MAX_DEPTH; i++) {
        lv[i].addr_cells = 2;
        lv[i].size_cells = 1;
        lv[i].compat[0]  = 0;
    }

    const uint8_t *p   = base + off_struct;
    const uint8_t *end = p + size_struct;
    int depth = 0;
    g_fdt_cpus = 0;
    g_fdt_virtio_n = 0;

    while (p + 4 <= end) {
        uint32_t tok = be32(p);
        p += 4;

        if (tok == FDT_BEGIN_NODE) {
            depth++;
            if (depth >= FDT_MAX_DEPTH) return -1;   /* malformado: aborta */
            /* Herda o contexto do pai — `reg` usa as celulas DO PAI. */
            lv[depth].addr_cells = lv[depth - 1].addr_cells;
            lv[depth].size_cells = lv[depth - 1].size_cells;
            lv[depth].compat[0]  = 0;
            lv[depth].has_reg    = 0;
            lv[depth].has_int    = 0;
            lv[depth].reg0 = lv[depth].reg1 = 0;
            lv[depth].int_phys = lv[depth].int_virt = 0;

            const char *name = (const char*)p;
            if (name[0] == 'c' && name[1] == 'p' && name[2] == 'u' && name[3] == '@')
                g_fdt_cpus++;

            while (p < end && *p) p++;   /* nome termina em NUL */
            p++;
            p = align4p(p);

        } else if (tok == FDT_END_NODE) {
            if (depth > 0) {
                /* Aplica o que foi colhido. AQUI o compatible ja esta completo,
                 * nao importa a ordem em que os campos vieram no DTB. */
                const char *c = lv[depth].compat;
                if (c[0]) {
                    if (lv[depth].has_reg) {
                        apply_gic(c, lv[depth].reg0, lv[depth].reg1);
                        apply_uart(c, lv[depth].reg0);
                        if (str_eq(c, "virtio,mmio")) apply_virtio(lv[depth].reg0);
                    }
                    if (lv[depth].has_int && str_eq(c, "arm,armv8-timer")) {
                        g_discovered_plat.timer_phys_irq = lv[depth].int_phys;
                        g_discovered_plat.timer_virt_irq = lv[depth].int_virt;
                    }
                }
                if (depth == 1) {
                    /* E5 — o no raiz e o nivel 1; o primeiro item do compatible
                     * dele e a identidade (ex: "linux,dummy-virt"). */
                    if (lv[1].compat[0]) disco_set_identity(lv[1].compat);
                }
                depth--;
            }

        } else if (tok == FDT_PROP) {
            if (p + 8 > end) break;
            uint32_t len     = be32(p);
            uint32_t nameoff = be32(p + 4);
            p += 8;
            const uint8_t *val = p;
            if (p + len > end) break;

            const char *nm = (const char*)(base + off_strings + nameoff);

            if (str_eq(nm, "compatible")) {
                int i = 0;
                while (i < (int)len && val[i] && i < FDT_COMPAT_MAX - 1) {
                    lv[depth].compat[i] = (char)val[i];
                    i++;
                }
                lv[depth].compat[i] = 0;

            } else if (str_eq(nm, "#address-cells") && len >= 4) {
                lv[depth].addr_cells = be32(val);

            } else if (str_eq(nm, "#size-cells") && len >= 4) {
                lv[depth].size_cells = be32(val);

            } else if (str_eq(nm, "reg") && depth > 0) {
                uint32_t ac = lv[depth - 1].addr_cells;
                uint32_t sc = lv[depth - 1].size_cells;
                if (ac == 0 || ac > 4) ac = 2;
                if (sc == 0 || sc > 4) sc = 1;
                /* COLHE, nao aplica: o compatible pode vir depois (ver fdt_level_t). */
                lv[depth].reg0 = read_cells(val, len, 0, ac);
                lv[depth].reg1 = (len >= (ac + sc) * 4u + ac * 4u)
                                 ? read_cells(val, len, ac + sc, ac) : 0;
                lv[depth].has_reg = 1;

            } else if (str_eq(nm, "interrupts")) {
                /* O DT da o PPI como numero RELATIVO a 16; o INTID e 16 + numero.
                 * Layout: 4 interrupcoes de 3 celulas [tipo, numero, flags]. */
                if (len >= 48) {
                    lv[depth].int_phys = 16 + be32(val + 16);   /* non-secure EL1 */
                    lv[depth].int_virt = 16 + be32(val + 28);   /* virtual */
                    lv[depth].has_int  = 1;
                }
            }

            p += len;
            p = align4p(p);

        } else if (tok == FDT_NOP) {
            continue;
        } else if (tok == FDT_END) {
            break;
        } else {
            break;   /* token desconhecido: aborta em vez de adivinhar */
        }
    }

    if (!only_missing) g_discovered_plat.cpu_count = g_fdt_cpus;
    g_discovered_plat.virtio_slots = g_fdt_virtio_n;
    g_discovered_plat.source = 2;

    printf("[FDT] version=%u totalsize=%u\n", (unsigned)version, (unsigned)totalsize);
    return 0;
}

void fdt_report(void) {
    printf("[FDT] Descoberta concluida:\n");
    printf("[FDT]   GICD : 0x%016llX  (versao %u)\n",
           (unsigned long long)g_discovered_plat.gicd_base,
           (unsigned)g_discovered_plat.gic_version);
    printf("[FDT]   GICR : 0x%016llX\n",
           (unsigned long long)g_discovered_plat.gicr_base);
    printf("[FDT]   GICC : 0x%016llX\n",
           (unsigned long long)g_discovered_plat.gicc_base);
    printf("[FDT]   UART : 0x%016llX  (tipo %u)\n",
           (unsigned long long)g_discovered_plat.uart_base,
           (unsigned)g_discovered_plat.uart_type);
    printf("[FDT]   Timer: Virt %u, Phys %u\n",
           (unsigned)g_discovered_plat.timer_virt_irq,
           (unsigned)g_discovered_plat.timer_phys_irq);
    printf("[FDT]   CPUs : %u\n", (unsigned)g_discovered_plat.cpu_count);
    printf("[FDT]   VirtIO: base 0x%016llX stride 0x%X (%u no(s))\n",
           (unsigned long long)g_discovered_plat.virtio_base,
           (unsigned)g_discovered_plat.virtio_stride,
           (unsigned)g_discovered_plat.virtio_slots);
}
