#ifndef NEO_VIRTIO_INPUT_H
#define NEO_VIRTIO_INPUT_H

#include <uefi.h>

#define VIRTIO_DEV_INPUT 18

// Linux input event types
#define EV_SYN 0x00
#define EV_KEY 0x01
#define EV_REL 0x02
#define EV_ABS 0x03

// Absolute axes
#define ABS_X 0x00
#define ABS_Y 0x01

// Relative axes
#define REL_X 0x00
#define REL_Y 0x01

// Mouse buttons
#define BTN_MOUSE   0x110
#define BTN_LEFT    0x110
#define BTN_RIGHT   0x111
#define BTN_MIDDLE  0x112

typedef struct {
    uint16_t type;
    uint16_t code;
    uint32_t value;
} __attribute__((packed)) virtio_input_event_t;

int  virtio_input_init(uint32_t screen_width, uint32_t screen_height);
void virtio_input_poll(void);
int  virtio_input_is_active(void);

#endif // NEO_VIRTIO_INPUT_H
