#ifndef NEO_VIRTIO_BLK_H
#define NEO_VIRTIO_BLK_H

#include <uefi.h>

#define VIRTIO_MMIO_MAGIC          0x74726976 // "virt"
#define VIRTIO_DEV_BLOCK           2          // Block device ID

// VirtIO MMIO Register Offsets
#define VIRTIO_MMIO_MAGIC_VALUE    0x000
#define VIRTIO_MMIO_VERSION        0x004
#define VIRTIO_MMIO_DEVICE_ID      0x008
#define VIRTIO_MMIO_VENDOR_ID      0x00C
#define VIRTIO_MMIO_DEVICE_FEATURES 0x010
#define VIRTIO_MMIO_DEVICE_FEATURES_SEL 0x014
#define VIRTIO_MMIO_DRIVER_FEATURES 0x020
#define VIRTIO_MMIO_DRIVER_FEATURES_SEL 0x024
#define VIRTIO_MMIO_QUEUE_SEL      0x030
#define VIRTIO_MMIO_QUEUE_NUM_MAX  0x034
#define VIRTIO_MMIO_QUEUE_NUM      0x038
#define VIRTIO_MMIO_QUEUE_READY    0x044
#define VIRTIO_MMIO_QUEUE_NOTIFY   0x050
#define VIRTIO_MMIO_INTERRUPT_STATUS 0x060
#define VIRTIO_MMIO_INTERRUPT_ACK  0x064
#define VIRTIO_MMIO_STATUS         0x070
#define VIRTIO_MMIO_QUEUE_DESC_LOW 0x080
#define VIRTIO_MMIO_QUEUE_DESC_HIGH 0x084
#define VIRTIO_MMIO_QUEUE_DRIVER_LOW 0x090
#define VIRTIO_MMIO_QUEUE_DRIVER_HIGH 0x094
#define VIRTIO_MMIO_QUEUE_DEVICE_LOW 0x0A0
#define VIRTIO_MMIO_QUEUE_DEVICE_HIGH 0x0A4
#define VIRTIO_MMIO_CONFIG         0x100

// Device Status bits
#define VIRTIO_STATUS_ACKNOWLEDGE  1
#define VIRTIO_STATUS_DRIVER       2
#define VIRTIO_STATUS_DRIVER_OK    4
#define VIRTIO_STATUS_FEATURES_OK  8

// Virtqueue Descriptor Flags
#define VRING_DESC_F_NEXT          1
#define VRING_DESC_F_WRITE         2

// VirtIO Block Request Types
#define VIRTIO_BLK_T_IN            0 // Read
#define VIRTIO_BLK_T_OUT           1 // Write
#define VIRTIO_BLK_T_FLUSH         4

#define VIRTIO_QUEUE_SIZE          256
#define SECTOR_SIZE                512

typedef struct {
    uint64_t addr;
    uint32_t len;
    uint16_t flags;
    uint16_t next;
} __attribute__((packed)) vring_desc_t;

typedef struct {
    uint16_t flags;
    uint16_t idx;
    uint16_t ring[VIRTIO_QUEUE_SIZE];
    uint16_t used_event;
} __attribute__((packed)) vring_avail_t;

typedef struct {
    uint32_t id;
    uint32_t len;
} __attribute__((packed)) vring_used_elem_t;

typedef struct {
    uint16_t flags;
    uint16_t idx;
    vring_used_elem_t ring[VIRTIO_QUEUE_SIZE];
    uint16_t avail_event;
} __attribute__((packed)) vring_used_t;

typedef struct {
    uint32_t type;
    uint32_t reserved;
    uint64_t sector;
} __attribute__((packed)) virtio_blk_req_t;

int      virtio_blk_init(void);
int      virtio_blk_read_sectors(uint64_t lba, uint32_t count, void *buffer);
int      virtio_blk_write_sectors(uint64_t lba, uint32_t count, const void *buffer);
uint64_t virtio_blk_get_capacity(void);

#endif // NEO_VIRTIO_BLK_H
