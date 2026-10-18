# THE UNIFIED SHELL-DOLDOC SYMBIOSIS & SOVEREIGN GRAPHICS SUBSTRATE
## Pure HolyC Ring 0 SASOS Architecture Specification for ARMv8-A
**Document ID:** SHELL-DOLDOC-SYMBIOSIS-2026-BETA  
**Target:** NeoOS Kernel Core, Graphics Engine & Shell Runtime  
**Classification:** Architectural Law & Unified Execution Specification  

---

```
                       ======================================================
                          THE SOVEREIGN UNIFIED CONTINUUM ARCHITECTURE
                       ======================================================

  [ Traditional Fractured Model ]                    [ NeoOS Sovereign Continuum ]
  +--------------------------------+                 +------------------------------------+
  | WebKit / DOM / Electron App    |                 |                                    |
  +--------------------------------+                 |                                    |
  | Compositor (Mutter/KWin/DWM)   |                 |                                    |
  +--------------------------------+                 |                                    |
  | Window Server (X11 / Wayland)  |       ===>      |        SOVEREIGN DOLDOC 3.0        |
  +--------------------------------+                 |     UNIFIED GRAPHICS CONTINUUM     |
  | Shell REPL (bash/zsh)          |                 |                                    |
  +--------------------------------+                 |   (Text, Window, Compositor, REPL  |
  | Terminal Emulator (VT100 Grid) |                 |    & Shaders in a Single Ring 0    |
  +--------------------------------+                 |          OmniTape Journal)         |
  | Kernel Framebuffer / DRM Driver|                 |                                    |
  +--------------------------------+                 +------------------------------------+
       4 Independent Event Loops                               Single Pass Traversal
       4 Competing Dirty Trackers                             Morton 64x64 L1 Spatial Bins
       Megabytes of Duplicated Pixmaps                        AArch64 NEON Direct Scanout
```

---

## 1. EXECUTIVE SUMMARY: THE RE-IMAGINED VISION

In UNIX, Plan 9, and modern desktop operating systems, an unfortunate historical compromise was codified: **the decoupling of the terminal emulator, the shell, the window manager, and the graphics compositor into disjoint processes communicating over pipes, sockets, and shared memory IPC.**
* Text is stripped of semantic meaning into a stream of VT100 ANSI escape codes.
* Windows are isolated offscreen raster buffers managed by an external window manager (`WM`) and compositor (`Compositor`).
* The shell is forced to be a dumb character matrix printer ignorant of graphical structure.

Terry Davis in TempleOS proved an alternate, superior truth: **A Shell Task’s output buffer IS a living `CDoc` document stream.** Typing at the prompt directly edits the document. Running a command appends formatted, interactive nodes to the display tape.

**NeoOS** takes Terry’s breakthrough to its ultimate theoretical and physical conclusion on 64-bit ARMv8-A (AArch64) Ring 0:
1. **The Shell retains 100% of its command-line identity, ergonomic brilliance, and instant HolyC REPL power** (prompt, history navigation, tab completion, line editing, continuous expression evaluation, instant disassembly, process inspection).
2. **DolDoc is promoted from a simple text-document formatter to the SOVEREIGN COMPOSITOR, RENDERER, LAYOUT ENGINE, and GRAPHICS SUBSTRATE of the entire OS.**
3. **`WM.HC` and `Compositor.HC` are completely dissolved** into native DolDoc spatial tape directives (`$WIN$`, `$SPLIT$`, `$BLUR$`, `$ELEV$`). Windowing is simply sub-stream viewport clipping within the universal display journal (`OmniTape`).
4. **The rigid 126×41 character cell grid is eradicated.** In its place stands **Continuous Subpixel Typography with Elastic Tabstops**, preserving strict columnar alignment for code, memory dumps, and disassembly while rendering proportional vector glyphs at subpixel precision.
5. **Interactive 3D meshes, fragment shaders, sliders, math equations, and oscilloscopes run seamlessly inline within the shell document or elevated into spatial tiles**, executed directly via SIMD NEON rasterization and Morton 64×64 tile caching.

---

## 2. THE SHELL-DOLDOC SYMBIOSIS

### 2.1 The Shell Output Buffer IS a `CDoc` Tape
In NeoOS, the Shell does not print to a virtual terminal (TTY) or an ANSI ring buffer. Every Shell task owns a pointer to an active `CDoc` document instance (`Fs->put_doc` and `Fs->display_doc`):

