#ifndef NEO_REDSEA_H
#define NEO_REDSEA_H

#include <uefi.h>

#define RS_ATTR_READONLY 0x01
#define RS_ATTR_HIDDEN   0x02
#define RS_ATTR_SYSTEM   0x04
#define RS_ATTR_VOL_ID   0x08
#define RS_ATTR_DIR      0x10
#define RS_ATTR_ARCHIVE  0x20
#define RS_ATTR_FILE     0x40

#define REDSEA_MAX_NAME  38
#define REDSEA_ENTRIES_PER_SECTOR (512 / sizeof(redsea_entry_t))

typedef struct {
    uint16_t attr;                   // File attributes
    char     name[REDSEA_MAX_NAME];  // Filename (null-terminated)
    uint64_t cluster;                // Starting 512-byte LBA sector
    uint64_t size;                   // Exact file size in bytes
    uint64_t datetime;               // 64-bit timestamp
} __attribute__((packed)) redsea_entry_t;

typedef struct {
    uint64_t root_lba;
    uint32_t root_sectors;
    uint64_t total_sectors;
    uint64_t current_dir_lba;
    uint32_t current_dir_sectors;
    uint64_t next_alloc_lba;
    char     current_pwd[128];
    int      initialized;
} redsea_fs_t;

int  redsea_init(uint64_t partition_lba);
void redsea_list_dir(void);
int  redsea_read_file(const char *filename, void *buffer, size_t max_bytes, size_t *out_size);
int  redsea_write_file(const char *filename, const void *data, size_t size);
int  redsea_delete_file(const char *filename);
int  redsea_mkdir(const char *dirname);
int  redsea_change_dir(const char *dirname);
const char* redsea_get_pwd(void);
int  redsea_format(uint64_t partition_lba, uint64_t sector_count);
int  redsea_get_entries(redsea_entry_t *entries, int max_entries);

// 16MB Volatile RAMDisk
void ramdisk_init(void);
int  ramdisk_write_file(const char *filename, const void *data, size_t size);
int  ramdisk_read_file(const char *filename, void *buffer, size_t max_bytes, size_t *out_size);
void ramdisk_list_dir(void);

#endif // NEO_REDSEA_H
