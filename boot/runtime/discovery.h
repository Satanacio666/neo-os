/*
 * discovery.h — E3/E4 — o contrato unico da descoberta de hardware.
 *
 * Dois produtores preenchem esta MESMA estrutura:
 *   acpi.c (E2) -> source = 1, a partir do XSDT/MADT/SPCR/GTDT
 *   fdt.c  (E4) -> source = 2, a partir do Device Tree
 *
 * Um so destino e o que permite a HAL ter UM caminho de consumo, ja validado
 * pelo teste de mutacao do E3. O FDT nao precisou de contrato novo — so de
 * preencher os mesmos campos.
 *
 * ESCOPO DE CADA UM (medido, nao suposto):
 *   ACPI descreve dispositivos ARQUITETURAIS: GIC, UART, timer, CPUs.
 *   ACPI NAO descreve dispositivos de PLACA — virtio-mmio nao aparece em ACPI.
 *   O FDT descreve os dois: e a arvore inteira da placa.
 * Por isso a descoberta roda ACPI primeiro e o FDT depois preenchendo o que
 * faltar; num sistema com os dois, o virtio so pode vir do FDT.
 */

#ifndef NEO_DISCOVERY_H
#define NEO_DISCOVERY_H

typedef struct {
    uint32_t source;            /* 0 = nada descoberto, 1 = ACPI, 2 = FDT */
    uint64_t gicd_base;
    uint64_t gicr_base;
    uint64_t gicc_base;
    uint32_t gic_version;
    uint64_t uart_base;
    uint32_t uart_type;         /* 1 = PL011, 2 = 16550, 3 = SBSA */
    uint32_t timer_virt_irq;    /* INTID, tipico 27 */
    uint32_t timer_phys_irq;    /* INTID, tipico 30 */
    uint32_t cpu_count;
    /* Dispositivos de placa — so o FDT fornece. */
    uint64_t virtio_base;
    uint32_t virtio_slots;
    uint32_t virtio_stride;
    /* E5 — IDENTIDADE: chave de texto derivada SO da descoberta, nunca digitada.
     * E o que indexa o perfil (politica) sem que a politica contamine a
     * descoberta (fatos). Derivacao:
     *   FDT  -> primeiro item de compatible do no raiz (ex: "linux,dummy-virt")
     *   ACPI -> oem_id + "_" + oem_table_id do cabecalho do XSDT, saneado
     *   nada -> "generic_aarch64"
     * Saneada para [A-Za-z0-9_-] porque vira nome de arquivo na ESP. */
    char identity[64];
} discovered_platform_t;

extern discovered_platform_t g_discovered_plat;

/* Saneia e grava a identidade (E5). Só [A-Za-z0-9_.-] passa; o resto vira '_',
 * porque a identidade vira NOME DE ARQUIVO na ESP: /profiles/<id>.conf.
 * Definida em acpi.c, usada pelos dois produtores. */
void disco_set_identity(const char *src);
/* Devolve a identidade derivada da descoberta (nunca vazia apos a descoberta). */
const char *disco_identity(void);

#endif /* NEO_DISCOVERY_H */
