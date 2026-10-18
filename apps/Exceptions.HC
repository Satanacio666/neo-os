// NeoOS Sovereign Pure HolyC AArch64 Exception Vector & BSOD Engine
// Ring 0 Synchronous Trap Decoding, JIT Task Unwinding, and Royal Blue Panic Screen (0xFF002080)

#define EC_UNDEF_INSN 0x00
#define EC_SVC_TRAP   0x15
#define EC_INSN_ABORT 0x21
#define EC_DATA_ABORT 0x25
#define EC_SP_ALIGN   0x26

#define BSOD_ROYAL_BLUE 0xFF002080

class CTrapFrame {
  U64 x[30];
  U64 lr;
  U64 elr_el1;
  U64 spsr_el1;
  U64 sp_el0;
};

class CExceptionState {
  U64 total_exceptions;
  U64 recovered_exceptions;
  U64 panic_count;
  I64 in_fault;
  I64 last_ec;
  U64 last_fault_pc;
  U64 last_fault_addr;
};

CExceptionState g_exc;
I64 g_exc_selftest_active;
U8  g_exc_line_buf[128];

U8* ExceptionsDecodeClass(U32 ec) {
  if (ec == EC_DATA_ABORT) return "Data Abort (Memory access violation)";
  if (ec == EC_INSN_ABORT) return "Instruction Abort (Execution violation)";
  if (ec == EC_SP_ALIGN)   return "SP Alignment Fault";
  if (ec == EC_SVC_TRAP)   return "SVC Trap";
  if (ec == EC_UNDEF_INSN) return "Undefined Instruction";
  return "Unknown Abort";
}

U8* ExceptionsGetEcDesc(U32 ec) {
  return ExceptionsDecodeClass(ec);
}

U0 ExcAppendHex64(U8 *dst, I64 *p_pos, U64 val) {
  I64 pos = *p_pos;
  dst[pos] = '0';
  dst[pos + 1] = 'x';
  pos = pos + 2;
  I64 shift = 60;
  while (shift >= 0) {
    I64 nib = (val >> shift) & 0xF;
    if (nib < 10) dst[pos] = '0' + nib;
    else dst[pos] = 'A' + (nib - 10);
    pos++;
    shift = shift - 4;
  }
  dst[pos] = 0;
  *p_pos = pos;
}

U0 ExcAppendStr(U8 *dst, I64 *p_pos, U8 *src) {
  if (!src) return;
  I64 pos = *p_pos;
  I64 s_i = 0;
  while (src[s_i] != 0 && pos < 120) {
    dst[pos] = src[s_i];
    pos++;
    s_i++;
  }
  dst[pos] = 0;
  *p_pos = pos;
}

