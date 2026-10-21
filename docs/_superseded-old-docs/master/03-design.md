# 03 — Design (brainstorm → architecture)

## 3.1 First principles
NeoOS has four competing worldviews: DolDoc (documents), WM (windows), Compositor (themes/damage), Render/HolyGL (two rasterizers). **Collapse them into one:** *a document is a scene is a window is an app is the shell.* One tree, one display list, one renderer, one action protocol.

Terry's real genius: text, links, widgets, sprites, and UI chrome all live in the same document with per-char attributes and executable macros — **the document is the program**. Push that to the limit.

## 3.2 What DolDoc really is (canonical TempleOS model)
From `DolDocOverview`: a **linked tree of `CDocEntry`** (not a flat grid); two-letter commands with `+/-` flags and comma args (`TX CR SR CU TB CL PB PL LM RM HD FO ID FD BD FG BG PT WW UL IV BK SX SY CM AN LK BT DA MA SP FI`); **per-character binary attribute words**; **`$MA` macros**; **`$SP` binary sprites**; **`$DA` data / `DocForm()`**.
NeoOS implements a bespoke subset and is missing: binary attribute words, `$MA`, `$AN`, `$MU`, `$FI`, real `$SP` bitmaps, `$DA` forms, `$ID` trees, word-wrap, document persistence.
**The idea to steal and extend:** a document is a compiled display list + an action table, and **every node can carry an executable action**.

## 3.3 The grand unification thesis
> **Everything is a CDoc. Every CDoc compiles to one OmniTape. Every OmniTape renders through HolyGL. Every interactive node returns an Action.**
- A **window is a document** (view); the WM becomes a *layout policy*.
- The **shell is a document** whose last line is an editable Input node.
- An **app is a document** (or a prototype you clone).
- The **compositor is a damage tracker over documents**; glass/shadow become node styles.
- **HolyGL is the only renderer**; DolDoc never calls `gfx_*`.

