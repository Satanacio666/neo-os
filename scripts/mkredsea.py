#!/usr/bin/env python3
"""
mkredsea.py - Host tool to format a 32MB RedSea filesystem image from local files.
Creates a valid contiguous RedSea partition image compatible with NeoOS virtio-blk.
"""

import sys
import os
import struct

SECTOR_SIZE = 512
DISK_SIZE = 32 * 1024 * 1024  # 32MB
TOTAL_SECTORS = DISK_SIZE // SECTOR_SIZE  # 65536 sectors
PARTITION_LBA = 1
ROOT_SECTORS = 16
ENTRIES_PER_SECTOR = SECTOR_SIZE // 64  # 8
MAX_ROOT_ENTRIES = ROOT_SECTORS * ENTRIES_PER_SECTOR  # 128

RS_ATTR_FILE = 0x40
RS_ATTR_DIR  = 0x10

def build_redsea_image(output_img_path, source_dir):
    print(f"[mkredsea] Creating {DISK_SIZE // (1024*1024)}MB RedSea image at: {output_img_path}")
    image = bytearray(DISK_SIZE)
    
    # Root directory entries start at PARTITION_LBA (sector 1)
    root_dir_offset = PARTITION_LBA * SECTOR_SIZE
    current_data_cluster = PARTITION_LBA + ROOT_SECTORS  # sector 17
    
    files = sorted([f for f in os.listdir(source_dir) if os.path.isfile(os.path.join(source_dir, f))])
    if len(files) > MAX_ROOT_ENTRIES:
        raise ValueError(f"Too many files ({len(files)}) for root directory (max {MAX_ROOT_ENTRIES})")
        
    entry_idx = 0
    for filename in files:
        filepath = os.path.join(source_dir, filename)
        with open(filepath, 'rb') as f:
            data = f.read()
            
        file_size = len(data)
        sectors_needed = max(1, (file_size + SECTOR_SIZE - 1) // SECTOR_SIZE)
        
        # Check disk boundary
        if current_data_cluster + sectors_needed > TOTAL_SECTORS:
            raise ValueError(f"Disk full! Cannot fit file {filename}")
            
        # Write file payload contiguously
        payload_offset = current_data_cluster * SECTOR_SIZE
        image[payload_offset : payload_offset + file_size] = data
        
        # Build packed 64-byte directory entry:
        # struct { uint16 attr; char name[38]; uint64 cluster; uint64 size; uint64 datetime; }
        name_bytes = filename.encode('ascii')[:37]  # Ensure null-terminated
        name_padded = name_bytes + b'\x00' * (38 - len(name_bytes))
        
        entry_bytes = struct.pack(
            '<H38sQQQ',
            RS_ATTR_FILE,
            name_padded,
            current_data_cluster,
            file_size,
            0x202609250000
        )
        
        entry_offset = root_dir_offset + (entry_idx * 64)
        image[entry_offset : entry_offset + 64] = entry_bytes
        
        print(f"  [+] Injected {filename:16s} ({file_size:5d} bytes) @ LBA {current_data_cluster}..{current_data_cluster + sectors_needed - 1}")
        current_data_cluster += sectors_needed
        entry_idx += 1
        
    # Write image to disk
    os.makedirs(os.path.dirname(os.path.abspath(output_img_path)), exist_ok=True)
    with open(output_img_path, 'wb') as f:
        f.write(image)
        
    print(f"[mkredsea] Successfully packaged {entry_idx} files into {output_img_path} (Watermark LBA: {current_data_cluster})")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python3 mkredsea.py <output_image> <source_directory>")
        sys.exit(1)
    build_redsea_image(sys.argv[1], sys.argv[2])