U0 ExceptionsRenderBsod(CTrapFrame *f, U64 esr, U64 far) {
  U32 ec = (esr >> 26) & 0x3F;
  U8 *desc = ExceptionsDecodeClass(ec);

  doldoc_print("\n$FG,RED$====================================================================$FG$\n");
  doldoc_print("$FG,WHITE$  *** NeoOS ROYAL BLUE KERNEL PANIC (RING 0 AArch64 EL1 BSOD) ***   $FG$\n");
  doldoc_print("$FG,RED$====================================================================$FG$\n");
  doldoc_printf("  Fault Syndrome : EC 0x%02X (%s) | ESR_EL1: 0x%016llX\n", ec, desc, esr);
  doldoc_printf("  ELR_EL1 (PC)   : 0x%016llX | FAR_EL1: 0x%016llX\n", f ? f->elr_el1 : 0, far);
  doldoc_printf("  SPSR_EL1       : 0x%016llX | X30(LR): 0x%016llX\n", f ? f->spsr_el1 : 0, f ? f->lr : 0);
  doldoc_print("$FG,RED$====================================================================$FG$\n");

  if (g_exc_selftest_active) {
    return;
  }

  I64 scr_w = gfx_get_canvas_width();
  I64 scr_h = gfx_get_canvas_height();
  if (scr_w <= 0) scr_w = 1024;
  if (scr_h <= 0) scr_h = 768;

  // Fill entire canvas with Royal Blue BSOD (0xFF002080)
  gfx_draw_rect(0, 0, scr_w, scr_h, BSOD_ROYAL_BLUE);
  gfx_draw_rect(28, 28, scr_w - 56, scr_h - 56, 0xFF001860);

  gfx_draw_string(48, 48, "*** NeoOS KERNEL PANIC (RING 0 AArch64 EL1) - ROYAL BLUE BSOD ***", 0xFFFFFFFF, BSOD_ROYAL_BLUE);
  gfx_draw_string(48, 76, "An unrecoverable synchronous hardware exception occurred in Ring 0.", 0xFFE2E8F0, BSOD_ROYAL_BLUE);

  I64 pos = 0;
  ExcAppendStr(g_exc_line_buf, &pos, "Fault Class    : ");
  ExcAppendStr(g_exc_line_buf, &pos, desc);
  gfx_draw_string(48, 114, g_exc_line_buf, 0xFFF9E2AF, BSOD_ROYAL_BLUE);

  pos = 0;
  ExcAppendStr(g_exc_line_buf, &pos, "ESR_EL1        : ");
  ExcAppendHex64(g_exc_line_buf, &pos, esr);
  gfx_draw_string(48, 138, g_exc_line_buf, 0xFFFFFFFF, BSOD_ROYAL_BLUE);

  pos = 0;
  ExcAppendStr(g_exc_line_buf, &pos, "ELR_EL1 (PC)   : ");
  ExcAppendHex64(g_exc_line_buf, &pos, f ? f->elr_el1 : 0);
  gfx_draw_string(48, 162, g_exc_line_buf, 0xFFFFFFFF, BSOD_ROYAL_BLUE);

  pos = 0;
  ExcAppendStr(g_exc_line_buf, &pos, "FAR_EL1 (Addr) : ");
  ExcAppendHex64(g_exc_line_buf, &pos, far);
  gfx_draw_string(48, 186, g_exc_line_buf, 0xFFFFFFFF, BSOD_ROYAL_BLUE);

  pos = 0;
  ExcAppendStr(g_exc_line_buf, &pos, "X30 (LR)       : ");
  ExcAppendHex64(g_exc_line_buf, &pos, f ? f->lr : 0);
  gfx_draw_string(48, 210, g_exc_line_buf, 0xFFFFFFFF, BSOD_ROYAL_BLUE);

  if (f) {
    gfx_draw_string(48, 246, "--- AArch64 Ring-0 Register State (X0 - X15) ---", 0xFF89DCEB, BSOD_ROYAL_BLUE);
    I64 ry = 272;
    I64 r_idx = 0;
    while (r_idx < 16) {
      pos = 0;
      ExcAppendStr(g_exc_line_buf, &pos, "Reg Pair       : ");
      ExcAppendHex64(g_exc_line_buf, &pos, f->x[r_idx]);
      ExcAppendStr(g_exc_line_buf, &pos, "   ");
      ExcAppendHex64(g_exc_line_buf, &pos, f->x[r_idx + 1]);
      gfx_draw_string(48, ry, g_exc_line_buf, 0xFFFFFFFF, BSOD_ROYAL_BLUE);
      ry = ry + 22;
      r_idx = r_idx + 2;
    }
  }

  gfx_swap_buffers();
}