```c
class CTask {
    U64         task_id;
    U8          task_name[32];
    U64         flags;
    CDoc       *put_doc;        // Active target for print/stream emission
    CDoc       *display_doc;    // Active presentation document rendered to display
    CShellCtx  *shell_ctx;      // Shell state: prompt, history, line buffer, cursor
    // ... Context registers, stack, message queue
};
```

When any function executes `doldoc_printf(...)`, `"Hello World\n";`, `Dir;`, or `Disasm("main");`, it writes directly into the task's display tape as typed `CDocEntry` records:
* Plain text is stored as `DOCET_TEXT`.
* Links are stored as `DOCET_LINK`.
* Interactive buttons and widgets are stored as `DOCET_BUTTON`, `DOCET_SLIDER`, `DOCET_SHADER`, etc.

```
+-----------------------------------------------------------------------------------+
|                             Shell Task (Ring 0 EL1)                               |
+-----------------------------------------------------------------------------------+
|  [Keyboard / UART] ---> [Shell Line Editor] ---> [Compiler / JIT REPL Engine]     |
|                                |                                   |              |
|                                v                                   v              |
|                     [Active Prompt Node]                 [Command Output Tape]    |
|                                \                                   /              |
|                                 v                                 v               |
|                       +-------------------------------------+                     |
|                       |  CDoc (OmniTape Display Journal)    |                     |
|                       +-------------------------------------+                     |
|                                          |                                        |
|                       +------------------v------------------+                     |
|                       |   DolDoc Sovereign Compositor Pass  |                     |
|                       +------------------+------------------+                     |
|                                          |                                        |
|                     +--------------------+--------------------+                   |
|                     |                                         |                   |
|                     v                                         v                   |
|       [Inline Shell Log Entry]                     [Spatial Elevated Viewport]    |
|       - Disassembly with syntax tags               - Floating 3D HolyGL Gears     |
|       - Live oscilloscopes                         - Tiled Shader Window          |
|       - Reactive variable sliders                  - Split-pane Filer             |
+-----------------------------------------------------------------------------------+
```

### 2.2 The Shell Ergonomics: Preserving 100% Interactive Power
The Shell feels like an ultra-responsive, supercharged terminal, but every character and widget is a live document node:

1. **The Dynamic Prompt**:
   ```holy-c
   U0 ShellPrintPrompt(CShellCtx *ctx) {
       // Emits styled, semantic color tokens directly into doc tape
       DocPrint(ctx->doc, "$FG,MAUVE$neo$FG,SAPPHIRE$:%s$FG,GREEN$> $FG,TEXT$", redsea_get_pwd());
       ctx->prompt_node = ctx->doc->tail; // Marks boundary between history and active input
   }
   ```
2. **Continuous Cursor Navigation & Line Editing**:
   * The Shell maintains an active input node: `DOCET_INPUT_LINE`.
   * Characters typed append directly to the document node's string buffer. Backspace truncates.
   * Arrow keys (`KEY_LEFT`, `KEY_RIGHT`) adjust `cursor_subpixel_offset` within the active vector run.
   * Mouse clicks anywhere in previous command outputs reposition the insertion point or inspect previous nodes!
3. **Command History (Up/Down Arrow)**:
   * Shell history is stored in a zero-allocation ring buffer.
   * Pressing `KEY_UP` replaces the text content of the active `DOCET_INPUT_LINE` with the historical command string and immediately marks the Morton 64×64 bounding tile dirty for instant sub-millisecond redraw.
4. **Direct HolyC Expression Evaluation & Instant JIT REPL**:
   * Unlike Bash/Zsh, which require subprocessing, any statement ending with `;` or bare expression is JIT-compiled directly to AArch64 machine code in executable RAM:
     * `1 + 1;` -> Compiles to `MOV X0, #2; RET`, executes in Ring 0, prints `0x0000000000000002`.
     * `U32 *p = 0x8000; *p = 42;` -> Ring 0 flat SASOS address direct poke without syscalls.
     * `Gears3DMain();` -> Direct jump to 3D pipeline execution.
5. **Disassembly & Inspection (`uf`, `mem`, `top`)**:
   * `uf("DolDocRender")` does not print raw ASCII text. It emits clickable, syntax-highlighted disassembly where register names are highlighted (`$FG,YELLOW$X0$FG$`), branch targets are hyperlinked (`$LK,"0xFFFF000000021A40",A="0xFFFF000000021A40"$`), and clicking a call target jumps the editor straight to that function's HolyC source!

---

