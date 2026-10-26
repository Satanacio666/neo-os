/*
 * fwdesc.c — E1 — descoberta da descricao de hardware pelo firmware.
 *
 * POR QUE ISTO EXISTE:
 * O NeoOS carregava uma TABELA de plataformas escrita a mao (g_plat_qemu,
 * g_plat_sm8150, g_plat_rpi4/5, g_plat_rk3399). Isso e uma lista de hardware
 * suportado, nao um sistema universal: hardware fora da lista nao boota, mesmo
 * que o firmware saiba descreve-lo perfeitamente.
 *
 * O firmware JA descreve o hardware. No ARM isso chega por dois caminhos, ambos
 * expostos na EFI Configuration Table:
 *   - Device Tree (FDT)  -> placas ARM, SBCs, QEMU virt
 *   - ACPI 2.0 (RSDP)    -> servidores ARM, Windows-on-ARM
 *
 * Este modulo apenas MEDE o que existe. Nao decide nada, nao chuta endereco.
 * A separacao que ele estabelece:
 *   DESCOBERTA (aqui) -> IDENTIDADE -> PERFIL (overlay opcional de dados)
 * O perfil e politica e nao pode ser descoberto; a descoberta e sempre factivel.
 * Perfil ausente => boota com defaults seguros. Nunca "boota ou nao".
 */

#include <uefi.h>

/* --- GUIDs canonicos da EFI Configuration Table -------------------------- */

static const efi_guid_t GUID_DTB = {
    0xb1b621d5, 0xf19c, 0x41a5, { 0x83, 0x0b, 0xd9, 0x15, 0x2c, 0x69, 0xaa, 0xe0 }
};
static const efi_guid_t GUID_ACPI20 = {
    0x8868e871, 0xe4f1, 0x11d3, { 0xbc, 0x22, 0x00, 0x80, 0xc7, 0x3c, 0x88, 0x81 }
};
static const efi_guid_t GUID_ACPI10 = {
    0xeb9d2d30, 0x2d88, 0x11d3, { 0x9a, 0x16, 0x00, 0x90, 0x27, 0x3f, 0xc1, 0x4d }
};
static const efi_guid_t GUID_SMBIOS3 = {
    0xf2fd1544, 0x9794, 0x4a2c, { 0x99, 0x2e, 0xe5, 0xbb, 0xcf, 0x20, 0xe3, 0x94 }
};
static const efi_guid_t GUID_SMBIOS = {
    0xeb9d2d31, 0x2d88, 0x11d3, { 0x9a, 0x16, 0x00, 0x90, 0x27, 0x3f, 0xc1, 0x4d }
};

/* --- Descritores encontrados (consumidos pelos parsers E2/E4) ------------ */

void    *g_fdt_blob  = 0;      /* Device Tree Blob (FDT) */
void    *g_acpi_rsdp = 0;      /* RSDP do ACPI 2.0 */
uint32_t g_fdt_size  = 0;      /* totalsize do FDT, do proprio cabecalho */

int neo_fwdesc_has_dtb(void)  { return g_fdt_blob  != 0; }
int neo_fwdesc_has_acpi(void) { return g_acpi_rsdp != 0; }
uint32_t neo_fwdesc_fdt_size(void) { return g_fdt_size; }

/* --- Helpers ------------------------------------------------------------- */

static int guid_eq(const efi_guid_t *a, const efi_guid_t *b) {
    if (a->Data1 != b->Data1 || a->Data2 != b->Data2 || a->Data3 != b->Data3) return 0;
    for (int i = 0; i < 8; i++) if (a->Data4[i] != b->Data4[i]) return 0;
    return 1;
}

static void print_guid(const efi_guid_t *g) {
    printf("%08lX-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X",
           (unsigned long)g->Data1, (unsigned)g->Data2, (unsigned)g->Data3,
           (unsigned)g->Data4[0], (unsigned)g->Data4[1],
           (unsigned)g->Data4[2], (unsigned)g->Data4[3],
           (unsigned)g->Data4[4], (unsigned)g->Data4[5],
           (unsigned)g->Data4[6], (unsigned)g->Data4[7]);
}

