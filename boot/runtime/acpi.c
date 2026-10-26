/*
 * acpi.c — E2 — descoberta de hardware por ACPI 2.0 (XSDT).
 *
 * POR QUE ACPI PRIMEIRO: e o unico caminho de descoberta cuja cadeia completa e
 * verificavel hoje. O AAVMF entrega ACPI 2.0 e roda o gate inteiro — entao da
 * para provar "descobre -> preenche a HAL -> boota com os valores descobertos ->
 * gate verde". O FDT so roda sob U-Boot, onde o boot completo esta bloqueado
 * pela corrupcao de heap no drop EL2; la a validacao seria so do parsing.
 *
 * Medido no E1:
 *   QEMU + AAVMF  -> ACPI 2.0 (RSDP revision 2). NAO entrega DTB.
 *   QEMU + U-Boot -> DTB. NAO entrega ACPI.
 *
 * O que este modulo extrai, e de onde:
 *   XSDT -> MADT ("APIC") : GICD (tipo 0x0C), GICR (0x0E), GICC (0x0B -> CPUs)
 *           SPCR          : base E TIPO da UART (PL011 x 16550 x SBSA)
 *           GTDT          : PPIs do timer (virtual e fisico)
 *
 * REGRA DE INTEGRIDADE ACPI: a soma em uint8_t de todos os bytes de uma tabela
 * valida (0 .. length-1) e ZERO. Toda tabela passa por acpi_checksum() antes de
 * ser interpretada.
 *
 * ARMADILHA EVITADA: as subestruturas do MADT tem comprimento VARIAVEL e
 * cresceram entre versoes do ACPI. Avancar por sizeof(struct) le lixo; avancar
 * pelo campo `length` da propria subestrutura e o unico jeito correto. Por isso
 * aqui os structs sao PARCIAIS (so os campos usados) e o passo e sempre
 * `length`.
 */

#include <uefi.h>
#include "discovery.h"

/* --------------------------------------------------------------------------
 * Estruturas (parciais de proposito — ver ARMADILHA acima)
 * ------------------------------------------------------------------------ */

typedef struct __attribute__((packed)) {
    char     signature[8];      /* "RSD PTR " */
    uint8_t  checksum;
    char     oem_id[6];
    uint8_t  revision;          /* 2 = ACPI 2.0+ (tem XSDT de 64 bits) */
    uint32_t rsdt_address;      /* ACPI 1.0 (32 bits) */
    uint32_t length;
    uint64_t xsdt_address;      /* ACPI 2.0+ (64 bits) */
    uint8_t  extended_checksum;
    uint8_t  reserved[3];
} acpi_rsdp_t;

typedef struct __attribute__((packed)) {
    char     signature[4];
    uint32_t length;
    uint8_t  revision;
    uint8_t  checksum;
    char     oem_id[6];
    char     oem_table_id[8];
    uint32_t oem_revision;
    uint32_t creator_id;
    uint32_t creator_revision;
} acpi_header_t;

/* MADT: cabecalho + estes dois campos, depois subestruturas variaveis. */
typedef struct __attribute__((packed)) {
    acpi_header_t header;
    uint32_t local_interrupt_controller_address;
    uint32_t flags;
} acpi_madt_t;

/* Subestrutura GICC (tipo 0x0B): CPUs. Parcial ate `mpidr`. */
typedef struct __attribute__((packed)) {
    uint8_t  type;
    uint8_t  length;
    uint16_t reserved;
    uint32_t cpu_interface_num;
    uint32_t acpi_processor_uid;
    uint32_t flags;                 /* bit 0 = habilitado */
    uint32_t parking_protocol_version;
    uint32_t performance_interrupt_gsiv;
    uint64_t parked_address;
    uint64_t physical_base_address; /* GICC base (GICv2) */
    uint64_t gicv_base_address;
    uint64_t gich_base_address;
    uint32_t vgic_maintenance_interrupt;
    uint64_t gicr_base_address;     /* GICR base (GICv3) */
    uint64_t mpidr;
} madt_gicc_t;

