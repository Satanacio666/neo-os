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