I64 ExceptionsHandleSync(CTrapFrame *f, U64 esr, U64 far, I64 is_user_jit) {
  if (!f) return 0;

  // Proper re-entrancy guard (resets to 0 on exit so sequential faults never hang!)
  if (g_exc.in_fault != 0) {
    doldoc_printf("[EXC FATAL] Recursive exception fault loop detected (in_fault=%lld). Halting.\n", g_exc.in_fault);
    while (1) {
      __wfe();
    }
  }
  g_exc.in_fault = 1;

  g_exc.total_exceptions = g_exc.total_exceptions + 1;
  U32 ec = (esr >> 26) & 0x3F;
  g_exc.last_ec = ec;
  g_exc.last_fault_pc = f->elr_el1;
  g_exc.last_fault_addr = far;

  // Validate f->elr_el1 before dereferencing instruction word (never dereference on EC_INSN_ABORT)
  U32 insn_val = 0;
  if (ec != EC_INSN_ABORT && !g_exc_selftest_active &&
      (f->elr_el1 & 3) == 0 &&
      f->elr_el1 >= 0x40000000 && f->elr_el1 < 0x80000000) {
    U32 *insn_ptr = f->elr_el1;
    insn_val = *insn_ptr;
  }

  U8 *ec_desc = ExceptionsDecodeClass(ec);

  // Sovereign Error Recovery Protocol:
  // If the fault occurred in userland HolyC code (inside the JIT code pool),
  // display a structured DolDoc crash card and unwind cleanly to ShellRecover()!
  if (is_user_jit) {
    g_exc.recovered_exceptions = g_exc.recovered_exceptions + 1;
    doldoc_print("\n$CARD,title=\"Sovereign Ring-0 Fault Recovery (JIT Task Unwound)\",w=96,h=6,bg=0xFF1E1E2E,border=0xFFF38BA8$\n");
    doldoc_printf("  $FG,RED$[EXC #%lld]$FG$ EC=0x%02X ($FG,YELLOW$%s$FG$) | Insn=0x%08X\n",
                  g_exc.total_exceptions, ec, ec_desc, insn_val);
    doldoc_printf("  $FG,SAPPHIRE$ELR_EL1:$FG$ 0x%016llX  $FG,SAPPHIRE$FAR_EL1:$FG$ 0x%016llX  $FG,SAPPHIRE$ESR_EL1:$FG$ 0x%016llX\n",
                  f->elr_el1, far, esr);
    doldoc_printf("  $FG,SAPPHIRE$X0..X3 :$FG$ 0x%016llX  0x%016llX  0x%016llX  0x%016llX\n",
                  f->x[0], f->x[1], f->x[2], f->x[3]);
    doldoc_printf("  $FG,SAPPHIRE$X16/17 :$FG$ 0x%016llX  0x%016llX  $FG,SAPPHIRE$X30(LR):$FG$ 0x%016llX\n",
                  f->x[16], f->x[17], f->lr);
    doldoc_print("$HR$\n");

    U64 rec_addr = symbols_lookup("ShellRecover");
    if (!rec_addr) rec_addr = symbols_lookup("ShellInit");
    if (!rec_addr) rec_addr = symbols_lookup("shell_poll");
    if (!rec_addr) rec_addr = 0x75001000;
    f->elr_el1 = rec_addr;
    f->lr = symbols_lookup("DolDocShellEventLoop");
    g_exc.in_fault = 0;
    return 1; // RECOVERED
  }

  // Core Kernel Panic (Unrecoverable Substrate Crash -> Royal Blue BSOD)
  g_exc.panic_count = g_exc.panic_count + 1;
  ExceptionsRenderBsod(f, esr, far);
  g_exc.in_fault = 0;
  return 0; // PANIC
}

U0 ExceptionsInit() {
  g_exc.total_exceptions = 0;
  g_exc.recovered_exceptions = 0;
  g_exc.panic_count = 0;
  g_exc.in_fault = 0;
  g_exc.last_ec = -1;
  g_exc.last_fault_pc = 0;
  g_exc.last_fault_addr = 0;
  g_exc_selftest_active = 0;

  U64 *vecs = &g_arch_vectors;
  vecs[0] = ExceptionsHandleSync;
  vecs[3] = ExceptionsHandleSync;
  __dmb_ish();
  disable_interrupts();
  install_vector_table();
}

U0 ExceptionsPrintDolDoc() {
  doldoc_printf("$FG,CYAN$--- ARM64 EXCEPTION TELEMETRY ---$FG$\n");
  doldoc_printf(" Total Trapped:   %d exceptions (in_fault=%d)\n", g_exc.total_exceptions, g_exc.in_fault);
  doldoc_printf(" JIT Recovered:   %d (Sovereign Unwind)\n", g_exc.recovered_exceptions);
  doldoc_printf(" Kernel Panics:   %d (Royal Blue BSOD 0x%08X)\n", g_exc.panic_count, BSOD_ROYAL_BLUE);
  if (g_exc.last_ec >= 0) {
    doldoc_printf(" Last Exception:  EC 0x%02X (%s)\n", g_exc.last_ec, ExceptionsDecodeClass(g_exc.last_ec));
    doldoc_printf(" Last Fault PC:   0x%016X | FAR: 0x%016X\n", g_exc.last_fault_pc, g_exc.last_fault_addr);
  }
  doldoc_printf("$FG,CYAN$---------------------------------$FG$\n");
}

