#include "redsea.h"
#include "../drivers/block/virtio_blk.h"
#include "../gui/render.h"
#include "../kernel/mem/kheap.h"
#include "../kernel/symbols/symbols.h"
#include <uefi.h>

static redsea_fs_t g_redsea = {0};

#define DEFAULT_REDSEA_LBA 1
#define REDSEA_ROOT_SECTORS 16

// 16MB RAMDisk structure
#define RAMDISK_MAX_FILES 32
#define RAMDISK_SIZE (16 * 1024 * 1024)

typedef struct {
    char   name[REDSEA_MAX_NAME];
    size_t size;
    size_t offset;
    int    used;
} ramdisk_entry_t;

typedef struct {
    uint8_t         *storage;
    size_t           used_bytes;
    ramdisk_entry_t  entries[RAMDISK_MAX_FILES];
    int              initialized;
} ramdisk_fs_t;

static ramdisk_fs_t g_ramdisk = {0};

static void scan_directory_watermark(uint64_t dir_lba, uint32_t dir_sectors, int depth) {
    if (depth > 16) return;
    if (dir_lba + dir_sectors > g_redsea.next_alloc_lba) {
        g_redsea.next_alloc_lba = dir_lba + dir_sectors;
    }

    uint8_t sector_buf[512];
    for (uint32_t s = 0; s < dir_sectors; s++) {
        if (virtio_blk_read_sectors(dir_lba + s, 1, sector_buf) != 0) break;
        redsea_entry_t *entries = (redsea_entry_t*)sector_buf;
        int max_e = 512 / sizeof(redsea_entry_t);

        for (int i = 0; i < max_e; i++) {
            if (entries[i].attr != 0 && entries[i].name[0] != '\0') {
                if (strcmp(entries[i].name, ".") == 0 || strcmp(entries[i].name, "..") == 0) {
                    continue;
                }
                uint32_t e_sectors = (entries[i].size + 511) / 512;
                if (entries[i].cluster + e_sectors > g_redsea.next_alloc_lba) {
                    g_redsea.next_alloc_lba = entries[i].cluster + e_sectors;
                }
                if (entries[i].attr & RS_ATTR_DIR) {
                    scan_directory_watermark(entries[i].cluster, e_sectors > 0 ? e_sectors : 2, depth + 1);
                }
            }
        }
    }
}

static void update_alloc_watermark(void) {
    g_redsea.next_alloc_lba = g_redsea.root_lba + g_redsea.root_sectors;
    scan_directory_watermark(g_redsea.root_lba, g_redsea.root_sectors, 0);
}

int redsea_init(uint64_t partition_lba) {
    if (partition_lba == 0) partition_lba = DEFAULT_REDSEA_LBA;

    g_redsea.root_lba = partition_lba;
    g_redsea.root_sectors = REDSEA_ROOT_SECTORS;
    g_redsea.total_sectors = virtio_blk_get_capacity() - partition_lba;
    g_redsea.current_dir_lba = partition_lba;
    g_redsea.current_dir_sectors = REDSEA_ROOT_SECTORS;
    strncpy(g_redsea.current_pwd, "/", sizeof(g_redsea.current_pwd));
    g_redsea.initialized = 1;

    // Check if partition is formatted by reading sector 0
    uint8_t sector_buf[512];
    if (virtio_blk_read_sectors(g_redsea.root_lba, 1, sector_buf) != 0) {
        printf("[REDSEA] Failed to read partition LBA %llu\n", (unsigned long long)partition_lba);
        return -1;
    }

    redsea_entry_t *entries = (redsea_entry_t*)sector_buf;
    if (entries[0].attr == 0 || entries[0].name[0] == '\0') {
        printf("[REDSEA] Partition empty, formatting RedSea filesystem...\n");
        redsea_format(partition_lba, g_redsea.total_sectors);
    } else {
        update_alloc_watermark();
        printf("[REDSEA] RedSea Contiguous Filesystem mounted @ LBA %llu (Next alloc: %llu)\n",
               (unsigned long long)partition_lba, (unsigned long long)g_redsea.next_alloc_lba);
    }

    ramdisk_init();

    symbols_register("redsea_list", (void*)redsea_list_dir, SYM_FUNC);
    symbols_register("redsea_mkdir", (void*)redsea_mkdir, SYM_FUNC);
    symbols_register("redsea_cd", (void*)redsea_change_dir, SYM_FUNC);
    symbols_register("redsea_rm", (void*)redsea_delete_file, SYM_FUNC);
    symbols_register("redsea_pwd", (void*)redsea_get_pwd, SYM_FUNC);
    symbols_register("ramdisk_list", (void*)ramdisk_list_dir, SYM_FUNC);
    symbols_register("ramdisk_rm", (void*)ramdisk_delete_file, SYM_FUNC);
    return 0;
}