/* Subestrutura GICD (tipo 0x0C) */
typedef struct __attribute__((packed)) {
    uint8_t  type;
    uint8_t  length;
    uint16_t reserved;
    uint32_t gic_id;
    uint64_t physical_base_address; /* GICD base */
    uint32_t system_vector_base;
    uint8_t  gic_version;           /* 0=nao declarada, 2, 3, 4 */
    uint8_t  reserved2[3];
} madt_gicd_t;

/* Subestrutura GICR (tipo 0x0E) */
typedef struct __attribute__((packed)) {
    uint8_t  type;
    uint8_t  length;
    uint16_t reserved;
    uint64_t discovery_range_base_address;  /* GICR base */
    uint32_t discovery_range_length;
} madt_gicr_t;

/* SPCR: a GAS de 12 bytes comeca em 36+4 = 40; o endereco em +44. */
typedef struct __attribute__((packed)) {
    acpi_header_t header;
    uint8_t  interface_type;    /* 0x03 = ARM PL011, 0x00 = 16550, 0x0E/0x0F = SBSA */
    uint8_t  reserved[3];
    uint8_t  gas_address_space_id;
    uint8_t  gas_bit_width;
    uint8_t  gas_bit_offset;
    uint8_t  gas_access_size;
    uint64_t base_address;      /* UART base */
} acpi_spcr_t;

/* GTDT: offsets 48/56/64 = GSIV do timer seguro EL1, nao-seguro EL1, virtual. */
typedef struct __attribute__((packed)) {
    acpi_header_t header;
    uint64_t counter_control_base;
    uint32_t reserved;
    uint32_t secure_el1_timer_gsiv;
    uint32_t secure_el1_timer_flags;
    uint32_t non_secure_el1_timer_gsiv;   /* PPI do timer fisico (tipico 30) */
    uint32_t non_secure_el1_timer_flags;
    uint32_t virtual_timer_gsiv;          /* PPI do timer virtual (tipico 27) */
    uint32_t virtual_timer_flags;
} acpi_gtdt_t;

/* --------------------------------------------------------------------------
 * Resultado da descoberta — o contrato compartilhado com o FDT (E4).
 * Ver boot/runtime/discovery.h: um so destino para os dois produtores.
 * A definicao fica aqui; o FDT escreve nesta mesma instancia.
 * ------------------------------------------------------------------------ */

discovered_platform_t g_discovered_plat;

/* Acessores para o HolyC e para a HAL. */
/* ATENCAO A NOMENCLATURA: apesar do prefixo, TODOS estes acessores devolvem o
 * resultado UNIFICADO da descoberta — nao importa se veio do ACPI (source=1) ou
 * do Device Tree (source=2). O prefixo e historico (nasceram no E2, quando so
 * havia ACPI) e vale corrigir para disco_* quando houver oportunidade. */
uint64_t acpi_gicd_base(void)   { return g_discovered_plat.gicd_base; }
uint64_t acpi_gicr_base(void)   { return g_discovered_plat.gicr_base; }
uint64_t acpi_gicc_base(void)   { return g_discovered_plat.gicc_base; }
uint32_t acpi_source(void)      { return g_discovered_plat.source; }
/* VirtIO: SO o FDT fornece (o ACPI nao descreve dispositivos de placa). */
uint64_t acpi_virtio_base(void)   { return g_discovered_plat.virtio_base; }
uint32_t acpi_virtio_stride(void) { return g_discovered_plat.virtio_stride; }
uint32_t acpi_virtio_slots(void)  { return g_discovered_plat.virtio_slots; }
uint64_t acpi_uart_base(void)   { return g_discovered_plat.uart_base; }
uint32_t acpi_uart_type(void)   { return g_discovered_plat.uart_type; }
uint32_t acpi_gic_version(void) { return g_discovered_plat.gic_version; }
uint32_t acpi_timer_virt(void)  { return g_discovered_plat.timer_virt_irq; }
uint32_t acpi_timer_phys(void)  { return g_discovered_plat.timer_phys_irq; }
uint32_t acpi_cpu_count(void)   { return g_discovered_plat.cpu_count; }

/* --------------------------------------------------------------------------
 * Integridade
 * ------------------------------------------------------------------------ */

