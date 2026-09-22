/*
 * reloc.S - Clean PE/COFF Base Relocation Section for UEFI AArch64
 *
 * Provides exactly one 16-byte base relocation block with two dummy entries.
 * Block size strictly matches section size to prevent EDK2 PeCoffLoader failure.
 */

.data
.align 4
dummy_reloc:
    .long 0

.section .reloc, "a"
.balign 4
reloc_block_start:
    .long dummy_reloc - reloc_block_start  /* Page RVA */
    .long reloc_block_end - reloc_block_start /* Size of Block = 16 */
    .word 0                                /* Entry 0: IMAGE_REL_BASED_ABSOLUTE */
    .word 0                                /* Entry 1: IMAGE_REL_BASED_ABSOLUTE */
    .word 0                                /* Entry 2: IMAGE_REL_BASED_ABSOLUTE */
    .word 0                                /* Entry 3: IMAGE_REL_BASED_ABSOLUTE */
reloc_block_end:
