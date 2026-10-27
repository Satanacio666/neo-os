/*
 * blockio.c — P7.1 — descoberta de armazenamento via EFI_BLOCK_IO_PROTOCOL.
 *
 * POR QUE O PROTOCOLO E NAO UM DRIVER DE UFS NATIVO:
 *
 * O NeoOS nunca chama ExitBootServices (fato medido: exit_bs() existe em
 * boot/uefi/stdlib.c mas nao tem chamador). Logo o firmware segue vivo e os
 * Boot Services continuam validos durante todo o boot. Escrever um driver UFS
 * nativo (HCI, UPIU/SCSI, filas de transferencia, clocks e reguladores do PMIC
 * da Qualcomm) e trabalho de meses. O EDK2 do Renegade na POCO ja inicializou o
 * controlador UFS e ja expoe EFI_BLOCK_IO.
 *
 * Usar o protocolo como FONTE DE VERDADE elimina toda suposicao sobre portas e
 * offsets — e a mesma decisao de projeto que fez o NeoOS ler os .HC pelo driver
 * FAT do firmware em vez de escrever um filesystem proprio.
 *
 * O que sai daqui:
 *   - neo_block_probe()  : enumera os dispositivos e imprime a tabela
 *   - neo_block_read()   : primitiva 1:1 com BlockIo->ReadBlocks
 *   - neo_block_write()  : primitiva 1:1 com BlockIo->WriteBlocks
 * O apps/RedSea.HC precisa exatamente destas duas ultimas para operar como
 * sistema de arquivos.
 */

#include <uefi.h>

#define NEO_BLOCK_MAX 8

typedef struct {
    efi_handle_t    handle;
    efi_block_io_t *bio;
    uint32_t        block_size;
    uint64_t        last_block;
    uint32_t        media_id;
    int             removable;
    int             media_present;
    int             read_only;
} neo_block_dev_t;

static neo_block_dev_t s_blk[NEO_BLOCK_MAX];
static int s_blk_count   = 0;
static int s_blk_primary = -1;

int neo_block_count(void) { return s_blk_count; }
int neo_block_primary(void) { return s_blk_primary; }

uint32_t neo_block_size(int idx) {
    if (idx < 0 || idx >= s_blk_count) return 0;
    return s_blk[idx].block_size;
}

uint64_t neo_block_last(int idx) {
    if (idx < 0 || idx >= s_blk_count) return 0;
    return s_blk[idx].last_block;
}

uint64_t neo_block_bytes(int idx) {
    if (idx < 0 || idx >= s_blk_count) return 0;
    return (uint64_t)s_blk[idx].block_size * (s_blk[idx].last_block + 1ULL);
}

int neo_block_is_removable(int idx) {
    if (idx < 0 || idx >= s_blk_count) return -1;
    return s_blk[idx].removable;
}

/* ---------------------------------------------------------------------------
 * As duas primitivas que o RedSea.HC consome. Mapeiam 1:1 no protocolo: o
 * firmware cuida de UFS/eMMC/USB, nos so endereçamos LBA.
 * ------------------------------------------------------------------------- */

int64_t neo_block_read(int idx, uint64_t lba, uint64_t count, void *buf) {
    if (idx < 0 || idx >= s_blk_count || !buf || count == 0) return -1;
    neo_block_dev_t *d = &s_blk[idx];
    if (!d->bio || !d->media_present || d->block_size == 0) return -1;
    efi_status_t st = d->bio->ReadBlocks(d->bio, d->media_id, (efi_lba_t)lba,
                                         (uintn_t)(count * d->block_size), buf);
    if (EFI_ERROR(st)) return -1;
    return (int64_t)(count * d->block_size);
}

int64_t neo_block_write(int idx, uint64_t lba, uint64_t count, const void *buf) {
    if (idx < 0 || idx >= s_blk_count || !buf || count == 0) return -1;
    neo_block_dev_t *d = &s_blk[idx];
    if (!d->bio || !d->media_present || d->block_size == 0 || d->read_only) return -1;
    efi_status_t st = d->bio->WriteBlocks(d->bio, d->media_id, (efi_lba_t)lba,
                                          (uintn_t)(count * d->block_size), (void*)buf);
    if (EFI_ERROR(st)) return -1;
    return (int64_t)(count * d->block_size);
}

/* ---------------------------------------------------------------------------
 * Enumeracao. Imprime a tabela para o log de boot: e assim que descobrimos, na
 * propria POCO, o que o Renegade EDK2 expoe — sem supor nada.
 * ------------------------------------------------------------------------- */