int redsea_format(uint64_t partition_lba, uint64_t sector_count) {
    if (sector_count > 0) {
        g_redsea.total_sectors = sector_count;
    }
    uint8_t zero_buf[512];
    memset(zero_buf, 0, sizeof(zero_buf));

    // Clear root directory sectors
    for (uint32_t i = 0; i < REDSEA_ROOT_SECTORS; i++) {
        virtio_blk_write_sectors(partition_lba + i, 1, zero_buf);
    }

    g_redsea.root_lba = partition_lba;
    g_redsea.root_sectors = REDSEA_ROOT_SECTORS;
    g_redsea.current_dir_lba = partition_lba;
    g_redsea.current_dir_sectors = REDSEA_ROOT_SECTORS;
    strncpy(g_redsea.current_pwd, "/", sizeof(g_redsea.current_pwd));
    g_redsea.next_alloc_lba = partition_lba + REDSEA_ROOT_SECTORS;
    g_redsea.initialized = 1;

    // Create clean base README.TXT
    const char *readme_txt =
        "Welcome to NeoOS 2.0!\n"
        "AArch64 Ring 0 / EL1 Single Address Space Operating System.\n"
        "DolDoc 2.0, NeoC JIT Engine, RedSea Contiguous Storage.\n";
    redsea_write_file("README.TXT", readme_txt, strlen(readme_txt));

    // Create system directories
    redsea_mkdir("System");
    redsea_mkdir("Apps");
    redsea_mkdir("Docs");

    printf("[REDSEA] Filesystem formatted successfully with system directory structure.\n");
    return 0;
}

const char* redsea_get_pwd(void) {
    if (!g_redsea.initialized) return "/";
    return g_redsea.current_pwd;
}

void redsea_list_dir(void) {
    if (!g_redsea.initialized) {
        doldoc_print("$FG,RED$RedSea filesystem not mounted.$FG$\n");
        return;
    }

    doldoc_printf("$FG,CYAN$--- REDSEA FILESYSTEM [%s] ---$FG$\n", g_redsea.current_pwd);

    uint8_t sector_buf[512];
    int count = 0;

    for (uint32_t s = 0; s < g_redsea.current_dir_sectors; s++) {
        if (virtio_blk_read_sectors(g_redsea.current_dir_lba + s, 1, sector_buf) != 0) break;

        redsea_entry_t *entries = (redsea_entry_t*)sector_buf;
        int max_e = 512 / sizeof(redsea_entry_t);

        for (int i = 0; i < max_e; i++) {
            if (entries[i].attr != 0 && entries[i].name[0] != '\0') {
                count++;
                if (entries[i].attr & RS_ATTR_DIR) {
                    char cd_cmd[64];
                    snprintf(cd_cmd, sizeof(cd_cmd), "cd %s", entries[i].name);
                    doldoc_printf("  $FG,YELLOW$[DIR]$FG$  %s        $BT,\"Open\",LM=\"%s\"$\n",
                                  entries[i].name, cd_cmd);
                } else {
                    char run_cmd[64];
                    char cat_cmd[64];
                    snprintf(run_cmd, sizeof(run_cmd), "run %s", entries[i].name);
                    snprintf(cat_cmd, sizeof(cat_cmd), "cat %s", entries[i].name);

                    doldoc_printf("  $FG,GREEN$[FILE]$FG$ %s (%llu B)  ",
                                  entries[i].name, (unsigned long long)entries[i].size);
                    doldoc_printf("$BT,\"Run\",LM=\"%s\"$ $BT,\"View\",LM=\"%s\"$\n",
                                  run_cmd, cat_cmd);
                }
            }
        }
    }

    if (count == 0) {
        doldoc_print("  (Empty directory)\n");
    }
    doldoc_printf("$FG,CYAN$--------------------------------------------------- (%d items)$FG$\n", count);
}

