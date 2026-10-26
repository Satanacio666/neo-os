#include "seed_fs.h"

/*
 * P2.2 — Read `.HC` sources from the FAT32 ESP via the UEFI firmware's FAT driver.
 * No custom filesystem, no custom block driver.
 */

static efi_file_handle_t *s_root = NULL;

int seed_fs_init(void) {
    efi_guid_t guid = EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID;
    efi_simple_file_system_protocol_t *fs = NULL;
    if (EFI_ERROR(BS->LocateProtocol(&guid, NULL, (void**)&fs)) || !fs) return -1;
    if (EFI_ERROR(fs->OpenVolume(fs, &s_root)) || !s_root) return -1;
    return 0;
}

static void seed_ascii_to_wchar(const char *src, wchar_t *dst, int cap) {
    int i = 0;
    while (src[i] && i < cap - 1) {
        dst[i] = (wchar_t)(unsigned char)src[i];
        i++;
    }
    dst[i] = 0;
}

/* ---------------------------------------------------------------------------
 * P1.1 / P4.3 — Pre-carga da arvore `holyc\` para RAM.
 *
 * POR QUE ISTO EXISTE (medido, nao teorico):
 * O NeoOS roda em EL1, mas o firmware que o carrega pode estar em EL2 — U-Boot
 * e o EDK2 do Renegade no Snapdragon entregam o payload em EL2. Depois do drop
 * EL2->EL1 (kernel/arch/aarch64/el2_drop.S) os Boot Services do firmware NAO
 * podem mais ser chamados: o codigo do firmware foi inicializado em EL2 e, ao
 * executa-lo a partir de EL1, ele toma excecao. Medido sob U-Boot:
 *
 *     [RAW] entry=EL2 drop=2 now=EL1
 *     Resetting CPU ...                 <- panic do proprio U-Boot
 *
 * Logo, TODA leitura de arquivo tem que acontecer ANTES do drop. Esta tabela e
 * o RAMDisk: depois do drop, seed_read_file() serve da RAM e nunca mais toca em
 * s_root->Open().
 * ------------------------------------------------------------------------- */

#define SEED_PRELOAD_MAX   64
#define SEED_PRELOAD_DIRSZ (8 * 4096)

typedef struct {
    char     name[64];
    uint8_t *data;
    uint64_t size;
} seed_preload_entry_t;

static seed_preload_entry_t s_preload[SEED_PRELOAD_MAX];
static int   s_preload_count = 0;
static int   s_preload_ready = 0;
static uint8_t *s_preload_dirbuf = NULL;

int seed_preload_count_get(void) { return s_preload_count; }

static int seed_name_eq(const char *a, const char *b) {
    int i = 0;
    for (;;) {
        char ca = a[i], cb = b[i];
        if (ca >= 'a' && ca <= 'z') ca = (char)(ca - 32);
        if (cb >= 'a' && cb <= 'z') cb = (char)(cb - 32);
        if (ca != cb) return 0;
        if (ca == 0) return 1;
        i++;
    }
}

/* Le a arvore `holyc\` inteira para RAM. Retorna o numero de arquivos, ou -1. */
int seed_preload_all(void) {
    if (!s_root) return -1;

    uint64_t dirbuf = 0;
    if (EFI_ERROR(BS->AllocatePages(AllocateAnyPages, EfiLoaderData,
                                    SEED_PRELOAD_DIRSZ / 4096, &dirbuf)))
        return -1;
    s_preload_dirbuf = (uint8_t*)dirbuf;

    wchar_t wdir[16];
    seed_ascii_to_wchar("holyc", wdir, 16);

    efi_file_handle_t *dir = NULL;
    if (EFI_ERROR(s_root->Open(s_root, &dir, wdir, EFI_FILE_MODE_READ, 0)) || !dir)
        return -1;

    for (;;) {
        uintn_t sz = SEED_PRELOAD_DIRSZ;
        efi_status_t st = dir->Read(dir, &sz, s_preload_dirbuf);
        if (EFI_ERROR(st) || sz == 0) break;

        efi_file_info_t *fi = (efi_file_info_t*)s_preload_dirbuf;
        if (fi->Attribute & EFI_FILE_DIRECTORY) continue;
        if (fi->FileSize == 0 || fi->FileSize > (4 * 1024 * 1024)) continue;
        if (s_preload_count >= SEED_PRELOAD_MAX) break;

        char nm[64];
        int k = 0;
        while (fi->FileName[k] && k < 63) { nm[k] = (char)fi->FileName[k]; k++; }
        nm[k] = 0;

        uint64_t phys = 0;
        if (EFI_ERROR(BS->AllocatePages(AllocateAnyPages, EfiLoaderData,
                                        (fi->FileSize + 4095) / 4096, &phys)))
            continue;

        char path[256];
        int n = 0;
        const char *pre = "holyc\\";
        for (int i = 0; pre[i] && n < 250; i++) path[n++] = pre[i];
        for (int i = 0; nm[i] && n < 254; i++) path[n++] = nm[i];
        path[n] = 0;

        wchar_t wp[256];
        seed_ascii_to_wchar(path, wp, 256);

        efi_file_handle_t *fh = NULL;
        if (EFI_ERROR(s_root->Open(s_root, &fh, wp, EFI_FILE_MODE_READ, 0)) || !fh)
            continue;
        uintn_t rd = (uintn_t)fi->FileSize;
        efi_status_t rst = fh->Read(fh, &rd, (void*)phys);
        fh->Close(fh);
        if (EFI_ERROR(rst)) continue;

        for (int i = 0; i < k; i++) s_preload[s_preload_count].name[i] = nm[i];
        s_preload[s_preload_count].name[k]  = 0;
        s_preload[s_preload_count].data     = (uint8_t*)phys;
        s_preload[s_preload_count].size     = (uint64_t)rd;
        s_preload_count++;
    }
    dir->Close(dir);
    s_preload_ready = 1;
    return s_preload_count;
}

