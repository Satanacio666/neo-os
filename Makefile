# NeoOS AArch64 Makefile
# Architecture: aarch64 (ARM64)
# Target: UEFI Application (BOOTAA64.EFI)

ARCH = aarch64
CC = aarch64-linux-gnu-gcc
AS = aarch64-linux-gnu-as
LD = aarch64-linux-gnu-ld
OBJCOPY = aarch64-linux-gnu-objcopy
AR = aarch64-linux-gnu-ar

BUILD_DIR = build
TARGET_EFI = $(BUILD_DIR)/BOOTAA64.EFI
TARGET_SO = $(BUILD_DIR)/boot.so
DISK_IMG = $(BUILD_DIR)/disk.img
REDSEA_IMG = $(BUILD_DIR)/redsea.img

UEFI_DIR = boot/uefi

SRCS_C = boot/main.c \
         kernel/mem/kheap.c \
         kernel/symbols/symbols.c \
         kernel/sched/sched.c \
         kernel/arch/aarch64/gic.c \
         kernel/arch/aarch64/timer.c \
         kernel/arch/aarch64/exceptions.c \
         compiler/lexer.c \
         compiler/table.c \
         compiler/jit_arm64.c \
         compiler/lua_bridge.c \
         compiler/lua_compat.c \
         gui/render.c \
         gui/wm.c \
         gui/shell.c \
         drivers/input/keyboard.c \
         drivers/input/mouse.c \
         drivers/block/virtio_blk.c \
         fs/redsea.c \
         kernel/arch/aarch64/smp.c \
         gui/font_ubuntu_mono.c \
         gui/font_ttf.c \
         kernel/math/math3d.c \
         kernel/math/raster_tile.c \
         kernel/physics/physics3d.c \
         drivers/gpu/gfx_backend.c \
         drivers/gpu/virtio_gpu.c \
         kernel/math/gears3d.c \
         kernel/math/holygl.c \
         kernel/bench/bench_unified.c \
         kernel/bench/perf_overlay.c \
         gui/apps_gui.c \
         gui/menu.c

SRCS_S = kernel/sched/switch.S \
         kernel/arch/aarch64/vectors.S \
         kernel/arch/aarch64/smp_entry.S \
         kernel/arch/aarch64/ffi_arm64.S

OBJS_C = $(patsubst %.c, $(BUILD_DIR)/%.o, $(SRCS_C))
OBJS_S = $(patsubst %.S, $(BUILD_DIR)/%.o, $(SRCS_S))
ALL_OBJS = $(OBJS_C) $(OBJS_S)

CFLAGS = -fshort-wchar -fno-strict-aliasing -ffreestanding -fno-stack-protector \
         -fno-stack-check -I$(UEFI_DIR) -Ikernel -Icompiler -Igui -Idrivers -Ifs -Icompiler/lua -D__aarch64__ \
         -Wno-builtin-declaration-mismatch -fpic -fPIC -O2 -Wall -MMD -MP

ASFLAGS = -Ikernel

LDFLAGS = -nostdlib -shared -Bsymbolic -T $(UEFI_DIR)/elf_aarch64_efi.lds -L$(UEFI_DIR) -Lcompiler/lua
LIBS = $(UEFI_DIR)/crt_aarch64.o $(UEFI_DIR)/reloc.o $(ALL_OBJS) -luefi -llua

QEMU = taskset -c 0 qemu-system-aarch64
QEMU_BIOS = /usr/share/qemu-efi-aarch64/QEMU_EFI.fd
QEMU_FLAGS = -M virt,gic-version=2 \
             -accel tcg,thread=single,tb-size=256 \
             -cpu cortex-a72 \
             -smp 4 \
             -m 1024 \
             -bios $(QEMU_BIOS) \
             -device ramfb \
             -device virtio-gpu-device,xres=1024,yres=768 \
             -device usb-ehci \
             -device usb-tablet \
             -net none \
             -drive file=$(DISK_IMG),format=raw,id=disk,if=none \
             -device virtio-blk-pci,drive=disk,bootindex=0 \
             -drive file=$(REDSEA_IMG),format=raw,id=redsea,if=none \
             -device virtio-blk-device,drive=redsea \
             -display sdl \
             -serial stdio

.PHONY: all clean run run-headless disk libuefi

all: $(TARGET_EFI) disk

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

compiler/lua/liblua.a:
	$(MAKE) -C compiler/lua

$(TARGET_SO): $(ALL_OBJS) libuefi compiler/lua/liblua.a
	$(LD) $(LDFLAGS) $(LIBS) -o $@

$(TARGET_EFI): $(TARGET_SO)
	$(OBJCOPY) -j .text -j .sdata -j .data -j .dynamic -j .dynsym \
	           -j .rel -j .rela -j .rel.* -j .rela.* -j .reloc \
	           --target pei-aarch64-little --subsystem=10 $< $@
	@echo ">>> Successfully built $(TARGET_EFI) <<<"

disk: $(TARGET_EFI)
	@echo "Creating FAT32 UEFI bootable disk image..."
	dd if=/dev/zero of=$(DISK_IMG) bs=1M count=64 status=none
	/usr/sbin/mkfs.vfat -F 32 $(DISK_IMG) >/dev/null
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

run-headless: all
	@echo "Launching QEMU AArch64 (Headless)..."
	$(QEMU) $(QEMU_FLAGS) -display none -monitor unix:/tmp/qemu-mon.sock,server,nowait

clean:
	rm -rf $(BUILD_DIR)
	$(MAKE) -C $(UEFI_DIR) clean 2>/dev/null || true
	$(MAKE) -C compiler/lua clean 2>/dev/null || true

-include $(ALL_OBJS:.o=.d)