/* O FDT e BIG-ENDIAN. Ler como u32 em LE daria 0xedfe0dd0 — por isso comparo
 * byte a byte, que e inequivoco nos dois sentidos. */
static int fdt_validate(void *blob) {
    const uint8_t *p = (const uint8_t*)blob;
    if (p[0] != 0xD0 || p[1] != 0x0D || p[2] != 0xFE || p[3] != 0xED) {
        printf("[FW] FDT: magic INESPERADO (%02X %02X %02X %02X, esperado D0 0D FE ED)\n",
               (unsigned)p[0], (unsigned)p[1], (unsigned)p[2], (unsigned)p[3]);
        return 0;
    }
    g_fdt_size = ((uint32_t)p[4] << 24) | ((uint32_t)p[5] << 16) |
                 ((uint32_t)p[6] << 8)  | (uint32_t)p[7];
    printf("[FW] FDT: magic OK (d00dfeed), totalsize=%u, version=%u\n",
           (unsigned)g_fdt_size,
           (unsigned)(((uint32_t)p[20] << 24) | ((uint32_t)p[21] << 16) |
                      ((uint32_t)p[22] << 8) | (uint32_t)p[23]));
    return 1;
}

/* Assinatura do RSDP: "RSD PTR " (8 bytes ASCII). */
static int acpi_validate(void *rsdp) {
    const uint8_t *p = (const uint8_t*)rsdp;
    const char *sig = "RSD PTR ";
    for (int i = 0; i < 8; i++) {
        if (p[i] != (uint8_t)sig[i]) {
            printf("[FW] ACPI: assinatura INESPERADA em RSDP\n");
            return 0;
        }
    }
    /* Revision em +15: 0 = ACPI 1.0, 2 = ACPI 2.0+ (tem XSDT de 64 bits). */
    printf("[FW] ACPI: RSDP OK (\"RSD PTR \"), revision=%u\n", (unsigned)p[15]);
    return 1;
}

/* --- Sonda --------------------------------------------------------------- */

int neo_fwdesc_probe(void) {
    printf("[FW] EFI Configuration Table: %llu entrada(s)\n",
           (unsigned long long)ST->NumberOfTableEntries);

    for (uintn_t i = 0; i < ST->NumberOfTableEntries; i++) {
        efi_configuration_table_t *e = &ST->ConfigurationTable[i];
        const char *name = 0;

        if      (guid_eq(&e->VendorGuid, &GUID_DTB))     { name = "DTB (Device Tree)";   g_fdt_blob  = e->VendorTable; }
        else if (guid_eq(&e->VendorGuid, &GUID_ACPI20))  { name = "ACPI 2.0 (RSDP)";      g_acpi_rsdp = e->VendorTable; }
        else if (guid_eq(&e->VendorGuid, &GUID_ACPI10))  { name = "ACPI 1.0 (legado)"; }
        else if (guid_eq(&e->VendorGuid, &GUID_SMBIOS3)) { name = "SMBIOS 3.0"; }
        else if (guid_eq(&e->VendorGuid, &GUID_SMBIOS))  { name = "SMBIOS (legado)"; }

        printf("[FW] #%llu @ 0x%016llX  ", (unsigned long long)i,
               (unsigned long long)(uintptr_t)e->VendorTable);
        print_guid(&e->VendorGuid);
        if (name) printf("  <- %s", name);
        printf("\n");
    }

    /* Achar o ponteiro nao basta: validar o conteudo antes que qualquer parser
     * (E2/E4) tente dereferenciar o cabecalho. */
    int ok = 0;
    if (g_fdt_blob)  { printf("[FW] --- validando FDT ---\n");  ok |= fdt_validate(g_fdt_blob); }
    if (g_acpi_rsdp) { printf("[FW] --- validando ACPI ---\n"); ok |= acpi_validate(g_acpi_rsdp); }
    if (!ok) printf("[FW] nenhuma descricao de hardware utilizavel\n");

    return ok ? 0 : -1;
}