## 3.4 DolDoc node & tag model (target)
Node kinds: `TextRun`, `Link` (typed), `Button`, `Input`/`Data`, `Slider`/`Toggle`/`Progress`, `Tree`, `Bitmap` (`$SP`), `Scene3D`, `Shader`, `Graph`, `Macro` (`$MA`), `Include` (`$FI`), `Split`, `Window`.
Upgrades over today: (1) per-char attribute word; (2) a real document tree; (3) a **reactive cell** (generalize `DolDocPatchTarget`: any node value bound to memory; on change, only its node re-lays-out); (4) a **macro table** (`$MA` → JIT'd HolyC).

## 3.5 HolyGL — from rasterizer to API with backends
Today HolyGL is a **software rasterizer** (flat shading, no Z-interp (`z_avg`), no texture sampling, no NEON). Redefine it as an **API**:
```
HolyGL (API) ── submit(tiles) ──► backend: soft (NEON×SMP) | virtio-gpu (virgl) | native GPU | remote (cluster)
```
Acceleration is not "tiers you choose" — it's **execution units of one model**.

## 3.6 The Unified Tile Pipeline (the spine)
> **The frame is a set of tile jobs. A *provider* executes tile jobs. SIMD, cores, and GPU are just providers — all at once.**
```
Document/Scene → draw list (OmniTape) → tile binning (Morton 64×64)
   → [ Tile Job Queue ] → work-stealing scheduler
        ├─ Core 0..N: SIMD tile kernel (NEON, 4 px/op)
        └─ GPU provider: same jobs → workgroups
   → tile compositor → present
```
- **The tile job** is the universal unit: `{tile_id, clipped primitive list, target surface}`.
- **SIMD** = the *shape* of the kernel (not a separate path). **SMP** = core count. **GPU** = a provider.
- **No fallback:** AArch64 **mandates NEON**, so the kernel is SIMD-native with no scalar path; one core = a scheduler with one worker; GPU is optional, not required.
- Write the kernel **once**; it is simultaneously the SIMD lane, the core unit, and the GPU workgroup.
- Provider seam: `Provider { bool available(); void submit(TileJob[], n); void wait(); }` — a `remote` provider later = the MCU cluster.
- Perfect = one canvas/device/damage/present; bin-then-raster; real Z-buffer + textures + SDF + fragment shaders; deterministic per tile (same result on 1 core vs N).

## 3.7 DolDoc ↔ Shell (interaction unification)
Documents never execute; they **emit Actions**. `DolDocHitTest → Action{Run, Open, Set, Clone, Focus}`. The **Shell is the action executor + REPL** and owns command dispatch (use the existing-but-dead `shell_register_cmd` registry). Shell output **is** a CDoc. Oberon/Emacs ideas: any text can be a command; documents have "modes"; a live notebook REPL.

## 3.8 DolDoc ↔ WM / Compositor (dissolution)
Windows are documents (`$WIN`/`$SPLIT`); the WM is a layout policy (geometry/z-order/focus/input). DolDoc *drives* window creation; the WM owns the allocator. Compositor dissolves into Render (damage = document dirty; themes = style tokens). Menus/taskbars/drawers become DolDoc documents.

## 3.9 Self-hosting (the "perfect and self" end state)
- The **compiler is a document** (source buffer + Run + output/errors).
- **Boot is a document** (log + progress + REPL that becomes the shell).
- The **DolDoc reference is a DolDoc** (dogfood).
- Path: add F64 + inline asm + `&function` to `Compiler.HC`; compile a real module end-to-end; flip boot; retire `jit_arm64.c`/`lexer.c`/`table.c`; only `boot/main.c` + `boot/uefi` remain in C.

## 3.10 "Run anything at max native performance" — the porting ladder
| Tier | How | Perf | Unlocks |
|---|---|---|---|
| 0 Native | HolyC/AArch64 | native | your code |
| 1 Recompiled source | C/C++/Rust/Zig → AArch64/HolyC | ~native | decompiled games |
| 2 WASM JIT | real WASM→AArch64 JIT | good | portable ecosystem |
| 3 Emulation | x86/ARM/RISC-V translator | 0.2–0.8× | any binary |
Requires: **`HolyPort`** (SDL/raylib-like platform layer: window, input, audio, files, threads, timers) + a toolchain (C→HolyC / LLVM→HolyC). **Shortcut:** port SDL/raylib to HolyPort → thousands of games come along. Note: `Jamesbarford/holyc-lang` adds `F32` specifically for SDL/raylib ports — proof the idea is real.

## 3.11 The MCU cluster (future)
ESP32 is Xtensa/RISC-V (not AArch64) and tiny. Needs a RISC-V backend + a node runtime. **It fits the architecture**: the tiled renderer maps onto nodes (each MCU renders its tiles), the OmniTape display list is serializable (documents replicate), and work-stealing → cluster work-stealing. The **`Surface` abstraction** unifies screen/window/texture/remote; a `remote` provider ships tiles to nodes. So the same document/tile abstractions scale 1 core → SMP → GPU → cluster.

## 3.12 Steal shamelessly
Emacs (buffers/modes/eval/self-doc), Oberon (text-as-command), HyperCard (cards/buttons/scripts), Smalltalk Morphic (halos/direct manipulation — make `[D] Clone`/`[R] Refresh` real), Self (prototype windows), Plan 9 (everything is a file → documents are RedSea files), Web (DOM+CSS+events), Shadertoy/SDF (fragment shaders, resolution-independent text), Zig (incremental recompile → incremental re-layout).

## 3.13 Moonshot features
Reactive documents; executable documents (`$MA`); time-travel (OmniTape is a command log → replay/undo); self-modifying UI; one unified focus tree; document ↔ 3D parity; distributed documents (`$FI` across nodes); one action bus (observable/replayable).
