// ==============================================================================
// calc.HC - Sovereign Scientific Calculator & Algebraic Expression Workbench
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT & Hardware FPU
// ==============================================================================

I64 a = 100;
I64 b = 250;

U0 CalcPrintFixed4(F64 cpf_val) {
    F64 cpf_v = cpf_val;
    if (cpf_v < 0.0) {
        doldoc_print("-");
        cpf_v = -cpf_v;
    }
    I64 cpf_whole = (I64)cpf_v;
    I64 cpf_frac = (I64)((cpf_v - (F64)cpf_whole) * 10000.0 + 0.5);
    if (cpf_frac >= 10000) {
        cpf_whole = cpf_whole + 1;
        cpf_frac = cpf_frac - 10000;
    }
    doldoc_printf("%lld.%04lld", cpf_whole, cpf_frac);
}

I64 CalcHornerCubic(I64 chc_c3, I64 chc_c2, I64 chc_c1, I64 chc_c0, I64 chc_x) {
    I64 chc_acc = chc_c3;
    chc_acc = chc_acc * chc_x + chc_c2;
    chc_acc = chc_acc * chc_x + chc_c1;
    chc_acc = chc_acc * chc_x + chc_c0;
    return chc_acc;
}

I64 CalcGcd(I64 cg_a, I64 cg_b) {
    I64 cg_x = cg_a;
    I64 cg_y = cg_b;
    if (cg_x < 0) cg_x = -cg_x;
    if (cg_y < 0) cg_y = -cg_y;
    while (cg_y != 0) {
        I64 cg_rem = cg_x % cg_y;
        cg_x = cg_y;
        cg_y = cg_rem;
    }
    return cg_x;
}

I64 CalcPowInt(I64 cpi_base, I64 cpi_exp) {
    I64 cpi_res = 1;
    I64 cpi_b = cpi_base;
    I64 cpi_e = cpi_exp;
    while (cpi_e > 0) {
        if ((cpi_e & 1) != 0) {
            cpi_res = cpi_res * cpi_b;
        }
        cpi_b = cpi_b * cpi_b;
        cpi_e = cpi_e >> 1;
    }
    return cpi_res;
}

I64 CalcMain() {
    doldoc_clear();
    U64 cm_t0 = __mrs_cntvct();

    I64 cm_lin = a + b * 2;
    I64 cm_grp = (a + b) * 2;
    I64 cm_p4  = CalcHornerCubic(2, -5, 3, 7, 4);
    I64 cm_p10 = CalcHornerCubic(2, -5, 3, 7, 10);
    I64 cm_gcd = CalcGcd(1071, 462);
    I64 cm_pow = CalcPowInt(3, 12);

    // Quadratic solver: x^2 - 5x + 6 = 0 -> discriminant = 25 - 24 = 1
    F64 cm_qa = 1.0;
    F64 cm_qb = -5.0;
    F64 cm_qc = 6.0;
    F64 cm_disc = cm_qb * cm_qb - 4.0 * cm_qa * cm_qc;
    F64 cm_sqrt_disc = MathSqrt(cm_disc);
    F64 cm_r1 = (-cm_qb + cm_sqrt_disc) / (2.0 * cm_qa);
    F64 cm_r2 = (-cm_qb - cm_sqrt_disc) / (2.0 * cm_qa);

    U64 cm_t1 = __mrs_cntvct();
    U64 cm_cycles = cm_t1 - cm_t0;

    doldoc_print("\n$CARD,title=\"NeoOS Sovereign Scientific Calculator & Expression Workbench\",w=108,h=2,bg=0xFF1E1E2E,border=0xFF89B4FA$\n");
    doldoc_printf("  Engine: $FG,GREEN$ARMv8-A AArch64 Native ALU + IEEE-754 Hardware FPU$FG$  |  Eval Latency: $FG,YELLOW$%llu cycles$FG$\n", cm_cycles);
    doldoc_print("$HR$\n");

    doldoc_print("  $FG,SAPPHIRE$[1] Operator Precedence & Integer Number Theory$FG$\n");
    doldoc_printf("      a = %lld, b = %lld  |  a + b * 2 = $FG,GREEN$%lld$FG$  |  (a + b) * 2 = $FG,CYAN$%lld$FG$\n", a, b, cm_lin, cm_grp);
    doldoc_printf("      Horner P(x) = 2x^3 - 5x^2 + 3x + 7  -->  P(4) = $FG,GREEN$%lld$FG$,  P(10) = $FG,GREEN$%lld$FG$\n", cm_p4, cm_p10);
    doldoc_printf("      Euclid GCD(1071, 462) = $FG,GREEN$%lld$FG$             -->  Fast Pow 3^12 = $FG,GREEN$%lld$FG$\n", cm_gcd, cm_pow);
    doldoc_print("$HR$\n");

    doldoc_print("  $FG,SAPPHIRE$[2] Quadratic Root Solver & Hardware FSQRT$FG$\n");
    doldoc_print("      Equation: x^2 - 5x + 6 = 0  |  Discriminant = ");
    CalcPrintFixed4(cm_disc);
    doldoc_print("  |  Root r1 = $FG,GREEN$");
    CalcPrintFixed4(cm_r1);
    doldoc_print("$FG$, Root r2 = $FG,GREEN$");
    CalcPrintFixed4(cm_r2);
    doldoc_print("$FG$\n");
    doldoc_print("      Radicals: sqrt(2) = $FG,CYAN$");
    CalcPrintFixed4(MathSqrt(2.0));
    doldoc_print("$FG$,  sqrt(3) = $FG,CYAN$");
    CalcPrintFixed4(MathSqrt(3.0));
    doldoc_print("$FG$,  sqrt(5) = $FG,CYAN$");
    CalcPrintFixed4(MathSqrt(5.0));
    doldoc_print("$FG$\n");
    doldoc_print("$HR$\n");

    doldoc_print("  $FG,SAPPHIRE$[3] Trigonometric & Pythagorean Identity Table (sin^2 + cos^2 = 1)$FG$\n");
    I64 cm_deg = 0;
    while (cm_deg <= 90) {
        F64 cm_ang = (F64)cm_deg;
        F64 cm_s = MathSin(cm_ang);
        F64 cm_c = MathCos(cm_ang);
        F64 cm_id = cm_s * cm_s + cm_c * cm_c;
        doldoc_printf("      theta = $FG,YELLOW$%2lld deg$FG$  |  sin = ", cm_deg);
        CalcPrintFixed4(cm_s);
        doldoc_print("  |  cos = ");
        CalcPrintFixed4(cm_c);
        doldoc_print("  |  sin^2 + cos^2 = $FG,GREEN$");
        CalcPrintFixed4(cm_id);
        doldoc_print("$FG$\n");
        if (cm_deg == 0) {
            cm_deg = 30;
        } else if (cm_deg == 30) {
            cm_deg = 45;
        } else if (cm_deg == 45) {
            cm_deg = 60;
        } else if (cm_deg == 60) {
            cm_deg = 90;
        } else {
            cm_deg = 100;
        }
    }

    doldoc_print("$HR$\n");
    doldoc_print("  $BT,\"Re-Run Calc\",LM=\"run calc.HC\"$  $BT,\"Factorial Table\",LM=\"run fact.HC\"$  $BT,\"Inspect Source\",LM=\"src calc.HC\"$\n\n");
    return cm_lin;
}

CalcMain();
a + b * 2;