static int acpi_checksum(const void *tbl, uint32_t len) {
    const uint8_t *p = (const uint8_t*)tbl;
    uint8_t sum = 0;
    for (uint32_t i = 0; i < len; i++) sum = (uint8_t)(sum + p[i]);
    return sum == 0;
}

static int sig_is(const char *a, const char *b) {
    for (int i = 0; i < 4; i++) if (a[i] != b[i]) return 0;
    return 1;
}

static const char *uart_type_name(uint32_t t) {
    switch (t) {
        case 1: return "PL011";
        case 2: return "16550";
        case 3: return "SBSA";
        default: return "?";
    }
}

/* --------------------------------------------------------------------------
 * Parsers por tabela
 * ------------------------------------------------------------------------ */

static void parse_madt(const acpi_header_t *h) {
    const uint8_t *base = (const uint8_t*)h;
    uint32_t off = sizeof(acpi_madt_t);   /* 44: fim do cabecalho + 8 */

    if (!acpi_checksum(h, h->length)) {
        printf("[ACPI] MADT: CHECKSUM INVALIDO — ignorando\n");
        return;
    }

    while (off + 2 <= h->length) {
        const uint8_t *sub = base + off;
        uint8_t type   = sub[0];
        uint8_t length = sub[1];

        /* length == 0 trava o laco para sempre: e corrupcao, nao dado. */
        if (length < 2 || off + length > h->length) break;

        if (type == 0x0B && length >= sizeof(madt_gicc_t)) {
            const madt_gicc_t *g = (const madt_gicc_t*)sub;
            if (g->flags & 1) g_discovered_plat.cpu_count++;
            if (!g_discovered_plat.gicc_base && g->physical_base_address)
                g_discovered_plat.gicc_base = g->physical_base_address;
            if (!g_discovered_plat.gicr_base && g->gicr_base_address)
                g_discovered_plat.gicr_base = g->gicr_base_address;
        } else if (type == 0x0C && length >= sizeof(madt_gicd_t)) {
            const madt_gicd_t *d = (const madt_gicd_t*)sub;
            if (d->physical_base_address)
                g_discovered_plat.gicd_base = d->physical_base_address;
            if (d->gic_version)
                g_discovered_plat.gic_version = d->gic_version;
        } else if (type == 0x0E && length >= sizeof(madt_gicr_t)) {
            const madt_gicr_t *r = (const madt_gicr_t*)sub;
            if (r->discovery_range_base_address)
                g_discovered_plat.gicr_base = r->discovery_range_base_address;
        }

        off += length;   /* SEMPRE pelo length — ver ARMADILHA no cabecalho */
    }
}

static void parse_spcr(const acpi_header_t *h) {
    if (!acpi_checksum(h, h->length)) {
        printf("[ACPI] SPCR: CHECKSUM INVALIDO — ignorando\n");
        return;
    }
    const acpi_spcr_t *s = (const acpi_spcr_t*)h;
    if (s->base_address) g_discovered_plat.uart_base = s->base_address;

    switch (s->interface_type) {
        case 0x03: g_discovered_plat.uart_type = 1; break;  /* ARM PL011 */
        case 0x00: g_discovered_plat.uart_type = 2; break;  /* 16550 */
        case 0x0E:
        case 0x0F: g_discovered_plat.uart_type = 3; break;  /* ARM SBSA */
        default:   g_discovered_plat.uart_type = 0; break;
    }
}

static void parse_gtdt(const acpi_header_t *h) {
    if (!acpi_checksum(h, h->length)) {
        printf("[ACPI] GTDT: CHECKSUM INVALIDO — ignorando\n");
        return;
    }
    const acpi_gtdt_t *g = (const acpi_gtdt_t*)h;
    g_discovered_plat.timer_phys_irq = g->non_secure_el1_timer_gsiv;
    g_discovered_plat.timer_virt_irq = g->virtual_timer_gsiv;
}

/* --------------------------------------------------------------------------
 * XSDT (ACPI 2.0+, 64 bits) e RSDT (ACPI 1.0, 32 bits)
 * ------------------------------------------------------------------------ */