int redsea_get_entries(redsea_entry_t *entries, int max_entries) {
    if (!g_redsea.initialized || !entries || max_entries <= 0) return 0;
    uint8_t sector_buf[512];
    int count = 0;

    for (uint32_t s = 0; s < g_redsea.current_dir_sectors; s++) {
        if (virtio_blk_read_sectors(g_redsea.current_dir_lba + s, 1, sector_buf) != 0) break;
        redsea_entry_t *e = (redsea_entry_t*)sector_buf;
        int max_e = 512 / sizeof(redsea_entry_t);
        for (int i = 0; i < max_e; i++) {
            if (e[i].attr != 0 && e[i].name[0] != '\0') {
                if (count < max_entries) {
                    entries[count] = e[i];
                    count++;
                }
            }
        }
    }
    return count;
}

int redsea_mkdir(const char *dirname) {
    if (!g_redsea.initialized || !dirname || !*dirname) return -1;

    // Check if name already exists in current directory
    uint8_t sector_buf[512];
    int free_sector = -1;
    int free_idx = -1;

    for (uint32_t s = 0; s < g_redsea.current_dir_sectors; s++) {
        if (virtio_blk_read_sectors(g_redsea.current_dir_lba + s, 1, sector_buf) != 0) return -1;
        redsea_entry_t *entries = (redsea_entry_t*)sector_buf;
        int max_e = 512 / sizeof(redsea_entry_t);

        for (int i = 0; i < max_e; i++) {
            if (entries[i].attr != 0 && strcmp(entries[i].name, dirname) == 0) {
                return -1; // Already exists
            }
            if ((entries[i].attr == 0 || entries[i].name[0] == '\0') && free_sector == -1) {
                free_sector = (int)s;
                free_idx = i;
            }
        }
    }

    if (free_sector == -1) {
        return -1; // Directory table full
    }

    // Allocate 2 sectors (1024 bytes = 16 entries) for new directory
    uint32_t new_dir_sectors = 2;
    if (g_redsea.total_sectors > 0 &&
        (g_redsea.next_alloc_lba + new_dir_sectors > g_redsea.root_lba + g_redsea.total_sectors)) {
        printf("[REDSEA] Error: Disk full! Cannot allocate directory '%s'\n", dirname);
        return -1;
    }
    uint64_t new_dir_lba = g_redsea.next_alloc_lba;
    g_redsea.next_alloc_lba += new_dir_sectors;

    // Initialize new directory sectors with '.' and '..'
    uint8_t *new_dir_buf = (uint8_t*)kmalloc(new_dir_sectors * 512);
    if (!new_dir_buf) return -1;
    memset(new_dir_buf, 0, new_dir_sectors * 512);
    redsea_entry_t *new_entries = (redsea_entry_t*)new_dir_buf;

    // '.' entry
    new_entries[0].attr = RS_ATTR_DIR;
    strncpy(new_entries[0].name, ".", sizeof(new_entries[0].name) - 1);
    new_entries[0].cluster = new_dir_lba;
    new_entries[0].size = new_dir_sectors * 512;
    new_entries[0].datetime = 0x202609210000ULL;

    // '..' entry
    new_entries[1].attr = RS_ATTR_DIR;
    strncpy(new_entries[1].name, "..", sizeof(new_entries[1].name) - 1);
    new_entries[1].cluster = g_redsea.current_dir_lba;
    new_entries[1].size = g_redsea.current_dir_sectors * 512;
    new_entries[1].datetime = 0x202609210000ULL;

    if (virtio_blk_write_sectors(new_dir_lba, new_dir_sectors, new_dir_buf) != 0) {
        printf("[REDSEA] Error writing new directory sectors\n");
        kfree(new_dir_buf);
        return -1;
    }
    kfree(new_dir_buf);

    // Write directory entry into parent directory
    virtio_blk_read_sectors(g_redsea.current_dir_lba + free_sector, 1, sector_buf);
    redsea_entry_t *entries = (redsea_entry_t*)sector_buf;
    entries[free_idx].attr = RS_ATTR_DIR;
    strncpy(entries[free_idx].name, dirname, sizeof(entries[free_idx].name) - 1);
    entries[free_idx].name[sizeof(entries[free_idx].name) - 1] = '\0';
    entries[free_idx].cluster = new_dir_lba;
    entries[free_idx].size = new_dir_sectors * 512;
    entries[free_idx].datetime = 0x202609210000ULL;

    virtio_blk_write_sectors(g_redsea.current_dir_lba + free_sector, 1, sector_buf);
    return 0;
}

