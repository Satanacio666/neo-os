// NeoOS — EL2 -> EL1 drop (P1.1 / D36)
//
// The UEFI AArch64 handoff EL is firmware-dependent: EDK2/AAVMF on QEMU enters the
// payload at EL1, but U-Boot (and real firmware such as Renegade EDK2 on Snapdragon)
// enters it at EL2. Measured on this project:
//
//   qemu -M virt                    -> PSTATE.M = 0x5 (EL1h)
//   qemu -M virt,virtualization=on  -> PSTATE.M = 0x9 (EL2h)
//
// At EL2 the NeoOS still *runs*, but every EL1 write (VBAR_EL1, TTBR0_EL1, SCTLR_EL1,
// CNTV_CTL_EL0) is accepted and silently has no effect on the executing EL. The boot
// then derails into an endless module-recompile loop with NO exception taken — the
// tier-0 reporter never fires, so the failure is invisible. This routine removes that
// whole class of failure by making the OS always execute where it was designed to.
//
// Returns:
//   1 = already at EL1 (no-op, zero regression on AAVMF)
//   2 = was at EL2 and dropped to EL1
//
// Note on SCTLR_EL2: we deliberately DO NOT clear SCTLR_EL2.M here. EL1 execution uses
// the SCTLR_EL1/TTBR0_EL1 translation regime; SCTLR_EL2 only governs EL2 accesses, and
// after `eret` we never execute at EL2 again. Stage-2 translation is disabled by
// HCR_EL2.VM=0, which is what actually matters for EL1 seeing physical RAM 1:1.
// Clearing SCTLR_EL2.M/C without prior cache maintenance is the riskier move.

.global neo_get_current_el
.global neo_ensure_el1

// uint32_t neo_get_current_el(void)
neo_get_current_el:
    mrs     x0, CurrentEL
    lsr     x0, x0, #2
    and     x0, x0, #3
    ret

// uint32_t neo_ensure_el1(void)
neo_ensure_el1:
    mrs     x0, CurrentEL
    lsr     x0, x0, #2
    and     x0, x0, #3
    cmp     x0, #2
    b.ne    .Lneo_already_el1

    // ---- executing at EL2: prepare the drop ----

    // 1. HCR_EL2: RW=1 (EL1 is AArch64), VM=0 (no stage-2 -> EL1 sees physical RAM 1:1),
    //    IMO/FMO/AMO=0 (physical IRQ/FIQ/SError are NOT routed to EL2; they stay at EL1).
    mov     x1, #1
    lsl     x1, x1, #31
    msr     hcr_el2, x1

    // 2. CNTHCTL_EL2: EL1PCTEN | EL1PCEN -> EL1 may use the physical and virtual timers.
    mov     x1, #3
    msr     cnthctl_el2, x1
    msr     cntvoff_el2, xzr

    // 3. FP/SIMD: CPTR_EL2=0x33ff clears TFP (bit 10) so no FP trap at EL2, and
    //    CPACR_EL1.FPEN=0b11 gives full FP/SIMD access at EL1/EL0.
    //    The HolyC JIT emits D0-D31/V0-V31 traffic, so a trapped FP instruction would
    //    vector through VBAR_EL2 into the firmware.
    mov     x1, #0x33ff
    msr     cptr_el2, x1
    msr     hstr_el2, xzr
    mov     x1, #(3 << 20)
    msr     cpacr_el1, x1

    // 4. MDCR_EL2: keep HPMN[4:0], clear the debug/PMU trap bits (TDE/TDA/TPM/...).
    //    (0x1f is not a valid A64 bitmask immediate -> mask through a register.)
    mrs     x1, mdcr_el2
    mov     x2, #0x1f
    and     x1, x1, x2
    msr     mdcr_el2, x1

    // 5. GICv3: ID_AA64PFR0_EL1.GIC[27:24] != 0 means the CPU implements the GIC system
    //    registers. Without ICC_SRE_EL2.SRE=1 | Enable=1 the first ICC_*_EL1 access at
    //    EL1 raises Undefined Instruction. This is required for P2.1.
    mrs     x1, id_aa64pfr0_el1
    ubfx    x2, x1, #24, #4
    cbz     x2, .Lneo_no_gicv3
    mrs     x1, s3_4_c12_c9_5          // ICC_SRE_EL2
    orr     x1, x1, #1                 // SRE   (bit 0)
    orr     x1, x1, #8                 // Enable (bit 3)  -- 0x9 is not a bitmask immediate
    msr     s3_4_c12_c9_5, x1
    isb