static void walk_entries(const void *table, uint32_t hdr_len, uint32_t length,
                         int wide64) {
    const uint8_t *p = (const uint8_t*)table;
    uint32_t entry = wide64 ? 8 : 4;

    for (uint32_t off = hdr_len; off + entry <= length; off += entry) {
        uint64_t addr = wide64
            ? *(const uint64_t*)(p + off)
            : (uint64_t)(*(const uint32_t*)(p + off));
        if (!addr) continue;

        const acpi_header_t *h = (const acpi_header_t*)(uintptr_t)addr;
        if (h->length < sizeof(acpi_header_t)) continue;

        if      (sig_is(h->signature, "APIC")) parse_madt(h);
        else if (sig_is(h->signature, "SPCR")) parse_spcr(h);
        else if (sig_is(h->signature, "GTDT")) parse_gtdt(h);
    }
}

int acpi_discover(void *rsdp_ptr) {
    if (!rsdp_ptr) return -1;
    const acpi_rsdp_t *rsdp = (const acpi_rsdp_t*)rsdp_ptr;

    /* Assinatura ja validada pelo E1, mas nao custa reconferir aqui. */
    const char *sig = "RSD PTR ";
    for (int i = 0; i < 8; i++) if (rsdp->signature[i] != sig[i]) return -1;

    g_discovered_plat.source = 1;   /* ACPI */

    if (rsdp->revision >= 2 && rsdp->xsdt_address) {
        const acpi_header_t *xsdt = (const acpi_header_t*)(uintptr_t)rsdp->xsdt_address;
        if (!sig_is(xsdt->signature, "XSDT")) {
            printf("[ACPI] XSDT esperado em 0x%llX, achei '%.4s'\n",
                   (unsigned long long)rsdp->xsdt_address, xsdt->signature);
            return -1;
        }
        if (!acpi_checksum(xsdt, xsdt->length)) {
            printf("[ACPI] XSDT: CHECKSUM INVALIDO\n");
            return -1;
        }
        printf("[ACPI] XSDT @ 0x%llX  (%u entradas de 64 bits)\n",
               (unsigned long long)rsdp->xsdt_address,
               (unsigned)((xsdt->length - sizeof(acpi_header_t)) / 8));
        walk_entries(xsdt, sizeof(acpi_header_t), xsdt->length, 1);
        return 0;
    }

    /* Fallback ACPI 1.0: RSDT com ponteiros de 32 bits. */
    if (rsdp->rsdt_address) {
        const acpi_header_t *rsdt = (const acpi_header_t*)(uintptr_t)rsdp->rsdt_address;
        if (sig_is(rsdt->signature, "RSDT") && acpi_checksum(rsdt, rsdt->length)) {
            printf("[ACPI] RSDT (1.0) @ 0x%llX\n",
                   (unsigned long long)rsdp->rsdt_address);
            walk_entries(rsdt, sizeof(acpi_header_t), rsdt->length, 0);
            return 0;
        }
    }
    return -1;
}

void acpi_report(void) {
    printf("[ACPI] Descoberta concluida:\n");
    printf("[ACPI]   GICD : 0x%016llX  (versao %u)\n",
           (unsigned long long)g_discovered_plat.gicd_base,
           (unsigned)g_discovered_plat.gic_version);
    printf("[ACPI]   GICR : 0x%016llX\n",
           (unsigned long long)g_discovered_plat.gicr_base);
    printf("[ACPI]   GICC : 0x%016llX\n",
           (unsigned long long)g_discovered_plat.gicc_base);
    printf("[ACPI]   UART : 0x%016llX  (%s)\n",
           (unsigned long long)g_discovered_plat.uart_base,
           uart_type_name(g_discovered_plat.uart_type));
    printf("[ACPI]   Timer: Virt PPI %u, Phys PPI %u\n",
           (unsigned)g_discovered_plat.timer_virt_irq,
           (unsigned)g_discovered_plat.timer_phys_irq);
    printf("[ACPI]   CPUs : %u core(s) online\n",
           (unsigned)g_discovered_plat.cpu_count);
}
