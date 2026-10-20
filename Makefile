# NeoOS AArch64 Makefile
# Architecture: aarch64 (ARM64)
# Target: UEFI Application (BOOTAA64.EFI)

ARCH = aarch64
CC = aarch64-linux-gnu-gcc
AS = aarch64-linux-gnu-as
LD = aarch64-linux-gnu-ld
OBJCOPY = aarch64-linux-gnu-objcopy
AR = aarch64-linux-gnu-ar

# Locate a FAT image tool across distros (dosfstools ships mkfs.vfat or mkfs.fat).
MKFS_VFAT := $(shell command -v mkfs.vfat 2>/dev/null || command -v mkfs.fat 2>/dev/null \
	|| { [ -x /usr/sbin/mkfs.vfat ] && echo /usr/sbin/mkfs.vfat; } \
	|| { [ -x /sbin/mkfs.vfat ] && echo /sbin/mkfs.vfat; } \
	|| echo mkfs.vfat)

BUILD_DIR = build
TARGET_EFI = $(BUILD_DIR)/BOOTAA64.EFI
TARGET_SO = $(BUILD_DIR)/boot.so
DISK_IMG = $(BUILD_DIR)/disk.img
REDSEA_IMG = $(BUILD_DIR)/redsea.img

UEFI_DIR = boot/uefi

SRCS_C = boot/main.c \
         boot/seed/lexer.c \
         boot/seed/table.c \
         boot/seed/jit_arm64.c \
         drivers/block/virtio_blk.c \
         fs/redsea.c \
         kernel/mem/kheap.c \
         kernel/symbols/symbols.c \
         kernel/arch/aarch64/hal_platform.c

SRCS_S = kernel/sched/switch.S \
         kernel/arch/aarch64/vectors.S \
         kernel/arch/aarch64/smp_entry.S \
         kernel/arch/aarch64/ffi_arm64.S

OBJS_C = $(patsubst %.c, $(BUILD_DIR)/%.o, $(SRCS_C))
OBJS_S = $(patsubst %.S, $(BUILD_DIR)/%.o, $(SRCS_S))
ALL_OBJS = $(OBJS_C) $(OBJS_S)

CFLAGS = -fshort-wchar -fno-strict-aliasing -ffreestanding -fno-stack-protector \
         -fno-stack-check -I$(UEFI_DIR) -Ikernel -Iboot/seed -Igui -Idrivers -Ifs -D__aarch64__ \
         -Wno-builtin-declaration-mismatch -fpic -fPIC -O2 -Wall -MMD -MP

ASFLAGS = -Ikernel

LDFLAGS = -nostdlib -shared -Bsymbolic -T $(UEFI_DIR)/elf_aarch64_efi.lds -L$(UEFI_DIR)
LIBS = $(UEFI_DIR)/crt_aarch64.o $(UEFI_DIR)/reloc.o $(ALL_OBJS) -luefi

QEMU = taskset -c 0 qemu-system-aarch64
QEMU_BIOS = /usr/share/qemu-efi-aarch64/QEMU_EFI.fd
QEMU_FLAGS = -M virt,gic-version=2 \
             -accel tcg,thread=single,tb-size=512 \
             -cpu cortex-a72 \
             -smp 4 \
             -m 1024 \
             -bios $(QEMU_BIOS) \
             -device ramfb \
             -device virtio-gpu-device,xres=1024,yres=768 \
             -device virtio-keyboard-device \
             -device virtio-tablet-device \
             -device usb-ehci \
             -device usb-kbd \
             -device usb-tablet \
             -net none \
             -drive file=$(DISK_IMG),format=raw,id=disk,if=none \
             -device virtio-blk-pci,drive=disk,bootindex=0 \
             -drive file=$(REDSEA_IMG),format=raw,id=redsea,if=none \
             -device virtio-blk-device,drive=redsea \
             -display gtk \
             -serial stdio

.PHONY: all clean run run-headless disk libuefi check-tools

check-tools:
	@missing=""; \
	for t in $(CC) $(LD) $(OBJCOPY) $(AR) $(AS) dd mmd mcopy $(MKFS_VFAT); do \
	  if [ -x "$$t" ] || command -v "$$t" >/dev/null 2>&1; then :; else missing="$$missing $$t"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
	  echo "ERROR: missing build dependencies:$$missing"; \
	  echo "  Debian/Ubuntu: sudo apt-get install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu dosfstools mtools"; \
	  exit 1; \
	fi

all: check-tools $(TARGET_EFI) disk

libuefi: $(UEFI_DIR)/reloc.o
	$(MAKE) -C $(UEFI_DIR) ARCH=aarch64 USE_GCC=1

$(UEFI_DIR)/reloc.o: $(UEFI_DIR)/reloc.S
	$(AS) $< -o $@

$(BUILD_DIR)/%.o: %.c | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: %.S | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(TARGET_SO): $(ALL_OBJS) libuefi
	$(LD) $(LDFLAGS) $(LIBS) -o $@

$(TARGET_EFI): $(TARGET_SO)
	$(OBJCOPY) -j .text -j .sdata -j .data -j .dynamic -j .dynsym \
	           -j .rel -j .rela -j .rel.* -j .rela.* -j .reloc \
	           --target pei-aarch64-little --subsystem=10 $< $@
	@echo ">>> Successfully built $(TARGET_EFI) <<<"

disk: $(TARGET_EFI)
	@echo "Creating FAT32 UEFI bootable disk image..."
	dd if=/dev/zero of=$(DISK_IMG) bs=1M count=64 status=none
	$(MKFS_VFAT) -F 32 $(DISK_IMG) >/dev/null
	mmd -i $(DISK_IMG) ::/EFI
	mmd -i $(DISK_IMG) ::/EFI/BOOT
	mcopy -i $(DISK_IMG) $(TARGET_EFI) ::/EFI/BOOT/BOOTAA64.EFI
	@printf "FS0:\r\ncd EFI\\\\BOOT\r\nBOOTAA64.EFI\r\n" > $(BUILD_DIR)/startup.nsh
	mcopy -i $(DISK_IMG) $(BUILD_DIR)/startup.nsh ::/startup.nsh
	@echo "Packaging RedSea 32MB disk image from apps/..."
	python3 scripts/mkredsea.py $(REDSEA_IMG) apps/
	@echo ">>> Boot disk image ready at $(DISK_IMG) <<<"

run: all
	@echo "Launching QEMU AArch64..."
	$(QEMU) $(QEMU_FLAGS)

run-singlecore: all
	@echo "Launching QEMU AArch64 (Single Core, Host taskset -c 0)..."
	$(QEMU) $(subst -smp 4,-smp 1,$(QEMU_FLAGS))

run-headless: all
	@echo "Launching QEMU AArch64 (Headless)..."
	$(QEMU) $(QEMU_FLAGS) -display none -monitor unix:/tmp/qemu-mon.sock,server,nowait

clean:
	rm -rf $(BUILD_DIR)
	$(MAKE) -C $(UEFI_DIR) clean 2>/dev/null || true

-include $(ALL_OBJS:.o=.d)
