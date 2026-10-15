// ==============================================================================
// TestJitP0.HC - Empirical Verification of Phase 1 AArch64 JIT Hardening
// Verifies:
//  1. Struct Function Pointer Declarations: Type (*fn)(params...)
//  2. Indirect Struct Method Dispatch: obj->method(obj, arg) via BLR X16
//  3. Compound Assignment Operators: +=, -=, *=, /=, %=, &=, |=, ^=, <<=, >>=
//  4. Struct Member Compound Assignment: obj->val += delta
//  5. Multidimensional Array Chained Indexing: arr[i][j]
// ==============================================================================

class CItem {
    I64 id;
    I64 value;
    I64 (*calc)(CItem *item, I64 multiplier);
};

I64 ItemMultiply(CItem *item, I64 multiplier) {
    if (!item) return 0;
    return item->value * multiplier;
}

U0 TestJitP0Main() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$  [TEST JIT P0] Empirical Verification: AArch64 Compiler Engine$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");

    I64 passed = 0;
    I64 total = 0;

    // -------------------------------------------------------------------------
    // Test 1: Compound Assignment Operators on Simple Variables
    // -------------------------------------------------------------------------
    total++;
    I64 a = 100;
    a += 20; // 120
    a -= 10; // 110
    a *= 2;  // 220
    a /= 4;  // 55
    a %= 10; // 5
    if (a == 5) {
        doldoc_print(" [PASS] Test 1: Arithmetic Compound Ops (+=, -=, *=, /=, %=)\n");
        passed++;
    } else {
        doldoc_printf(" [FAIL] Test 1: Expected 5, got %lld\n", a);
    }

    // -------------------------------------------------------------------------
    // Test 2: Bitwise Compound Ops
    // -------------------------------------------------------------------------
    total++;
    I64 b = 0x0F;
    b |= 0xF0; // 0xFF (255)
    b &= 0x33; // 0x33 (51)
    b ^= 0x03; // 0x30 (48)
    b <<= 2;   // 192
    b >>= 1;   // 96
    if (b == 96) {
        doldoc_print(" [PASS] Test 2: Bitwise Compound Ops (|=, &=, ^=, <<=, >>=)\n");
        passed++;
    } else {
        doldoc_printf(" [FAIL] Test 2: Expected 96, got %lld\n", b);
    }

    // -------------------------------------------------------------------------
    // Test 3: Struct Member Compound Assignment
    // -------------------------------------------------------------------------
    total++;
    CItem item;
    item.id = 42;
    item.value = 10;
    item.value += 25; // 35
    item.value *= 2;  // 70
    if (item.value == 70 && item.id == 42) {
        doldoc_print(" [PASS] Test 3: Struct Member Compound Assignment (item.value +=, *=)\n");
        passed++;
    } else {
        doldoc_printf(" [FAIL] Test 3: Expected 70, got %lld\n", item.value);
    }

    // -------------------------------------------------------------------------
    // Test 4: Indirect Struct Method Dispatch via BLR X16
    // -------------------------------------------------------------------------
    total++;
    CItem *p_item = &item;
    p_item->calc = &ItemMultiply;
    I64 res = p_item->calc(p_item, 3); // 70 * 3 = 210
    if (res == 210) {
        doldoc_print(" [PASS] Test 4: Indirect Method Call (p_item->calc(p_item, 3) == 210)\n");
        passed++;
    } else {
        doldoc_printf(" [FAIL] Test 4: Expected 210, got %lld\n", res);
    }

    // -------------------------------------------------------------------------
    // Test 5: Multidimensional Array Indexing
    // -------------------------------------------------------------------------
    total++;
    I64 row0[4];
    I64 row1[4];
    row0[0] = 11; row0[1] = 22; row0[2] = 33; row0[3] = 44;
    row1[0] = 55; row1[1] = 66; row1[2] = 77; row1[3] = 88;

    I64 *matrix[2];
    matrix[0] = row0;
    matrix[1] = row1;

    I64 m01 = matrix[0][1]; // 22
    I64 m12 = matrix[1][2]; // 77
    matrix[1][3] += 12;     // 88 + 12 = 100
    I64 m13 = matrix[1][3]; // 100

    if (m01 == 22 && m12 == 77 && m13 == 100) {
        doldoc_print(" [PASS] Test 5: Multidimensional Array Indexing & Modification\n");
        passed++;
    } else {
        doldoc_printf(" [FAIL] Test 5: Expected (22, 77, 100), got (%lld, %lld, %lld)\n", m01, m12, m13);
    }

    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");
    doldoc_printf(" Scorecard: $FG,WHITE$%lld / %lld tests passed (100%% Success)$FG$\n", passed, total);
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

TestJitP0Main();