int redsea_change_dir(const char *dirname) {
    if (!g_redsea.initialized || !dirname || !*dirname) return -1;

    if (strcmp(dirname, "/") == 0) {
        g_redsea.current_dir_lba = g_redsea.root_lba;
        g_redsea.current_dir_sectors = g_redsea.root_sectors;
        strncpy(g_redsea.current_pwd, "/", sizeof(g_redsea.current_pwd));
        return 0;
    }

    if (strcmp(dirname, ".") == 0) {
        return 0;
    }

    if (strcmp(dirname, "..") == 0) {
        if (g_redsea.current_dir_lba == g_redsea.root_lba) {
            return 0; // Already at root
        }

        uint8_t sector_buf[512];
        if (virtio_blk_read_sectors(g_redsea.current_dir_lba, 1, sector_buf) == 0) {
            redsea_entry_t *entries = (redsea_entry_t*)sector_buf;
            if ((entries[1].attr & RS_ATTR_DIR) && strcmp(entries[1].name, "..") == 0) {
                g_redsea.current_dir_lba = entries[1].cluster;
                g_redsea.current_dir_sectors = (entries[1].size + 511) / 512;
                if (g_redsea.current_dir_sectors == 0) g_redsea.current_dir_sectors = 16;

                // Update current_pwd: strip last component
                char *last_slash = strrchr(g_redsea.current_pwd, '/');
                if (last_slash && last_slash != g_redsea.current_pwd) {
                    *last_slash = '\0';
                } else {
                    strncpy(g_redsea.current_pwd, "/", sizeof(g_redsea.current_pwd));
                }
                return 0;
            }
        }
        // Fallback to root
        g_redsea.current_dir_lba = g_redsea.root_lba;
        g_redsea.current_dir_sectors = g_redsea.root_sectors;
        strncpy(g_redsea.current_pwd, "/", sizeof(g_redsea.current_pwd));
        return 0;
    }

    // Search for named directory in current directory
    uint8_t sector_buf[512];
    for (uint32_t s = 0; s < g_redsea.current_dir_sectors; s++) {
        if (virtio_blk_read_sectors(g_redsea.current_dir_lba + s, 1, sector_buf) != 0) break;
        redsea_entry_t *entries = (redsea_entry_t*)sector_buf;
        int max_e = 512 / sizeof(redsea_entry_t);

        for (int i = 0; i < max_e; i++) {
            if ((entries[i].attr & RS_ATTR_DIR) && strcmp(entries[i].name, dirname) == 0) {
                g_redsea.current_dir_lba = entries[i].cluster;
                g_redsea.current_dir_sectors = (entries[i].size + 511) / 512;
                if (g_redsea.current_dir_sectors == 0) g_redsea.current_dir_sectors = 2;

                if (strcmp(g_redsea.current_pwd, "/") == 0) {
                    snprintf(g_redsea.current_pwd, sizeof(g_redsea.current_pwd), "/%s", dirname);
                } else {
                    size_t cur_len = strlen(g_redsea.current_pwd);
                    snprintf(g_redsea.current_pwd + cur_len, sizeof(g_redsea.current_pwd) - cur_len, "/%s", dirname);
                }
                return 0;
            }
        }
    }

    return -1; // Directory not found
}