## 3. DOLDOC AS THE SOVEREIGN COMPOSITOR, RENDERER & GRAPHICS ENGINE

### 3.1 Dissolving `WM.HC` and `Compositor.HC`
In the legacy stack, three separate entities fought over pixels:
1. `WM.HC` tracked windows (`CWindow`), coordinates, z-order, titlebars, dragging, and tiling.
2. `Compositor.HC` traversed window lists, generated blur buffers, drew drop shadows, and blitted damage rects.
3. `DolDoc.HC` rendered text and widgets inside the client area of a single window.

**In NeoOS, this separation is completely abolished.**
DolDoc *is* the desktop, the window manager, the layout engine, and the compositor:

```
+===================================================================================+
|               TRADITIONAL DESKTOP                  |          NEO-OS UNIFIED      |
+====================================================+==============================+
| User Apps -> Pipe -> Shell -> ANSI -> X11/Wayland  |                              |
| -> Window Manager -> IPC -> Compositor -> Drivers  | Shell / Apps -> CDoc Tape    |
|                                                    |      |                       |
| Result: 4 Context Switches, 3 Intermediate Copies, |      v                       |
| Severe Frame Latency, Loss of Semantics            | DolDoc Sovereign Engine      |
|                                                    |      | (SIMD Morton Tiles)   |
|                                                    |      v                       |
|                                                    | Direct Physical Framebuffer  |
+===================================================================================+
```

### 3.2 Window Management as Document Directives
When a user launches a window or splits the screen, no external window server is invoked. DolDoc handles it via stream layout:

1. **Floating Window (`$WIN$`)**:
   ```holy-c
   // Embeds an elevated sub-viewport into the active document tape
   CDocEntry *DocWindowCreate(CDoc *doc, U8 *title, F32 x, F32 y, F32 w, F32 h) {
       CDocEntry *e = DocEntryAlloc(doc, DOCET_VIEWPORT);
       strncpy(e->viewport.title, title, 63);
       e->viewport.vx = x;
       e->viewport.vy = y;
       e->viewport.vw = w;
       e->viewport.vh = h;
       e->viewport.win_flags = WIN_FLAG_FLOATING | WIN_FLAG_HAS_SHADOW | WIN_FLAG_ACRYLIC;
       e->viewport.sub_doc = DocNew("SubDoc");
       e->z_elevation = 10; // Elevates above desktop
       DocInsertEntry(doc, e);
       DocMarkDirtyRect(doc, x - 16, y - 16, w + 32, h + 32);
       return e;
   }
   ```

2. **Tile Split (`$SPLIT$`)**:
   * `DocTileSplit(doc, SPLIT_HORIZONTAL, 0.5)` splits the current viewport into two sub-viewports. Layout traversal calculates their bounds using flexbox rules during the single layout pass!

3. **Window Elevation and Shadows (`$ELEV$`)**:
   * Shadows and acrylic blurs are not separate compositing surfaces. When DolDoc's Morton rasterizer encounters an entry with `z_elevation > 0`, it expands the damage rectangle, computes a dual-pass Box/Gaussian blur over the underlying Morton tiles, and blends the window contents with NEON SIMD alpha compositing.

### 3.3 Inline Execution vs. Spatial Window Elevation
When typing commands in the Shell:
* `ls` or `dir` -> Outputs inline text and clickable links into the stream.
* `cat photo.bmp` -> Inlines a scalable raster image widget directly into the terminal log.
* `shader 4` (plasma shader):
  * **Default (Inline)**: Embeds a 256×128 live animating `$SHADER$` widget right between the prompt that ran it and the next prompt!
  * **Elevated (`shader 4 --win` or clicking the "Pop Out" icon)**: DolDoc changes the node's type from inline to `DOCET_VIEWPORT` with floating elevation. The widget lifts off the tape and floats as an independent window!
* `gears` (3D HolyGL):
  * Running `gears` embeds the live 3D spinning gear train directly into the terminal stream. You can scroll up in your shell history, and **the gears from three commands ago are still spinning smoothly at 60 FPS in your history scrollback!**

---

## 4. ERADICATING THE DUALITY AND THE LEGACY CHARACTER CELL

### 4.1 Continuous Subpixel Typography (`FontVector.HC`)
NeoOS replaces fixed cells with **Continuous Subpixel Vector Typography**:
* Glyphs are defined by quadratic/cubic Bézier curves or pre-rasterized distance field curves (SDF) rendered with subpixel horizontal positioning (1/4 pixel resolution).
* Text coordinates are continuous IEEE-754 floats (`F32 x, y`).
* Kerning and ligature tracking are evaluated during layout traversal.

