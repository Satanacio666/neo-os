#ifndef NEO_SEED_FS_H
#define NEO_SEED_FS_H

#include <uefi.h>

/*
 * P2.2 — Bootstrap file access via the UEFI firmware's own FAT driver.
 *
 * The seed does NOT implement a filesystem or a block driver. It reads the
 * OS's own `.HC` sources from the FAT32 ESP using EFI_SIMPLE_FILE_SYSTEM_PROTOCOL,
 * exactly like the firmware's boot menu reads the boot loader. After the `.HC`
 * drivers load, they own the real hardware.
 */

int     seed_fs_init(void);
int64_t seed_read_file(const char *name, void *buf, size_t max_bytes);

#endif // NEO_SEED_FS_H