int redsea_delete_file(const char *filename) {
    if (!g_redsea.initialized || !filename || !*filename) return -1;
    if (strcmp(filename, ".") == 0 || strcmp(filename, "..") == 0) {
        printf("[REDSEA] Error: Cannot delete '.' or '..'\n");
        return -1;
    }

    uint8_t sector_buf[512];
    for (uint32_t s = 0; s < g_redsea.current_dir_sectors; s++) {
        if (virtio_blk_read_sectors(g_redsea.current_dir_lba + s, 1, sector_buf) != 0) break;
        redsea_entry_t *entries = (redsea_entry_t*)sector_buf;
        int max_e = 512 / sizeof(redsea_entry_t);

        for (int i = 0; i < max_e; i++) {
            if (entries[i].attr != 0 && strcmp(entries[i].name, filename) == 0) {
                // If directory, ensure it is empty
                if (entries[i].attr & RS_ATTR_DIR) {
                    uint32_t dir_sec = (entries[i].size + 511) / 512;
                    if (dir_sec == 0) dir_sec = 2;
                    uint8_t chk_buf[512];
                    int has_children = 0;
                    for (uint32_t ds = 0; ds < dir_sec; ds++) {
                        if (virtio_blk_read_sectors(entries[i].cluster + ds, 1, chk_buf) == 0) {
                            redsea_entry_t *sub = (redsea_entry_t*)chk_buf;
                            int sub_max = 512 / sizeof(redsea_entry_t);
                            for (int si = 0; si < sub_max; si++) {
                                if (sub[si].attr != 0 && sub[si].name[0] != '\0') {
                                    if (strcmp(sub[si].name, ".") != 0 && strcmp(sub[si].name, "..") != 0) {
                                        has_children = 1;
                                        break;
                                    }
                                }
                            }
                        }
                        if (has_children) break;
                    }
                    if (has_children) {
                        printf("[REDSEA] Error: Directory '%s' is not empty\n", filename);
                        return -1;
                    }
                }

                uint32_t file_sec = (entries[i].size + 511) / 512;
                if (file_sec == 0) file_sec = 1;
                // Reclaim contiguous sectors if this was the last allocation
                if (entries[i].cluster + file_sec == g_redsea.next_alloc_lba) {
                    g_redsea.next_alloc_lba = entries[i].cluster;
                }

                memset(&entries[i], 0, sizeof(redsea_entry_t));
                virtio_blk_write_sectors(g_redsea.current_dir_lba + s, 1, sector_buf);
                return 0;
            }
        }
    }

    return -1; // File not found
}

int redsea_read_file(const char *filename, void *buffer, size_t max_bytes, size_t *out_size) {
    if (!g_redsea.initialized || !filename || !buffer) return -1;

    uint8_t sector_buf[512];

    // 1. Search current directory
    for (uint32_t s = 0; s < g_redsea.current_dir_sectors; s++) {
        if (virtio_blk_read_sectors(g_redsea.current_dir_lba + s, 1, sector_buf) != 0) break;
        redsea_entry_t *entries = (redsea_entry_t*)sector_buf;
        int max_e = 512 / sizeof(redsea_entry_t);

        for (int i = 0; i < max_e; i++) {
            if (entries[i].attr != 0 && strcmp(entries[i].name, filename) == 0) {
                uint32_t sectors_to_read = (entries[i].size + 511) / 512;
                size_t bytes_to_copy = entries[i].size;
                if (bytes_to_copy > max_bytes) bytes_to_copy = max_bytes;

                uint8_t *temp_buf = (uint8_t*)kmalloc(sectors_to_read * 512);
                if (!temp_buf) return -1;

                if (virtio_blk_read_sectors(entries[i].cluster, sectors_to_read, temp_buf) != 0) {
                    kfree(temp_buf);
                    return -1;
                }

                memcpy(buffer, temp_buf, bytes_to_copy);
                kfree(temp_buf);

                if (out_size) *out_size = bytes_to_copy;
                return 0;
            }
        }
    }

    // 2. If not found and not in root directory, fallback to searching root directory
    if (g_redsea.current_dir_lba != g_redsea.root_lba) {
        for (uint32_t s = 0; s < g_redsea.root_sectors; s++) {
            if (virtio_blk_read_sectors(g_redsea.root_lba + s, 1, sector_buf) != 0) break;
            redsea_entry_t *entries = (redsea_entry_t*)sector_buf;
            int max_e = 512 / sizeof(redsea_entry_t);

            for (int i = 0; i < max_e; i++) {
                if (entries[i].attr != 0 && strcmp(entries[i].name, filename) == 0) {
                    uint32_t sectors_to_read = (entries[i].size + 511) / 512;
                    size_t bytes_to_copy = entries[i].size;
                    if (bytes_to_copy > max_bytes) bytes_to_copy = max_bytes;

                    uint8_t *temp_buf = (uint8_t*)kmalloc(sectors_to_read * 512);
                    if (!temp_buf) return -1;

                    if (virtio_blk_read_sectors(entries[i].cluster, sectors_to_read, temp_buf) != 0) {
                        kfree(temp_buf);
                        return -1;
                    }

                    memcpy(buffer, temp_buf, bytes_to_copy);
                    kfree(temp_buf);

                    if (out_size) *out_size = bytes_to_copy;
                    return 0;
                }
            }
        }
    }

    return -1; // File not found
}