.Lneo_no_gicv3:

    // 6. Expose the real CPU identity to EL1 through the virtualization registers.
    mrs     x1, midr_el1
    msr     vpidr_el2, x1
    mrs     x1, mpidr_el1
    msr     vmpidr_el2, x1

    // 7. Herdar o regime de traducao do EL2 para o EL1.
    //
    // MOTIVO (medido): com SCTLR_EL1 = 0x30D00800 (MMU off), o EL1 passa a usar
    // enderecamento FISICO. Se o firmware mapeou a memoria por tabelas (TTBR0_EL2)
    // que nao sao identidade, os acessos do EL1 vao para o lugar errado. Sintoma
    // medido sob U-Boot: escrita crua em MMIO e chamadas simples funcionam, mas
    // vsnprintf() retorna sem escrever nada e locais de pilha leem dado velho.
    // Copiando TTBR0/MAIR/TCR do EL2, o EL1 herda o MESMO mapeamento e os MESMOS
    // atributos de memoria que o firmware montou, e a MMU/D-Cache seguem ligadas.
    mrs     x1, ttbr0_el2
    msr     ttbr0_el1, x1

    mrs     x1, mair_el2
    msr     mair_el1, x1

    // TCR_EL2 -> TCR_EL1: T0SZ/IRGN0/ORGN0/SH0/TG0 ficam nos mesmos bits;
    // PS (TCR_EL2[18:16]) vira IPS (TCR_EL1[34:32]).
    mrs     x1, tcr_el2
    mov     x2, #0xffff
    and     x3, x1, x2
    ubfx    x2, x1, #16, #3
    bfi     x3, x2, #32, #3
    // EPD1 (bit 23) = 1: desabilita os walks por TTBR1_EL1.
    // BUG CORRIGIDO: o `and x3, x1, #0xffff` acima zera o bit 23, o que LIGA os
    // walks por TTBR1_EL1 com TTBR1_EL1 = 0 (nunca inicializado). Nosso espaco de
    // enderecos e todo TTBR0, entao hoje isso nao e exercitado — mas qualquer
    // acesso futuro na metade alta do espaco daria translation fault. Desabilitar
    // e o correto: nao usamos TTBR1.
    orr     x3, x3, #(1 << 23)
    msr     tcr_el1, x3

    // SCTLR_EL1: bits RES1 (0x30D00800) + herda M (bit 0), C (bit 2), I (bit 12)
    // do SCTLR_EL2. Sem isso a MMU e a D-Cache ficam desligadas em EL1.
    mrs     x2, sctlr_el2
    mov     x3, #0x1005
    and     x2, x2, x3
    movz    x1, #0x0800
    movk    x1, #0x30d0, lsl #16
    orr     x1, x1, x2
    msr     sctlr_el1, x1

    tlbi    vmalle1
    dsb     sy
    isb

    // 8. Carry the C stack across: EL1h uses SP_EL1.
    mov     x1, sp
    msr     sp_el1, x1

    // 9. SPSR_EL2 = 0x3C5 -> M[3:0]=0b0101 (EL1h), M[4]=0 (AArch64), DAIF all masked.
    mov     x1, #0x3c5
    msr     spsr_el2, x1
    adr     x1, .Lneo_el1_entry
    msr     elr_el2, x1
    dsb     sy
    isb
    eret                                // <-- now executing at EL1

.Lneo_el1_entry:
    mov     x0, #2
    ret

.Lneo_already_el1:
    mov     x0, #1
    ret