int neo_block_probe(void) {
    efi_guid_t    guid = EFI_BLOCK_IO_PROTOCOL_GUID;
    efi_handle_t *handles = NULL;
    uintn_t       nhandles = 0;

    s_blk_count   = 0;
    s_blk_primary = -1;

    efi_status_t st = BS->LocateHandleBuffer(ByProtocol, &guid, NULL, &nhandles, &handles);
    if (EFI_ERROR(st) || !handles) {
        printf("[BLOCK] EFI_BLOCK_IO indisponivel (status 0x%llX)\r\n",
               (unsigned long long)st);
        return -1;
    }

    printf("[BLOCK] EFI_BLOCK_IO: %llu handle(s)\r\n", (unsigned long long)nhandles);

    for (uintn_t i = 0; i < nhandles && s_blk_count < NEO_BLOCK_MAX; i++) {
        efi_block_io_t *bio = NULL;
        if (EFI_ERROR(BS->HandleProtocol(handles[i], &guid, (void**)&bio))) continue;
        if (!bio || !bio->Media) continue;

        efi_block_io_media_t *m = bio->Media;
        neo_block_dev_t *d = &s_blk[s_blk_count];
        d->handle        = handles[i];
        d->bio           = bio;
        d->block_size    = m->BlockSize;
        d->last_block    = (uint64_t)m->LastBlock;
        d->media_id      = m->MediaId;
        d->removable     = m->RemovableMedia ? 1 : 0;
        d->media_present = m->MediaPresent  ? 1 : 0;
        d->read_only     = m->ReadOnly      ? 1 : 0;

        uint64_t bytes = (uint64_t)m->BlockSize * ((uint64_t)m->LastBlock + 1ULL);
        uint64_t mb    = bytes / (1024ULL * 1024ULL);
        uint64_t gb    = bytes / (1024ULL * 1024ULL * 1024ULL);

        printf("[BLOCK] #%d blk=%u blocos=%llu = %llu MB (%llu GB) %s%s%s\r\n",
               s_blk_count,
               (unsigned)m->BlockSize,
               (unsigned long long)(uint64_t)m->LastBlock,
               (unsigned long long)mb,
               (unsigned long long)gb,
               m->RemovableMedia ? "removivel " : "fixo ",
               m->MediaPresent   ? "" : "SEM-MIDIA ",
               m->ReadOnly       ? "RO" : "RW");

        /* Primario = primeiro FIXO com midia presente e bloco valido. */
        if (s_blk_primary < 0 && !m->RemovableMedia && m->MediaPresent && m->BlockSize != 0)
            s_blk_primary = s_blk_count;

        s_blk_count++;
    }

    if (handles) BS->FreePool(handles);

    /* Fallback: se nao houver fixo, o primeiro com midia (ex.: pendrive USB). */
    if (s_blk_primary < 0) {
        for (int i = 0; i < s_blk_count; i++) {
            if (s_blk[i].media_present && s_blk[i].block_size != 0) { s_blk_primary = i; break; }
        }
    }

    printf("[BLOCK] dispositivos=%d primario=#%d\r\n", s_blk_count, s_blk_primary);
    return s_blk_count;
}

/* ---------------------------------------------------------------------------
 * P7.2 — Crash dump em setores CRUS, fora da FAT.
 *
 * REGRA PETREA: um caminho de falha nao pode alocar, nao pode montar estrutura
 * de diretorio e nao pode depender de heap. O driver FAT do firmware cria
 * descritores, percorre diretorios e aloca clusters. Se o panic vier de heap
 * corrompido ou stack estourada, um logger FAT trava e apaga o rastro.
 *
 * Por isso: buffer estatico em .bss, escrita direta por BlockIo->WriteBlocks
 * para a zona reservada no fim da midia (LBA NEO_CRASH_ZONE_LBA, definido pelo
 * Makefile e fora do alcance do FAT). Nenhuma alocacao no caminho.
 *
 * Leitura offline: scripts/read-crash-dump.py
 * ------------------------------------------------------------------------- */

#ifndef NEO_CRASH_ZONE_LBA
#error "NEO_CRASH_ZONE_LBA nao definido: vem do Makefile (CRASH_ZONE_LBA). Um fallback silencioso aqui gravaria o dump no LBA errado sem avisar."
#endif

#define NEO_CRASH_MAGIC    0x4E454F21u   /* "NEO!" em ASCII */
#define NEO_CRASH_VERSION  1u
#define NEO_CRASH_SECTORS  8             /* 8 x 512 = 4096 B */