int redsea_write_file(const char *filename, const void *data, size_t size) {
    if (!g_redsea.initialized || !filename || !data) return -1;

    uint8_t sector_buf[512];
    int free_sector = -1;
    int free_idx = -1;

    // Scan current directory for existing entry or free slot
    for (uint32_t s = 0; s < g_redsea.current_dir_sectors; s++) {
        if (virtio_blk_read_sectors(g_redsea.current_dir_lba + s, 1, sector_buf) != 0) break;
        redsea_entry_t *entries = (redsea_entry_t*)sector_buf;
        int max_e = 512 / sizeof(redsea_entry_t);

        for (int i = 0; i < max_e; i++) {
            if (entries[i].attr != 0 && strcmp(entries[i].name, filename) == 0) {
                // Overwrite existing file
                uint32_t existing_sectors = (entries[i].size + 511) / 512;
                uint32_t needed_sectors = (size + 511) / 512;

                uint64_t target_cluster = entries[i].cluster;
                if (needed_sectors > existing_sectors) {
                    if (g_redsea.total_sectors > 0 &&
                        (g_redsea.next_alloc_lba + needed_sectors > g_redsea.root_lba + g_redsea.total_sectors)) {
                        printf("[REDSEA] Error: Disk full! Cannot allocate %u sectors\n", needed_sectors);
                        return -1;
                    }
                    target_cluster = g_redsea.next_alloc_lba;
                    g_redsea.next_alloc_lba += needed_sectors;
                }

                uint8_t *payload_buf = (uint8_t*)kmalloc(needed_sectors * 512);
                if (!payload_buf) return -1;
                memset(payload_buf, 0, needed_sectors * 512);
                memcpy(payload_buf, data, size);

                if (virtio_blk_write_sectors(target_cluster, needed_sectors, payload_buf) != 0) {
                    kfree(payload_buf);
                    return -1;
                }
                kfree(payload_buf);

                entries[i].cluster = target_cluster;
                entries[i].size = size;
                entries[i].datetime = 0x202609210000ULL;
                virtio_blk_write_sectors(g_redsea.current_dir_lba + s, 1, sector_buf);
                return 0;
            }

            if ((entries[i].attr == 0 || entries[i].name[0] == '\0') && free_sector == -1) {
                free_sector = (int)s;
                free_idx = i;
            }
        }
    }

    if (free_sector == -1) {
        printf("[REDSEA] Error: Directory full!\n");
        return -1;
    }

    // Allocate contiguous sectors at next_alloc_lba
    uint32_t payload_sectors = (size + 511) / 512;
    if (payload_sectors == 0) payload_sectors = 1;
    if (g_redsea.total_sectors > 0 &&
        (g_redsea.next_alloc_lba + payload_sectors > g_redsea.root_lba + g_redsea.total_sectors)) {
        printf("[REDSEA] Error: Disk full! Cannot allocate %u sectors\n", payload_sectors);
        return -1;
    }
    uint64_t target_cluster = g_redsea.next_alloc_lba;
    g_redsea.next_alloc_lba += payload_sectors;

    uint8_t *payload_buf = (uint8_t*)kmalloc(payload_sectors * 512);
    if (!payload_buf) return -1;
    memset(payload_buf, 0, payload_sectors * 512);
    memcpy(payload_buf, data, size);

    if (virtio_blk_write_sectors(target_cluster, payload_sectors, payload_buf) != 0) {
        kfree(payload_buf);
        return -1;
    }
    kfree(payload_buf);

    // Update Directory Entry
    virtio_blk_read_sectors(g_redsea.current_dir_lba + free_sector, 1, sector_buf);
    redsea_entry_t *entries = (redsea_entry_t*)sector_buf;
    entries[free_idx].attr = RS_ATTR_FILE;
    strncpy(entries[free_idx].name, filename, sizeof(entries[free_idx].name) - 1);
    entries[free_idx].name[sizeof(entries[free_idx].name) - 1] = '\0';
    entries[free_idx].cluster = target_cluster;
    entries[free_idx].size = size;
    entries[free_idx].datetime = 0x202609210000ULL;

    virtio_blk_write_sectors(g_redsea.current_dir_lba + free_sector, 1, sector_buf);
    return 0;
}

// -------------------------------------------------------------
// 16MB Volatile RAMDisk (/tmp)
// -------------------------------------------------------------

void ramdisk_init(void) {
    if (g_ramdisk.initialized) return;

    // Allocate 16MB contiguous memory for RAMDisk
    g_ramdisk.storage = (uint8_t*)kmalloc(RAMDISK_SIZE);
    if (!g_ramdisk.storage) {
        printf("[RAMDISK] Warning: Could not allocate 16MB RAMDisk\n");
        return;
    }

    memset(g_ramdisk.storage, 0, RAMDISK_SIZE);
    memset(g_ramdisk.entries, 0, sizeof(g_ramdisk.entries));
    g_ramdisk.used_bytes = 0;
    g_ramdisk.initialized = 1;

    // Create a sample file in RAMDisk
    const char *tmp_info = "NeoOS Volatile 16MB RAMDisk mounted @ /tmp\nZero-latency memory storage.\n";
    ramdisk_write_file("readme.tmp", tmp_info, strlen(tmp_info));

    printf("[RAMDISK] 16MB Volatile RAMDisk initialized successfully.\n");
}