/* E5 — leitura por CAMINHO COMPLETO (ex: "profiles\\<id>.conf").
 * seed_read_file() prefixa "holyc\\"; o perfil mora fora dessa arvore. */
int64_t seed_read_file_at(const char *path, void *buf, size_t max_bytes) {
    if (!s_root || !path || !buf) return -1;

    wchar_t wp[256];
    seed_ascii_to_wchar(path, wp, 256);

    efi_file_handle_t *fh = NULL;
    if (EFI_ERROR(s_root->Open(s_root, &fh, wp, EFI_FILE_MODE_READ, 0)) || !fh) return -1;

    uintn_t size = (uintn_t)max_bytes;
    efi_status_t st = fh->Read(fh, &size, buf);
    fh->Close(fh);
    if (EFI_ERROR(st)) return -1;
    return (int64_t)size;
}

/* Reads "holyc\<name>" from the ESP. Returns bytes read, or -1 on error. */
int64_t seed_read_file(const char *name, void *buf, size_t max_bytes) {
    if (!name || !buf) return -1;

    /* P1.1/P4.3: depois do drop nao existem Boot Services — servir da RAM. */
    if (s_preload_ready) {
        for (int i = 0; i < s_preload_count; i++) {
            if (!seed_name_eq(s_preload[i].name, name)) continue;
            uint64_t n = s_preload[i].size;
            if (n > (uint64_t)max_bytes) n = (uint64_t)max_bytes;
            uint8_t *d = (uint8_t*)buf;
            for (uint64_t j = 0; j < n; j++) d[j] = s_preload[i].data[j];
            return (int64_t)n;
        }
        return -1;
    }

    if (!s_root) return -1;

    char path[256];
    int n = 0;
    const char *pre = "holyc\\";
    for (int i = 0; pre[i] && n < 250; i++) path[n++] = pre[i];
    for (int i = 0; name[i] && n < 254; i++) path[n++] = name[i];
    path[n] = 0;

    wchar_t wpath[256];
    seed_ascii_to_wchar(path, wpath, 256);

    efi_file_handle_t *fh = NULL;
    if (EFI_ERROR(s_root->Open(s_root, &fh, wpath, EFI_FILE_MODE_READ, 0)) || !fh) return -1;

    uintn_t size = (uintn_t)max_bytes;
    efi_status_t st = fh->Read(fh, &size, buf);
    fh->Close(fh);
    if (EFI_ERROR(st)) return -1;
    return (int64_t)size;
}

/* ---------------------------------------------------------------------------
 * P2.3 — Escrita no ESP.
 *
 * Não há filesystem próprio aqui: é o mesmo driver FAT do firmware. Escrever é
 * o que destrava o cache de JIT (P2.4) e a validação de ida e volta do RedSea
 * sobre EFI_BLOCK_IO (P3.2).
 *
 * seed_write_file() apaga e recria o arquivo antes de gravar — assim o tamanho
 * é sempre exato e não sobra cauda de uma versão anterior maior (o FAT não
 * trunca sozinho ao sobrescrever).
 * ------------------------------------------------------------------------- */

static int seed_build_path(const char *name, wchar_t *wpath, int cap) {
    char path[256];
    int n = 0;
    const char *pre = "holyc\\";
    for (int i = 0; pre[i] && n < 250; i++) path[n++] = pre[i];
    for (int i = 0; name[i] && n < 254; i++) path[n++] = name[i];
    path[n] = 0;
    seed_ascii_to_wchar(path, wpath, cap);
    return 0;
}

int seed_delete_file(const char *name) {
    if (!s_root || !name) return -1;
    wchar_t wpath[256];
    seed_build_path(name, wpath, 256);

    efi_file_handle_t *fh = NULL;
    efi_status_t st = s_root->Open(s_root, &fh, wpath,
                                   EFI_FILE_MODE_READ | EFI_FILE_MODE_WRITE, 0);
    if (EFI_ERROR(st) || !fh) return -1;
    st = fh->Delete(fh);   /* fecha o handle também */
    return EFI_ERROR(st) ? -1 : 0;
}

int64_t seed_write_file(const char *name, const void *buf, size_t bytes) {
    if (!s_root || !name || !buf) return -1;

    /* tamanho exato: apaga a versão anterior (ignora ausência) */
    (void)seed_delete_file(name);

    wchar_t wpath[256];
    seed_build_path(name, wpath, 256);

    efi_file_handle_t *fh = NULL;
    efi_status_t st = s_root->Open(s_root, &fh, wpath,
                                   EFI_FILE_MODE_READ | EFI_FILE_MODE_WRITE |
                                   EFI_FILE_MODE_CREATE, 0);
    if (EFI_ERROR(st) || !fh) return -1;

    uintn_t size = (uintn_t)bytes;
    st = fh->Write(fh, &size, (void*)buf);
    if (!EFI_ERROR(st)) st = fh->Flush(fh);
    fh->Close(fh);
    if (EFI_ERROR(st) || size != (uintn_t)bytes) return -1;
    return (int64_t)size;
}

uint32_t seed_fnv1a(const void *data, size_t bytes) {
    const uint8_t *p = (const uint8_t*)data;
    uint32_t h = 2166136261u;             /* FNV-1a 32 bits */
    for (size_t i = 0; i < bytes; i++) {
        h ^= p[i];
        h *= 16777619u;
    }
    return h;
}