typedef struct __attribute__((packed)) {
    uint32_t magic;              /* 0x4E454F21 */
    uint32_t version;
    uint64_t timestamp_cntvct;   /* CNTVCT_EL0 no momento da falha */
    uint64_t esr_el1;            /* syndrome */
    uint64_t elr_el1;            /* PC da falha */
    uint64_t far_el1;            /* endereco que faltou */
    uint64_t spsr_el1;
    uint64_t sp_el1;
    uint64_t current_el;
    uint64_t heap_base;
    uint64_t last_module_idx;
    uint8_t  module_name[32];
    uint64_t regs[31];           /* x0..x30 */
    uint8_t  text_msg[128];
    uint8_t  stack_dump[1024];   /* 1 KB crus a partir do SP */
} neo_crash_dump_t;

/* Buffer de panic: estatico, alinhado, zero alocacao. */
static uint8_t s_crash_buf[4096] __attribute__((aligned(4096)));

/* Contexto preenchido pelo boot / pelo KernelInit.HC (nenhuma alocacao). */
uint64_t g_crash_heap_base   = 0;
uint64_t g_crash_module_idx  = 0;
char     g_crash_module_name[32] = { 0 };

void neo_crash_set_module(uint64_t idx, const char *name) {
    g_crash_module_idx = idx;
    if (!name) return;
    uint32_t i = 0;
    while (name[i] && i < 31) { g_crash_module_name[i] = name[i]; i++; }
    g_crash_module_name[i] = 0;
}

void neo_crash_set_heap(uint64_t base) { g_crash_heap_base = base; }

/* Escolhe o dispositivo que COBRE a zona de crash — o disco inteiro, nao a
 * particao. Maior last_block vence. Retorna -1 se nenhum cobrir. */
static int neo_crash_pick_device(void) {
    int idx = -1;
    uint64_t best = 0;
    for (int i = 0; i < s_blk_count; i++) {
        if (!s_blk[i].media_present) continue;
        if (s_blk[i].block_size != 512) continue;
        uint64_t blocks = s_blk[i].last_block + 1ULL;
        if (blocks < (uint64_t)NEO_CRASH_ZONE_LBA) continue;
        if (blocks > best) { best = blocks; idx = i; }
    }
    return idx;
}

/*
 * Grava o dump. Chamada de dentro do reporter de panic — precisa ser curta e
 * nao pode falhar de forma barulhenta.
 */
void neo_crash_dump_to_disk(uint64_t esr, uint64_t elr, uint64_t far, uint64_t spsr) {
    int idx = neo_crash_pick_device();
    if (idx < 0) return;              /* sem midia que cubra a zona: nao ha o que fazer */

    uint8_t *raw = s_crash_buf;
    for (uint32_t i = 0; i < sizeof(s_crash_buf); i++) raw[i] = 0;

    neo_crash_dump_t *d = (neo_crash_dump_t*)s_crash_buf;
    d->magic   = NEO_CRASH_MAGIC;
    d->version = NEO_CRASH_VERSION;

    uint64_t t = 0, sp = 0, cel = 0;
    __asm__ volatile("mrs %0, cntvct_el0"  : "=r"(t));
    __asm__ volatile("mov %0, sp"          : "=r"(sp));
    __asm__ volatile("mrs %0, CurrentEL"   : "=r"(cel));

    d->timestamp_cntvct = t;
    d->esr_el1          = esr;
    d->elr_el1          = elr;
    d->far_el1          = far;
    d->spsr_el1         = spsr;
    d->sp_el1           = sp;
    d->current_el       = (cel >> 2) & 3ULL;
    d->heap_base        = g_crash_heap_base;
    d->last_module_idx  = g_crash_module_idx;
    for (uint32_t i = 0; i < 32; i++) d->module_name[i] = (uint8_t)g_crash_module_name[i];

    /* Copia 1 KB crus da pilha a partir do SP (os quadros dos chamadores). */
    const uint8_t *src = (const uint8_t*)sp;
    for (uint32_t i = 0; i < sizeof(d->stack_dump); i++) d->stack_dump[i] = src[i];

    /* x0..x30 do chamador nao estao acessiveis aqui com seguranca; o que importa
     * para localizar a falha (ELR/FAR/ESR/SPSR + pilha) ja esta no cabecalho. */
    (void)d->regs;

    neo_block_write(idx, (uint64_t)NEO_CRASH_ZONE_LBA, NEO_CRASH_SECTORS, s_crash_buf);
}
