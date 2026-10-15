// ==============================================================================
// Filer.HC - Sovereign Pure HolyC RedSea File Navigator & Disk Explorer
// Architecture: ARMv8-A Ring 0 | 100% Native AArch64 JIT Execution
// Substrate: Interactive Directory Tree, File Badges & DolDoc Quick Actions
// ==============================================================================

U0 FilerMain() {
    I64 max_entries = 64;
    I64 count = 0;
    I64 file_idx = 0;
    I64 sz = 0;
    I64 attr = 0;
    I64 flen = 0;
    I64 is_holyc = 0;
    U8 *entries = 0;
    U8 *entry = 0;
    U8 *fname = 0;
    I64 *psz = 0;

    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$       ✦ NeoOS Sovereign RedSea File Navigator (Filer.HC) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_printf(" Volume : RedSea 32MB Disk | Active Directory: $FG,YELLOW$%s$FG$\n", redsea_get_pwd());
    doldoc_print(" Actions: $BT,\"Root /\",LM=\"cd /\"$  $BT,\"Refresh\",LM=\"run Filer.HC\"$  $BT,\"New Folder\",LM=\"mkdir newdir\"$  $BT,\"Disk Mem\",LM=\"mem\"$\n");
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    entries = kmalloc(max_entries * 64);
    if (!entries) {
        doldoc_print("$FG,RED$Memory allocation failure in Filer!$FG$\n");
        return;
    }
    memset(entries, 0, max_entries * 64);

    count = redsea_get_entries(entries, max_entries);
    doldoc_printf(" Found $FG,YELLOW$%lld$FG$ entries in current directory:\n\n", count);

    for (file_idx = 0; file_idx < count; file_idx++) {
        entry = entries + file_idx * 64;
        attr = entry[0] | (entry[1] << 8);
        fname = entry + 2;
        psz = entry + 48;
        sz = *psz;

        if (attr & 0x10) {
            // Directory
            doldoc_printf("  $FG,BLUE$[DIR]$FG$     $LK,\"%-18s\",A=\"cd %s\"$  $BT,\"Open\",LM=\"cd %s\"$\n",
                          fname, fname, fname);
        } else {
            // Check extension
            flen = strlen(fname);
            is_holyc = (flen > 3 && fname[flen-3] == '.' && fname[flen-2] == 'H' && fname[flen-1] == 'C');
            if (is_holyc) {
                doldoc_printf("  $FG,GREEN$[HOLYC]$FG$   %-18s %6lld B  $BT,\"Run\",LM=\"run %s\"$  $BT,\"Edit\",LM=\"edit %s\"$  $BT,\"Del\",LM=\"rm %s\"$\n",
                              fname, sz, fname, fname, fname);
            } else {
                doldoc_printf("  $FG,YELLOW$[DOC]$FG$     %-18s %6lld B  $BT,\"Cat\",LM=\"cat %s\"$  $BT,\"Edit\",LM=\"edit %s\"$  $BT,\"Del\",LM=\"rm %s\"$\n",
                              fname, sz, fname, fname, fname);
            }
        }
    }

    kfree(entries);
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");
    doldoc_print(" Quick Launch: $BT,\"HolyBenchmark\",LM=\"bench\"$  $BT,\"GLXGears 3D\",LM=\"gears\"$  $BT,\"Compositor\",LM=\"compositor\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

FilerMain();
0;
