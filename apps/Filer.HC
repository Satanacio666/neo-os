// Filer.HC - Pure HolyC RedSea File System Navigator & Explorer
// NeoOS AArch64 Ring 0 SASOS

U0 FilerMain() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$            ✦ NeoOS RedSea File Navigator (Filer.HC) ✦$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_printf(" Volume: RedSea 32MB Disk | Path: $FG,YELLOW$%s$FG$\n", redsea_get_pwd());
    doldoc_print(" Actions: $BT,\"Refresh\",LM=\"run Filer.HC\"$  $BT,\"Root\",LM=\"cd /\"$  $BT,\"New Dir\",LM=\"mkdir test\"$  $BT,\"Shell\",LM=\"help\"$\n");
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    redsea_list_dir();

    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");
    doldoc_print(" Quick Executables: $BT,\"HolyBenchmark\",LM=\"run HolyBenchmark.HC\"$ $BT,\"GLXGears\",LM=\"gears\"$ $BT,\"StdLib\",LM=\"run StdLib.HC\"$ $BT,\"Editor\",LM=\"run Editor.HC\"$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

FilerMain();