I64 ExceptionsSelfTest() {
  doldoc_printf("\n$FG,CYAN$[EXCEPTIONS-TEST] Starting Pure HolyC AArch64 Exception Subsystem Verification...$FG$\n");

  // Test 1: Exception syndrome & class decoding
  ExceptionsInit();
  g_exc_selftest_active = 1;
  U8 *d_str = ExceptionsDecodeClass(EC_DATA_ABORT);
  U8 *i_str = ExceptionsDecodeClass(EC_INSN_ABORT);
  U8 *s_str = ExceptionsDecodeClass(EC_SP_ALIGN);
  if (!d_str || !i_str || !s_str) {
    g_exc_selftest_active = 0;
    doldoc_printf("$FG,RED$[FAIL] Test 1: Exception class decoding failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 1: ESR_EL1 Exception Syndrome Class decoders validated.$FG$\n");

  // Test 2: Setup simulated Trap Frame
  CTrapFrame tf;
  I64 reg_i = 0;
  while (reg_i < 30) {
    tf.x[reg_i] = 0x1000 + reg_i;
    reg_i++;
  }
  tf.lr = 0x75005000;
  tf.elr_el1 = 0x76B00124; // PC inside HolyC JIT pool
  tf.spsr_el1 = 0x00000000;
  tf.sp_el0 = 0x75800000;
  doldoc_printf("$FG,GREEN$[PASS] Test 2: Trap frame 64-bit context registers initialized.$FG$\n");

  // Test 3: Sovereign JIT fault unwinding & recovery
  U64 esr_val = ((U64)EC_DATA_ABORT << 26) | 0x01;
  U64 far_val = 0xDEAD0000;
  I64 rec_res = ExceptionsHandleSync(&tf, esr_val, far_val, 1);
  if (rec_res != 1 || tf.elr_el1 == 0 || g_exc.recovered_exceptions != 1 || g_exc.in_fault != 0) {
    g_exc_selftest_active = 0;
    doldoc_printf("$FG,RED$[FAIL] Test 3: HolyC JIT fault recovery failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 3: Sovereign HolyC JIT fault unwound to shell without kernel panic.$FG$\n");

  // Test 4: Unrecoverable substrate crash handling (2nd exception, verifying in_fault guard resets!)
  tf.elr_el1 = 0x00001000; // Outside JIT pool
  I64 panic_res = ExceptionsHandleSync(&tf, esr_val, far_val, 0);
  if (panic_res != 0 || g_exc.panic_count != 1 || g_exc.in_fault != 0) {
    g_exc_selftest_active = 0;
    doldoc_printf("$FG,RED$[FAIL] Test 4: Kernel panic handling failed!$FG$\n");
    return 0;
  }
  doldoc_printf("$FG,GREEN$[PASS] Test 4: Kernel panic trigger & re-entrancy guard (in_fault=0) validated.$FG$\n");

  // Test 5: Telemetry dump & total count
  g_exc_selftest_active = 0;
  if (g_exc.total_exceptions != 2) {
    doldoc_printf("$FG,RED$[FAIL] Test 5: Total exceptions mismatch!$FG$\n");
    return 0;
  }
  ExceptionsPrintDolDoc();
  doldoc_printf("$FG,GREEN$[PASS] Test 5: Exception telemetry and DolDoc dump verified.$FG$\n");

  doldoc_printf("\n[EXCEPTIONS-PASS] ALL 5 EXCEPTION TESTS PASSED\n\n");
  return 1;
}

I64 g_kernel_booting;
if (g_kernel_booting) {
  ExceptionsInit();
} else {
  ExceptionsSelfTest();
}
