// Editor.HC - Pure HolyC Source Code Inspector & Editor
// NeoOS AArch64 Ring 0 SASOS

U0 EditorMain() {
    U8 *target = "fact.HC";
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_printf("$FG,WHITE$          ✦ NeoOS HolyC Code Inspector & Editor: %s ✦$FG$\n", target);
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" Actions: $BT,\"Execute [F5]\",LM=\"run fact.HC\"$  $BT,\"Inspect Bench\",LM=\"run Bench.HC\"$  $BT,\"Filer\",LM=\"run Filer.HC\"$\n");
    doldoc_print("$FG,CYAN$--------------------------------------------------------------$FG$\n");

    I64 buf_sz = 4096;
    U8 *buf = kmalloc(buf_sz);
    if (!buf) return;
    memset(buf, 0, buf_sz);

    I64 read_bytes = 0;
    if (redsea_read_file(target, buf, buf_sz - 1, &read_bytes) == 0) {
        buf[read_bytes] = 0;
        doldoc_printf(" File Size: %lld bytes | Format: Plaintext HolyC (.HC)\n\n", read_bytes);
        doldoc_print("$FG,WHITE$");
        doldoc_print(buf);
        doldoc_print("$FG$\n");
    } else {
        doldoc_printf(" $FG,RED$Error reading '%s' from RedSea filesystem.$FG$\n", target);
    }

    kfree(buf);
    doldoc_print("$FG,CYAN$==============================================================$FG$\n\n");
}

EditorMain();