### 4.2 Elastic Tabstops: Proportional Fonts with Columnar Perfection
Developers love fixed-width monospace fonts solely because code columns, struct definitions, tables, and disassembly instructions line up neatly:
```
U32    flags;        // Bitfield
U64    timestamp;    // Timer ticks
U8    *buffer;       // Cache line
```
If rendered with standard proportional fonts, columns turn into an unreadable jagged mess.

NeoOS resolves this universally through **Elastic Tabstops**:
* A tab stop (`\t`) in DolDoc is not a fixed number of pixels (e.g. 32px or 4 chars).
* Instead, a tab stop is an **elastic column boundary** calculated across contiguous blocks of lines:
  1. During layout traversal, DolDoc groups contiguous lines containing tab tokens into a *Tab Block*.
  2. For column $N$, DolDoc finds the maximum rendered text width:
     $$W_{\text{col}, N} = \max_{\text{line} \in \text{block}} (\text{Width}(\text{Text}_{\text{line}, N})) + \text{Padding}$$
  3. Every line in the block snaps its $N+1$-th column to $W_{\text{col}, N}$.
  4. If a line without tabs or an empty line occurs, the block closes.

```
+-----------------------------------------------------------------------------------+
|                     Continuous Elastic Tabstops Layout                            |
+-----------------------------------------------------------------------------------+
|  [Proportional Text]           | [Col 2 Elastic Boundary]   | [Col 3 Elastic]     |
|  U32                           | flags;                     | // Bitfield         |
|  unsigned long long int        | timestamp;                 | // Timer ticks      |
|  U8*                           | buffer;                    | // Cache line       |
+-----------------------------------------------------------------------------------+
|<------------ W_col0 ---------->|<--------- W_col1 --------->|
```

This guarantees:
* Code, disassembly (`uf`), memory listings (`mem`), and process tables (`top`) remain **strictly aligned to pixel-perfect vertical columns**.
* Variable names, comments, and identifiers are rendered in beautiful, proportional typography.

### 4.3 Continuous Subpixel Shell Cursor
In legacy terminals, the cursor is an inverted 8×16 character box. In NeoOS's continuous substrate:
* The cursor is an arbitrary-height vector caret positioned at continuous subpixel $(X_c, Y_c)$.
* It features an animated soft glow (Morphic Halo) driven by `CNTVCT_EL0` hardware ticks:
  $$\text{Alpha}(t) = 0.5 + 0.5 \cdot \sin(2\pi \cdot f \cdot t)$$
* **Selection Highlight**: DolDoc calculates the exact polygon bounding box of selected glyphs, rendering an acrylic accent highlight behind proportional characters without clipping descenders.
* **Mouse Click Repositioning**: Clicking mouse coordinate $(M_x, M_y)$ performs a 1D binary search on the `char_advances` array of the clicked node, snapping the insertion caret directly between the two nearest glyphs in $O(\log N)$ time.

---

## 5. HARDWARE-SYMPATHETIC RENDERER & SIMD COMPOSITING PIPELINE

### 5.1 L1-Cache Resident Morton 64×64 Spatial Partitioning
NeoOS renders without a heavy frame buffer hierarchy. The screen (e.g. 1920×1080) is partitioned into $30 \times 17 = 510$ discrete **Morton 64×64 Pixel Tiles**:

$$\text{Tile Size} = 64 \times 64 \times 4\,\text{bytes} = 16\,\text{KB}$$

On ARMv8-A Cortex-A72/A76/Neoverse cores, the L1 Data Cache is 32 KB to 64 KB.
* A $16\,\text{KB}$ Morton tile fits **completely inside the L1 Data Cache**.
* DolDoc never writes individual pixels directly across the memory bus to DRAM.
* Instead, each dirty 64×64 tile is cleared, composed, and textured entirely inside L1 cache registers, and then flushed to the physical scanout framebuffer using **AArch64 Non-Temporal Streaming Vector Stores (`stnp`)**, bypassing L2 and L3 caches to eliminate cache pollution!

