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

/* Reads "holyc\<name>" from the ESP. Returns bytes read, or -1 on error. */
int64_t seed_read_file(const char *name, void *buf, size_t max_bytes) {
    if (!s_root || !name || !buf) return -1;

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