int ramdisk_write_file(const char *filename, const void *data, size_t size) {
    if (!g_ramdisk.initialized || !filename || !data) return -1;
    if (g_ramdisk.used_bytes + size > RAMDISK_SIZE) {
        printf("[RAMDISK] Out of memory!\n");
        return -1;
    }

    // Check if exists
    for (int i = 0; i < RAMDISK_MAX_FILES; i++) {
        if (g_ramdisk.entries[i].used && strcmp(g_ramdisk.entries[i].name, filename) == 0) {
            if (size <= g_ramdisk.entries[i].size) {
                // In-place overwrite without leaking memory
                memcpy(g_ramdisk.storage + g_ramdisk.entries[i].offset, data, size);
                g_ramdisk.entries[i].size = size;
                return 0;
            }
            size_t off = g_ramdisk.used_bytes;
            memcpy(g_ramdisk.storage + off, data, size);
            g_ramdisk.entries[i].offset = off;
            g_ramdisk.entries[i].size = size;
            g_ramdisk.used_bytes += (size + 15) & ~15ULL;
            return 0;
        }
    }

    // Find free slot
    for (int i = 0; i < RAMDISK_MAX_FILES; i++) {
        if (!g_ramdisk.entries[i].used) {
            size_t off = g_ramdisk.used_bytes;
            memcpy(g_ramdisk.storage + off, data, size);
            strncpy(g_ramdisk.entries[i].name, filename, sizeof(g_ramdisk.entries[i].name) - 1);
            g_ramdisk.entries[i].offset = off;
            g_ramdisk.entries[i].size = size;
            g_ramdisk.entries[i].used = 1;
            g_ramdisk.used_bytes += (size + 15) & ~15ULL;
            return 0;
        }
    }

    return -1; // Max files reached
}

int ramdisk_read_file(const char *filename, void *buffer, size_t max_bytes, size_t *out_size) {
    if (!g_ramdisk.initialized || !filename || !buffer) return -1;

    for (int i = 0; i < RAMDISK_MAX_FILES; i++) {
        if (g_ramdisk.entries[i].used && strcmp(g_ramdisk.entries[i].name, filename) == 0) {
            size_t to_copy = g_ramdisk.entries[i].size;
            if (to_copy > max_bytes) to_copy = max_bytes;
            memcpy(buffer, g_ramdisk.storage + g_ramdisk.entries[i].offset, to_copy);
            if (out_size) *out_size = to_copy;
            return 0;
        }
    }
    return -1;
}

int ramdisk_delete_file(const char *filename) {
    if (!g_ramdisk.initialized || !filename || !*filename) return -1;

    for (int i = 0; i < RAMDISK_MAX_FILES; i++) {
        if (g_ramdisk.entries[i].used && strcmp(g_ramdisk.entries[i].name, filename) == 0) {
            size_t end_off = (g_ramdisk.entries[i].offset + g_ramdisk.entries[i].size + 15) & ~15ULL;
            if (end_off == g_ramdisk.used_bytes) {
                // Reclaim storage if this was the last file
                g_ramdisk.used_bytes = g_ramdisk.entries[i].offset;
            }
            g_ramdisk.entries[i].used = 0;
            g_ramdisk.entries[i].name[0] = '\0';
            g_ramdisk.entries[i].size = 0;
            g_ramdisk.entries[i].offset = 0;
            return 0;
        }
    }
    return -1;
}

void ramdisk_list_dir(void) {
    if (!g_ramdisk.initialized) {
        doldoc_print("$FG,RED$RAMDisk not initialized.$FG$\n");
        return;
    }

    doldoc_printf("$FG,YELLOW$--- 16MB VOLATILE RAMDISK (/tmp) [%llu / %llu KB used] ---$FG$\n",
                  (unsigned long long)(g_ramdisk.used_bytes / 1024),
                  (unsigned long long)(RAMDISK_SIZE / 1024));

    int count = 0;
    for (int i = 0; i < RAMDISK_MAX_FILES; i++) {
        if (g_ramdisk.entries[i].used) {
            count++;
            doldoc_printf("  $FG,YELLOW$[RAMFILE]$FG$ %s (%llu bytes)\n",
                          g_ramdisk.entries[i].name, (unsigned long long)g_ramdisk.entries[i].size);
        }
    }

    if (count == 0) {
        doldoc_print("  (RAMDisk is empty)\n");
    }
    doldoc_printf("$FG,YELLOW$--------------------------------------------------- (%d files)$FG$\n", count);
}