```
+-----------------------------------------------------------------------------------+
|                          Morton 64x64 Tile L1 Architecture                        |
+-----------------------------------------------------------------------------------+
|                                                                                   |
|    Screen: 1920 x 1080 = 510 Tiles (Morton Swizzled Z-Order)                     |
|                                                                                   |
|    +-------------------+                                                          |
|    | Tile (tx, ty)     |  ---> Fits entirely in 16 KB L1 Data Cache               |
|    | 64x64 RGBA32      |                                                          |
|    +-------------------+                                                          |
|              |                                                                    |
|              |  Render Passes Inside L1:                                          |
|              |  1. Clear / Acrylic Blur Sample                                    |
|              |  2. Drop-Shadow Signed Distance Field (SDF)                        |
|              |  3. Vector Typography (NEON ld4/st4 subpixel blend)                |
|              |  4. Live Widget Render (Shader, 3D Mesh, Oscilloscope)             |
|              |                                                                    |
|              v                                                                    |
|    [AArch64 NEON stnp] ---> Zero-Copy Streaming DMA ---> [VirtIO-GPU Scanout]     |
|                                                                                   |
+-----------------------------------------------------------------------------------+
```

---

## 6. SYSTEM-WIDE INTEGRATION BLUEPRINT: THE UNIFIED LIFECYCLE

### 6.1 The Unified Master Loop (60 FPS VSync Paced)
The entire operating system runs inside a single, hyper-optimized, VSync-paced master loop in `KernelInit.HC` / `DolDoc.HC`:

```holy-c
U0 DolDocMasterLoop() {
    I64 last_ticks = GetCntvct();
    I64 ticks_per_frame = CntvctFreq() / 60; // 60 FPS pacing via ARM Generic Timer

    while (1) {
        I64 current_ticks = GetCntvct();
        
        // 1. Process Hardware Input Events
        VirtioInputPoll();
        UARTPoll();
        
        // 2. Dispatch Input to Focused Shell Document Node
        CDoc *active_doc = Fs->display_doc;
        CInputMsg msg;
        while (TaskGetMsg(Fs, &msg)) {
            DolDocDispatchEvent(active_doc, &msg);
        }
        
        // 3. Tick Reactive Widgets (Animate Shaders, 3D Meshes, Oscilloscopes)
        g_doc_anim_tick++;
        DolDocUpdateTelemetryRingBuffers();
        
        // 4. Layout Pass: Recompute Subpixel Bounds & Elastic Tabstops (Only if Dirty)
        if (active_doc->flags & DOCF_DIRTY_LAYOUT) {
            DolDocComputeLayout(active_doc);
            active_doc->flags &= ~DOCF_DIRTY_LAYOUT;
        }
        
        // 5. Compositing & Render Pass: L1 Morton 64x64 Tile Traversal
        if (active_doc->flags & DOCF_DIRTY_RENDER) {
            // Traverse all dirty Morton tiles
            for (I64 tile_idx = 0; tile_idx < active_doc->dirty_tile_count; tile_idx++) {
                I64 tile_id = active_doc->dirty_tiles[tile_idx];
                
                // Render directly inside 16 KB L1 Data Cache
                DolDocRasterizeTileL1(active_doc, tile_id);
                
                // Flush to scanout using non-temporal streaming stores (stnp)
                DolDocFlushTileToScanout(tile_id);
            }
            active_doc->dirty_tile_count = 0;
            active_doc->flags &= ~DOCF_DIRTY_RENDER;
            
            // Notify VirtIO-GPU of hardware flush
            VirtioGpuFlush();
        }
        
        // 6. Hardware VSync Pacing & Power Efficiency
        I64 elapsed = GetCntvct() - last_ticks;
        if (elapsed < ticks_per_frame) {
            // Event-driven low-power wait until next timer tick or input interrupt
            __asm__("wfe");
        }
        last_ticks = GetCntvct();
    }
}
```

---

## 7. SUMMARY & ARCHITECTURAL VERDICT

By making **DolDoc the Sovereign Compositor and Graphics Engine** while maintaining the **Shell as the primary living document task**, NeoOS achieves what no operating system has ever dared:
1. **Total Conceptual Unity**: There is no distinction between a terminal, an editor, a file manager, a window manager, or a GUI application. Everything is an OmniTape stream.
2. **Unrivaled Ergonomics**: The developer has the familiar terminal shell with autocomplete, history, and REPL, but gained the ability to manipulate 3D models, inspect live memory graphs, adjust variables with sliders, and pop out floating windows with zero ceremony.
3. **Extreme Bare-Metal Efficiency**: Eliminating context switches, page-table traversals, IPC serialization, and intermediate compositor surfaces allows NeoOS to deliver 60 FPS graphics, 4K vector typography, and sub-millisecond REPL response on low-power ARMv8-A hardware.

*This specification stands as the definitive blueprint for the unified Shell-DolDoc engine.*
