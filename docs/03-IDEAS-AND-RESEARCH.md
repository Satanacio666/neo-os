# NeoOS — 03 IDEAS & RESEARCH (vision, deferred features, research manifestos)

> Consolidation doc 4 of 5. Every **idea, vision, design, and research direction** found in the 44 old docs,
> preserved so nothing is lost. These are mostly **not near-term** (see `00-MASTER-PLAN §8`). Reality tags
> (`[REAL]/[PARTIAL]/[STUB]/[MISSING]/[GONE]/[SUPERSEDED]`) are from `01-REALITY-AUDIT.md`.
> Contradictions/decisions are in `04-CONTRADICTIONS-DECISIONS-OPEN-QUESTIONS.md`.

---

## 1. The founding vision (the "why")

**NeoOS** = a 64-bit AArch64 **Ring-0 (EL1) Single Address Space OS (SASOS)** in the TempleOS tradition:
"the Compiler IS the OS"; no userspace; one flat identity-mapped address space; direct MMIO/VRAM access from
any module. Terry Davis's tenets, restated across the docs: SASOS identity mapping; Ring-0 everywhere;
the compiler is the OS (no AOT binaries, source compiled on the fly); DolDoc as universal medium (text is an
active document tree with macros, live memory watches, inline 3D); radical transparency (one person can read
every line). `(from neo_os_grand_architecture_manifesto §1, neo_os_grand_consolidation_encyclopedia §1)`

**Design north star (03-design §3.3):** *"Everything is a CDoc. Every CDoc compiles to one OmniTape. Every
OmniTape renders through HolyGL. Every interactive node returns an Action."* — a window is a document (view);
the shell is a document whose last line is an editable Input node; an app is a document; the compositor is a
damage tracker over documents; HolyGL is the only renderer; DolDoc never calls `gfx_*`.

**Steal shamelessly** `(from 03-design §3.12, ultimate_dom §1)`: Emacs (buffers/modes/eval/self-doc);
Oberon (text-as-command, zero-separation); HyperCard (cards/buttons/scripts); Smalltalk Morphic (halos, direct
manipulation); Self (prototype windows); Plan 9 (everything is a file; Acme plumber); Web (DOM+CSS+events);
Shadertoy/SDF (fragment shaders, resolution-independent text); Zig (incremental recompile → incremental
layout); Makepad/Rive/Slint/Flutter-Impeller (data-oriented UI, analytical SDF, static signal graphs).

---

## 2. DolDoc — the document/scene model (target)

**Canonical TempleOS model** `(from 03-design §3.2, doldoc_sovereign…, doldoc3_graphics…, ultimate_dom §1.5)`:
a **linked tree of `CDocEntry`** (not a flat grid); two-letter commands with `+/-` flags and comma args; **per-character
binary attribute words**; `$MA` macros; `$SP` binary sprites; `$DA` data/`DocForm()`; `$ID` trees; typed `$LK`
links; anchors; word-wrap; document persistence.

**Full two-letter tag set (target):** `TX CR SR CU TB CL PB PL LM RM HD FO ID FD/BD/FG/BG PT WW UL IV BK SX SY CM
AN LK BT DA MA SP FI`. `(from 00-MASTER-CONSOLIDATED-PLAN §6 P5, 02-PRIORITY-PLAN P5, 03-design §3.2)`

**Node kinds (target):** `TextRun`, `Link` (typed), `Button`, `Input`/`Data`, `Slider`/`Toggle`/`Progress`,
`Tree`, `Bitmap` (`$SP`), `Scene3D`, `Shader`, `Graph`, `Macro` (`$MA`), `Include` (`$FI`), `Split`, `Window`.
`(from 03-design §3.4)`

**Reactive cells:** generalize `DolDocPatchTarget` — any node value bound to memory; on change, only its node
re-lays-out. `(from 03-design §3.4, doldoc_sovereign §4.4, ultimate_dom §3 Pillar 2)`

**Moonshot features** `(from 03-design §3.13)`: reactive documents; executable documents (`$MA`); time-travel
(OmniTape is a command log → replay/undo); self-modifying UI; one unified focus tree; document ↔ 3D parity;
distributed documents (`$FI` across nodes); one action bus (observable/replayable).

### 2.1 OmniTape & the Living Cell Matrix (the post-DOM spec)
`(from ultimate_dom_substitute_paradigm_spec, doldoc_sovereign_unified_continuum_master_specification)` **[MISSING]** — design spec only.
- **Pillar 1 — Linear Command Tape:** contiguous 64-byte-aligned bump arena; relative 32-bit offsets; relocatable
  via `memcpy`; `OMNITAPE_MAGIC 0x544150454E454F31` ('NEOTAPE1').
- **Pillar 2 — Living Computational Cell:** `#cell[slider…]` / `#cell[color_swatch…]` / `#cell[gizmo3d…]` /
  `#cell[oscilloscope…]`; direct in-memory mutation of the bound variable; source-text sync; Morphic halos
  (Alt-click → bytecode inspector, address pin, signal graph, in-place source editor); Oberon/Acme 3-button
  semantics (L=interact, M=execute, R=plumb).
- **Pillar 3 — Spatial Morton 64×64 tiles:** 16 KB color + 8 KB Z = 24 KB tile (fits Cortex-A72 32 KB L1);
  `Morton2D` bit-interleave; O(1) amortized hit-testing; dirty-tile streaming via `stnp`.
- **Pillar 4 — Dynamic Reactive Signal Matrix:** flat `SignalSlot`/`SignalDependencyEdge` arrays; `signal_write`
  → `O(dependents)` propagation; zero tree diffing; SIMD batch evaluation.
- **Concrete structs:** `CTapeCmdHeader` (64 B), `CPayloadTextRun/Window/Repl/LivingCell/ShaderQuad`, `CTurtle`,
  `CMortonSpatialIndex`, `TapeOpcode` enum (`CMD_TEXT_RUN`, `CMD_SDF_CARD`, `CMD_WINDOW_CONTAINER`, `CMD_REPL_PROMPT`,
  `CMD_CELL_SLIDER`, `CMD_PLUMB_DISPATCH`, …). (Two conflicting `CMD_*` tables exist across the two docs — see doc 04.)
- **Quantified claims:** <0.4 ms input-to-photon; 0.000% idle CPU; 99.87% memory-bus reduction vs IMGUI.
  These are **spec targets, not measured**.

### 2.2 DolDoc 3.0 graphics/typography/widget/sprite spec
`(from doldoc3_graphics_typography_sprite_spec)` **[MISSING]** — design spec only.
- **Catppuccin Mocha tokens** (`CAT_BASE`…`CAT_ROSEWATER`), 6 themes (Mocha, Latte, Tokyo Night, Nord,
  TempleOS CGA, Cyberpunk OLED). `(also SKILL.md Order 13)`
- **Analytical SDF** rounded rectangles/cards with border + inner glow (closed-form `d(p)`); subpixel coverage.
- **Frosted glass** (`$GLASS$`) dual-pass separable blur; NEON `ld4`/`st4` 16-pixel alpha blend.
- **Scalable Bézier typography** (quadratic + cubic, adaptive subdivision/De Casteljau); subpixel monospace
  hinting; **elastic tabstops** (proportional fonts with columnar alignment).
- **Widgets:** `$BT$` vector buttons (rest/hover/pressed elevation), `$SL$` reactive sliders (gradient fill,
  live tooltip), `$CB$` toggles/checkboxes, `$PB$` progress.
- **`$EQ$` mathematical typography:** recursive AST (`EQ_NODE_FRAC/RADICAL/SCRIPT/MATRIX`); fractions,
  dynamic-height radicals, super/subscripts, ∑/∫. `(also SKILL.md Order 15)`
- **`$GRAPH$` telemetry:** rolling oscilloscope with Catmull-Rom splines + gradient fill; analytical `y=f(x)`.
- **`$SP$` / `SPT_MESH` CSprite bytecode:** TempleOS-parity opcodes (`SPT_END/COLOR/THICK/TRANSFORM/LINE/
  POLYGON/BSPLINE3/BITMAP/MESH/SHIFTABLE_MESH`); `CSpriteMeshHeader` + `CD3I32` + `CMeshTri`; in-code 3D mesh
  rendered inline with local Z-buffer, Lambertian lighting, trackball orbit, Ctrl-R vertex editor.
- **Shader engine:** `$SHADER$` node (`DOC_NODE_SHADER`) with `CShaderUniforms` (iTime/iFrame/iResolution/
  iMouse/bound_cell); built-in library `FastSinRad`/`FastCosRad`/`ShaderFract`/`ShaderMix`/`ShaderSmoothstep`/
  `SdfSphere`/`SdfBox2D`/`SdfTorus`; 3 built-in shaders (Cyber Plasma, Raymarched SDF Morphing Torus, Acrylic
  Glass Wave); upgrade `ShaderEditor.HC` to a live split-pane IDE. `(SKILL.md Order 17)`

### 2.3 Shell ⇄ DolDoc symbiosis & sovereign compositor
`(from shell_doldoc_symbiosis_and_sovereign_compositor_blueprint)` **[MISSING]** — design spec only.
- Shell task owns `put_doc`/`display_doc` (`CDoc`); `doldoc_printf` appends typed `CDocEntry` records.
- Shell keeps full ergonomics: dynamic prompt, cursor navigation, history ring, tab autocomplete, instant HolyC
  JIT evaluation, `uf`/`src`/`mem`/`top` inspection with clickable disassembly.
- **Dissolve `WM.HC` + `Compositor.HC`:** `$WIN$`/`$SPLIT$`/`$BLUR$`/`$ELEV$`; inline vs elevated viewports
  (`shader 4 --win`); "gears from three commands ago still spinning in history scrollback".
- Continuous subpixel cursor with glow; elastic tabstops; selection highlight.

### 2.4 Post-DOM OS architecture blueprint (storage + SIC + SMP)
`(from POST_DOM_OS_ARCHITECTURE_BLUEPRINT)` **[MISSING]** — design spec only.
- **Zero-copy persistence:** documents are contiguous KHeap slabs streamed straight to RedSea clusters via
  VirtIO-Blk DMA (`DocPersistDirect`); no serialization.
- **Symbol Indirect Cell (SIC) live-patching:** UI controls ↔ JIT literal pools; `JitPatchImmediate` with
  `DC CVAU`/`DSB ISH`/`IC IVAU`/`ISB`; `MOVZ` immediate patch. (SIC cells exist late-binding **[PARTIAL]**; the
  full literal-pool patch engine is a spec.)
- **Asymmetric core specialization:** Core 0 coordinator; Cores 1–3 SIMD tile workers; lockless SPSC rings
  padded to 64 B; tickless `WFE`/`SEV`.
- 64 KB contiguous slabs; 64-byte cache-line aligned; `PhysAddr(x)=x`.

---

## 3. Rendering & graphics ideas

- **HolyGL as an API with backends** `(from 03-design §3.5)`: `HolyGL(API) → soft (NEON×SMP) | virtio-gpu (virgl)
  | native GPU | remote (cluster)`. Acceleration is execution units of one model, not tiers. **[PARTIAL]** today (software only).
- **Unified Tile Pipeline** `(from 03-design §3.6)`: frame = set of tile jobs; a *provider* executes them; SIMD =
  kernel shape, SMP = core count, GPU = a provider; all at once; no scalar fallback (AArch64 mandates NEON);
  deterministic per tile (same on 1 vs N cores). **[MISSING]**.
- **Barycentric perspective 3D** `(from FUTURE roadmap §3, forensic dossier §3.4/§4.3)`: kill `z_avg`; Pineda 28.4
  fixed-point edge equations; perspective-correct `1/w, z/w, u/w, v/w`; NEON fast reciprocals. **[MISSING]**.
- **Textures & lighting** `(from FUTURE roadmap §3.3, complete_render_stack §3.4)`: `glTexImage2D`/`glBindTexture`,
  bilinear (and trilinear) filtering; Blinn-Phong specular; alpha blend modes (additive/multiply). **[MISSING]**.
- **Mesh ingestion** `(from FUTURE roadmap §3.4)`: streaming Wavefront OBJ parser in HolyC. **[MISSING]**.
- **HolyGL as the compositor backend** `(from FUTURE roadmap §3.5)`: DolDoc 2D cards/glass/shadows → HolyGL textured quads.
- **Shader engine (native 2×2 NEON quad SoA)** `(from FUTURE roadmap §4, forensic dossier §3.5/§4.2, SKILL.md Order 17)`:
  evaluate 4 pixels/iteration with NEON lanes; Newton-Raphson `FRSQRTE`/`FRSQRTS`; `dFdx`/`dFdy` via lane
  permutations; execution masking (a per-lane predicate + mask stack); raymarched SDF primitives; multi-octave
  Perlin/fBm noise; Mandelbulb; a text assembler for custom shaders. **[REAL — P4.6]** (`apps/ShaderVM.HC`,
  `scripts/shader_quad.s`); the legacy 2-D `$SHADER$` approximations remain in `DolDoc.HC` for the other type
  strings. 32×32 tile parallelism across 4 cores is still open (P9).
- **NEON span rasterizer** `(from single_core…_audit §2/§4, complete_render_stack §3.4)`: 8-pixel simultaneous
  depth test (`cmlt.8h`), branchless select (`bsl`/`bit`), 64-byte vector writes.
- **F32x4 SIMD as a HolyC primitive** `(from neo_os_grand_architecture_manifesto §8)`: `F32x4 v1 = {…}; v1+v2 → fadd v0.4s`.
- **Direct hardware access in HolyC** `(from manifesto §8)`: typed pointer derefs (`#define VIRTIO_GPU_STATUS *(U32*)(…)`)
  and inline bracketed asm.

### 3.1 P4 implementation decisions & references (research, 2026-10)
These are the *chosen* implementations for the P4 steps (doc 2 §P4), with the sources that justify them.
- **Rasterization — Pineda incremental edge functions, 16.16 fixed-point, top-left fill rule.** Pineda's
  1988 "A Parallel Algorithm for Polygon Rasterization" is the canonical parallel-friendly method; integer
  16.16 gives deterministic coverage. Refs: scratchapixel "Rasterization Stage"; krzosa/software_rasterizer
  (SIMD+MT); "A Trip through the Graphics Pipeline" (why scanline does *not* map to SIMD).
- **Tiling & determinism — bin triangles into 64×64 tiles, per-tile job queue.** Per-tile results are
  order-independent, so 1 core == N cores. Refs: vblanco20-1/Rasterizer (tile binning, lock-free queues);
  Zielon/CPURasterizer (AVX2, tiled); Laine 2011 "High-Performance Software Rasterization" (bin → coarse →
  fine stages).
- **NEON 8-wide spans, branchless depth.** Arm NEON intrinsics reference (`cmlt.8h` compare → `vbsl`/`vcgt`
  select, 64-byte stores); HolyC emits NEON words via inline `asm {}` today. Ref: Arm ACLE NEON reference.
- **Perspective-correct interpolation.** Interpolate `1/w, z/w, u/w, v/w`, divide per pixel (kills `z_avg`).
  Ref: scratchapixel perspective-correct texture mapping.
- **Color & blending.** Shade in linear light, present sRGB, store premultiplied alpha for correct compositing.
  Refs: Søren Sandmann "Gamma Correction vs. Premultiplied Pixels"; HN #33301471 (premul + dithering in 8-bit).
- **Fonts — bitmap for small text + analytical SDF for scalable.** Build the SDF from the existing bezier
  outlines (single-channel) and sample with `smoothstep`; MSDF is the multi-channel upgrade. Refs: Viktor
  Chlumsky MSDF thesis + FreeType SDF renderer (GSoC 2020); stb_truetype SDF; redblobgames SDF guide.
  Atlas packing: stb_rect_pack shelf packing.
- **Fragment-shader VM.** Small register bytecode VM, 2×2 quad (SoA), lane-permutation derivatives, execution
  masking — **implemented in P4.6** (see §3.1.2). Refs: Schmalstieg et al. "A High-Performance Software
  Graphics Pipeline Architecture for the GPU"; ProtonVM (parallel bytecode interpreter).
- **Mesh ingestion.** Streaming OBJ parser handling negative indices + n-gon triangulation. Refs: nullprogram
  "Robust Wavefront OBJ parsing in C" (2025); rapidobj / tinyobjloader.
- **virtio-gpu: 2D-only for P4; 3D deferred to P9.** Virgl/Venus require host Vulkan + a large QEMU patch set
  and are still landing upstream. Refs: Collabora "Venus on QEMU"; Mesa virtio-gpu Venus docs; QEMU virtio-gpu
  docs (`-device virtio-gpu-gl,hostmem=8G,blob=true,venus=true`).

#### 3.1.1 P4.5 shading implementation notes (2026-10)
- **Smooth shading in one kernel via a mode dispatch, not a second rasterizer.** `CRasterSpan.gmode` selects
  the colour stage *after* the shared coverage/depth mask, so Pineda/top-left/exact-64-bit-Z are written once.
  gmode 0 is the original solid store (byte-identical → the golden hash is a live invariant, not a snapshot).
- **Affine accumulators instead of per-pixel division.** A perspective divide per pixel for colour/normal is
  wasteful when the quantity is linear in `x`; the C side precomputes the value at `x_start` and the per-pixel
  delta, and the kernel steps the accumulator by `8*delta` per block. This is the classic incremental-shading
  trick (Gouraud 1971), done in NEON (`FMLA v.4s, v.4s, [0..7]`).
- **Per-fragment normal normalize = `FRSQRTE` + one `FRSQRTS` Newton–Raphson step.** Arm's `FRSQRTE` gives a
  ~8-bit reciprocal-sqrt estimate and `FRSQRTS` supplies the `(3 - x·y²)/2` term of the Newton iteration —
  exactly the "normalize a vector in a shader" idiom. One step is enough for 8-bit output. Ref: Arm ARM
  `FRSQRTE`/`FRSQRTS`; "Fast Inverse Square Root" (Lomont). No scalar fallback in the span body.
- **Blinn-Phong, exponent 16, gamma-corrected.** `N·H` (Blinn 1977) avoids the reflect-vector; `(N·H)^16` via
  four `FMUL` squarings; ambient+diffuse+specular summed in **linear light** and presented with `sqrt`
  (≈ sRGB). Base colour is linearised at the C side (`(c/255)²`). Refs: Blinn 1977; Sandmann gamma/premul.
- **Root cause of the gears "geometry" bug was the compiler, not the mesh.** Cross-unit F64 function return
  types were dropped because `HcReset()` cleared the per-unit function table every unit — so `r * MathCos(a)`
  emitted `scvtf` on the double's raw bits. Fixed with a persistent name→returns-F64 table + a brace-depth-0
  `HcPrescanFuncs` pre-pass. Lesson: a codegen type-loss bug can masquerade as a geometry/math bug for a long
  time; always dump raw vertex *bits* before blaming the algorithm.

#### 3.1.2 P4.6 fragment-VM implementation notes (2026-10)
- **Register VM, not a stack VM, over a 2×2 quad.** A stack VM's push/pop traffic dominates when the data is
  already vector-shaped; a fixed 16-register file × 4 lanes (SoA) maps one instruction to one NEON op across
  the whole quad. Instruction = `[op, a, b, c]` (4×I64). The interpreter is a plain dispatch loop; the
  arithmetic is out-sourced to a hand-encoded NEON core so "4 px/iteration" is literal.
- **The NEON op core (`ShaderOp4`) is the whole point.** `aarch64` gives `fadd/fsub/fmul/fdiv/fmin/fmax` and
  `fabs/fneg/fsqrt/frintm` for `.2d`, so a 4-lane double op is two `.2d` instructions. `rsq` uses
  `FRSQRTE` + one `FRSQRTS` Newton step (the same idiom P4.5 uses to normalize). Hand-assembled in
  `scripts/shader_quad.s` (75 words) and embedded via `asm {}` — the compiler emits the prologue/epilogue, so
  the block has no `ret`. Ref: Arm ARM ASIMD `FRSQRTE`/`FRSQRTS`.
- **Derivatives are a lane permutation, not a separate pass.** With the quad laid out
  `0=(x,y) 1=(x+1,y) 2=(x,y+1) 3=(x+1,y+1)`, `dFdx` is `(v1−v0, v1−v0, v3−v2, v3−v2)` and `dFdy` is
  `(v2−v0, v3−v1, v2−v0, v3−v1)` — the hardware's own 2×2 finite difference, so no extra helper lanes.
- **Execution masking with a predicate stack.** `if r[a]` builds a 4-bit predicate (`r[a] > 0` per lane) and
  intersects it with the active mask; every op writes only active lanes; `else` recomputes from the saved mask
  and `~pred`; `endif` restores. The masked `mandel` program is the proof: escaped lanes stop iterating while
  the rest continue. This is a software analogue of GPU predication.
- **Library first, VM second.** The heavy, reusable kernels (Perlin gradient noise, multi-octave fBm, the
  Mandelbulb DE with hand-rolled `atan2`/`acos`/`log`, SDF primitives) are native functions exposed as VM
  opcodes — fast and correct — and the generic VM composes them for custom shaders (a small text assembler:
  `mnemonic a, b, c`, `label:`, `//` comments, two-pass label resolution). This matches how real engines ship
  a shader stdlib and a compiler.
- **Raymarch in 4-lane NEON via composition.** `ShaderField4` evaluates the scene SDF for four lanes by
  chaining `ShaderOp4` calls, so the ray *field* is 4 px/iteration even though the per-lane ray parameter
  update is scalar. Normals are finite differences of the field (6 more `ShaderField4` calls), then Blinn-Phong
  + gamma. The demo renders a sphere+torus+plane (`shadervm`).
- **Two compiler root bugs surfaced and were fixed (D13).** (1) A **local array's element floatness** was never
  set on the local-array path, so it inherited the *previous* declaration's type and `F64 a[3]; a[0]=1.0`
  stored/loaded raw integer bits. (2) Indexing a **pointer local** (`F64 *p; p[i]`) used the pointer's own
  floatness (always 0) instead of the **pointee**. Fixed by tracking element/pointee floatness separately
  (`g_hc_decl_elem_float` → `g_hc_local_elem_float`) and consulting it on subscript. Lesson (again): local
  aggregate type tracking is a landmine — a VM's scratch arrays are the perfect probe for it.

#### 3.1.3 P4.7 OBJ mesh implementation notes (2026-10)
- **Streaming, one pass, no allocator.** `MeshParseOBJ` walks the source line by line, tokenizes with a tiny
  whitespace splitter, and writes into fixed-capacity `CMesh` globals. No `kmalloc`, so the `.HC`→C census
  stays at 181. Hand-rolled `MeshAtoiTok`/`MeshAtofTok` (the runtime has no `strtod`), including exponent
  handling. Negative indices resolve against the *current* vertex/normal/texcoord counts (`count + v`), which
  is exactly the OBJ relative-index rule. `MeshParseCorner` splits `v/t/n`, `v//n`, `v/t`, `v` by '/' into three
  fixed fields — the normal is field **2**, the texcoord field **1** (getting this backwards makes every face
  fall into the "compute a normal" path).
- **Render through the ONE pipeline.** `MeshRender` uses HolyGL immediate mode exactly like `Gears3DRenderMesh`,
  so the mesh inherits real per-pixel Z, perspective, and P4.5 per-fragment Blinn-Phong for free — no second
  rasterizer, no new gate machinery. DolDoc's `$SP,type="mesh"` binds the node to `MeshRenderViewport` by
  direct call (Stage 5 loads Mesh before DolDoc), keeping the census flat.
- **Debugging: the bug was in the compiler, not the parser.** The parser was provably correct (`v=8 n=6 f=12`);
  the fault was a wild read in the post-parse normal-fill loop. The decisive move was to reproduce the *exact*
  shape in the live REPL: `struct PQ{I64 a[4];}; I64 pqg(PQ*p){F64 b=1.5; I64 b=1; return p->a[b];}` panicked
  identically. Every earlier probe had passed because it used a **uniquely-named** local or a **literal** array
  dimension — the one thing they never did was **redeclare a name with a different type** (D14) or use a
  **compound member-array dimension** (D15). Lesson: when a "geometry" fault survives a dozen correct-looking
  probes, enumerate what all the probes *share* and violate it deliberately.
- **The two root fixes were in the compiler, and one was in both compilers.** D14 (`HcAddLocalTyped` must
  refresh a redeclared local's type flags) is self-hosted-only; D15 (member-array `N*M` dimensions) existed
  identically in `apps/Compiler.HC` **and** `boot/seed/jit_arm64.c`, and the in-guest **parity** gate caught the
  seed half immediately (`PARITY … 1 diff`) — a nice demonstration that the twin-engine parity check is doing
  real work, not ceremony. Fix both, keep the gate at 0 diff.
- **Self-consistency can hide a layout bug.** D15 changed `sizeof(CMesh)` from 28704 to 53280 and moved `fni`/
  `ft`, yet nothing broke *before* the fix because the definition and every use shared the same (wrong) offsets.
  The tell is `sizeof`/cross-engine layout, not a render diff — worth remembering for any struct with computed
  member dimensions.

---

## 4. Compiler research (beyond self-hosting)

`(from 00-MASTER-CONSOLIDATED-PLAN §11, 00-CONSOLIDATED §8, forensic dossier §3.6, neo_os_grand_architecture_manifesto §8, SKILL.md Order 7)`
- **Class inheritance + virtual method tables** (C++-style HolyC). **[MISSING]**
- **Optimizing JIT** (basic-block SSA + linear-scan register allocation across `X19–X28`/`D8–D15`; ~600% speedup claim).
- **Incremental recompile cache** (Zig-style).
- **Linear-scan register allocation** to kill per-operator push/pop.
- **F32 support** (for SDL/raylib ports; `Jamesbarford/holyc-lang` adds F32 specifically for this).
- **Table-literal / global-initializer breadth.**
- **AArch64 NEON 4-lane intrinsics** (`DUP.4S`/`FADD.4S`/`FMUL.4S`/`FMLA.4S`/`FRSQRTE.4S`).
- **True self-host from source** (Option C): a tiny seed compiles `Compiler.HC` from `.HC`; then self-verify.

---

## 5. "Run anything at max native performance" — the porting ladder

`(from 03-design §3.10, POST_DOM §7, consolidation_dossier §3, SKILL.md Orders 19–20)`

| Tier | How | Perf | Unlocks |
|---|---|---|---|
| 0 Native | HolyC/AArch64 | native | your code |
| 1 Recompiled source | C/C++/Rust/Zig → AArch64/HolyC | ~native | decompiled games |
| 2 WASM JIT | real WASM→AArch64 JIT | good | portable ecosystem |
| 3 Emulation | x86/ARM/RISC-V translator | 0.2–0.8× | any binary |

- **`HolyPort`** — an SDL/raylib-like platform layer (window, input, audio, files, threads, timers). **[MISSING]**
- **Sovereign SDL** — a ~500-line SDL 1.2/2.0 ABI mapped to Ring 0 (`SDL_SetVideoMode`→GOP; `SDL_PollEvent`→input;
  `SDL_OpenAudio`→DMA ring; `SDL_GetTicks`→`cntvct_el0`). **[MISSING]**
- **Game ports:** Quake (WinQuake/GLQuake), Half-Life 1 (Xash3D FWGS), N64Recomp (Zelda MM, Perfect Dark, SM64,
  OoT). **[MISSING]**
- **Static recompilation** (MIPS→C99 → compile with the NeoOS toolchain). **[MISSING]**
- **Android NDK** (run `arm64-v8a` `libapp.so` directly — already native; needs Bionic libc + `libandroid.so`
  shims). **[MISSING]**
- **DEX→AArch64 transpilation** (Dalvik/ART-lite JIT). **[MISSING]**
- **WASM** (`WasmJit.HC`, 4-opcode toy). **[GONE]** — not in current apps.
- **C→HolyC / LLVM→HolyC toolchain.** **[MISSING]**

---

## 6. Hardware scaling (MCU → superphone)

`(from 03-design §3.11, manifesto §12–13, ring0 manifesto §3, consolidation_dossier §3)`
- **MCU cluster (future):** ESP32 is Xtensa/RISC-V (not AArch64); needs a RISC-V backend + node runtime; the tiled
  renderer maps onto nodes; OmniTape display list is serializable; work-stealing → cluster work-stealing; the
  `Surface` abstraction unifies screen/window/texture/remote. **[MISSING]** (note: master plan §10 open question
  RISC-V vs Xtensa; whole-OS vs render/compute offload).
- **RP2040 (Cortex-M0+ @133 MHz, 264 KB):** 320×240 8-bit paletted; zero-RAM tile streaming over SPI/PIO; Thumb JIT. **[MISSING]**
- **RP2350 (Cortex-M33 @150 MHz, 520 KB):** FPU + Thumb-2 JIT; 320×240 RGB565 double-buffered; 3D HolyGL @60 FPS. **[MISSING]**
- **RK322x/RK3399 (Cortex-A7/A72):** $15 TV box → instant-boot sovereign desktop; 1080p/4K HDMI via Rockchip VOP. **[MISSING]**
- **Poco X3 Pro / Snapdragon 860 (Kryo 485):** 120 Hz FHD+; LPDDR4X; UFS 3.1. **[MISSING]**
- **Mobile silicon realities:** I2C touch digitizer + GPIO IRQ; PMIC backlight (WLED/PWM); audio codec DMA;
  baseband powered down for air-gap; vendor GPUs — Adreno 640 (Freedreno A6xx command packets, WPTR doorbell),
  Mali-400 (Lima command streams). **[MISSING]**
- **FDT/DTB parser** for Pi 4/5, RK3326, Snapdragon. **[MISSING]**

---

## 7. Ring-0 native embeddings engine ("semantic dispatch")

`(from ring0_embeddings_engine_manifesto, neo_os_grand_architecture_manifesto §2/§14, neo_os_consolidated_defect_record C19)`
**[MISSING]** — explicitly "0 weights / 0 inference code"; a research manifesto, not implemented.

- **What it is:** a *discriminative* intent router — **Vectorized Retrieval-Augmented Dispatch (RAD)**, NOT RAG,
  NOT an agent harness. Input string → embedding `q ∈ S³⁸³` → `argmax(q·aᵢ)` over pre-compiled action anchors →
  **verified function pointer**. No text generated.
- **Model:** 6-layer, 384-dim INT8 transformer encoder (~22 MB), 12 heads, vocab 30,522; contiguous
  `EMBED_MODEL.BIN` on RedSea; loaded by one VirtIO-Blk DMA in ~18 ms.
- **Hardware:** ARMv8.2-A `sdot` (16 INT8 MACs/cycle); dual-issue ~94.7 GOPS on a 2.96 GHz prime core.
- **Tokenizer:** zero-allocation fixed-window WordPiece in a 16 KB stack buffer (~8.2 µs; 0 heap bytes).
- **Search:** NEON `sdot` kernel; 5,000 entries in ~420 µs on Cortex-A76.
- **3-Zone safety:** Green `S ≥ 0.82` (autonomous dispatch); Yellow `0.60 ≤ S < 0.82` (DolDoc disambiguation);
  Red `S < 0.60` (safe rejection). "Mathematically impossible for out-of-distribution input to trigger an action."
- **`kernel_action_t`** (`action_id`, `handler`, `anchor_vector[384]`, `expected_arg`, `arg_min/max`,
  `confidence_gate`); `SemanticShellExecute(prompt)`.
- **Applications:** semantic shell (no syntax memorization); semantic code navigation (death of `grep`); semantic
  code completion; **Divine Oracle 2.0** (embed Bible/Aurelius; retrieve nearest resonant passages).

---

## 8. Telemetry & benchmarking research

`(from FUTURE roadmap §6, forensic dossier §3.7/§4.4, bench_empirical_analysis §3)`
- **ARMv8 PMU:** enable via `PMCR_EL0`; read `PMCCNTR_EL0` (cycles), `INST_RETIRED` (0x08), `L1D_CACHE_REFILL`
  (0x03), `BR_MIS_PRED` (0x10). **[MISSING]**
- **Statistical frame pacing:** median (p50), 1% low (p99), 0.1% low (p99.9), jitter variance σ. **[MISSING]**
- **Sub-millisecond stage breakdown:** `Δt_total = Δt_geom + Δt_rast + Δt_blit + Δt_wm + Δt_smp`.
- **Root-cause spike logger:** frames >33.3 ms tagged (`VIRTIO_POLL`, `COMPOSITOR_OVERDRAW`, `RASTER_BURDEN`,
  `GOP_BLIT_MEM`). Logs: `/BENCH_REPORT.TXT`, `/BENCH_COMPARISON.TXT`, `BENCH_PROFILER.LOG`, `BENCH_SPIKES.LOG`.
- **Purge synthetic constants** (`blit_us=1200`, `dma_us=400`, `wm_us=300`) and "PERFECT (100%)" strings.
- **`BenchCpu` real SIMD** (currently an integer LCG — BEN-01) + PMU counters.

---

## 9. Kernel & driver ideas

`(from 00-MASTER-CONSOLIDATED-PLAN §11, neo_os_grand_consolidation_encyclopedia §10, SKILL.md Orders 3–12)`
- **FDT parser** (Pi 4/5, RK3326, Snapdragon) to de-hardcode MMIO. **[MISSING]**
- **Audio:** virtio-snd / Intel HDA + HolyC synthesizer. **[MISSING]**
- **Networking:** virtio-net + lwIP (Telnet/HTTP/remote HolyC REPL). **[MISSING]**
- **USB xHCI** host controller. **[MISSING]**
- **Virtual memory protection** (optional Memory Domains / MTE) while preserving SASOS zero-copy. **[MISSING]**
- **SMP dynamic work-stealing** (`ldaxr`/`stlxr` deques). **[MISSING]**
- **RedSea improvements:** sector reclamation on delete; dynamic `next_alloc_lba`; grow-allocates; deep subdirs;
  real uptime/RTC timestamps; fix `cd ..` parent popping. **[MISSING]/[PARTIAL]**
- **Physical page frame allocator (PMM)** + buddy allocator (from `neo_os_architecture_specification §2.4/§2.5`). **[MISSING]**

---

## 9.5 RedSea v2 — the filesystem (design target: the best FS in the world)

`(research this session via Tavily; see "Research basis" below)`

**Why NeoOS can beat ZFS/bcachefs/Btrfs/Hammer2/RedoxFS on the things that matter here**
- **SASOS** — a file *is* a range of physical memory: `open()` returns a pointer, `mmap` is free, DMA runs
  straight out of the file buffer (**zero-copy**). No mainstream FS can do this.
- **No legacy** — design for NVMe/virtio queue semantics, not 1970s platters.
- **HolyC + JIT** — the on-disk format can be **compiled into accessors at mount** (JIT + zero-copy
  serialization, cf. Apache Fury / Cornflakes), and programs are HolyC (**exec = JIT**, no ELF loader).
- **Full-stack ownership** — block driver, FS and VM are ours.

**Architecture — a checksummed, copy-on-write Bε-tree**
- **Bε-tree** (BetrFS, USENIX FAST '15) instead of a B+tree: write-optimized; batches many random updates into
  few sequential writes — ideal for SSDs (kills write amplification).
- **Merkle-tree checksums** (ZFS): each block's checksum lives in its parent pointer; the whole store is a
  self-validating tree → silent-corruption detection + **self-healing** (rebuild from a snapshot / parity).
- **Copy-on-write + superblock ring** (ZFS/bcachefs): never overwrite live data; a commit is an atomic switch
  to the newest valid superblock generation → **never fsck**, **instant snapshots**, crash consistency.
- **Extents + inline data**: tiny files live inside the inode; big files are extent lists.
- **Inline compression** (LZ4 default, Zstd optional) + **content-defined chunking** (CDC, Rabin/gear) for
  **dedup** and casync-style deltas.
- **Power-loss safety à la littlefs**: two-phase commit on the superblock ring.
- **Tiering**: RAM disk (already present) + persistent disk; hot data cached in RAM.

**Novel NeoOS twists (the "insane" part)**
1. **Compiled filesystem** — metadata are HolyC classes; at mount the JIT emits typed accessors → ~0 parse cost.
2. **Executable filesystem** — programs are HolyC source; "exec" = JIT; no ELF/loader.
3. **Direct-mapped files** — `open()` = pointer; DMA straight from the file buffer.
4. **Semantic/typed files** — files carry schemas; the FS indexes fields → queryable, DB-like.
5. **Self-healing** — checksums + snapshots reconstruct corrupt blocks (optional erasure coding).
6. **Capability-secured** — SASOS has no rings; capabilities gate file/device access (no ambient authority;
   cf. CheriOS).
7. **Whole-OS versioning** — snapshots are the version unit (Git-for-the-OS).

**Format sketch** — superblock ring (N copies: generation + checksum + root) · Bε-tree nodes (keys +
values/messages + checksums) · inode (type/size/time/extents|inline/xattrs/schema) · extent (logical, len,
phys, compression, checksum) · chunk store (content hash → phys).

**Guarantees** — atomic commits · O(1) snapshots · no fsck · verify-on-read · self-heal.

**Inspired by every filesystem (what we take from each):**

| FS | What we borrow |
|---|---|
| **FAT/exFAT** | Ubiquity — used **only as the boot medium** the firmware reads; not the OS FS. |
| **ext4** | Extents, delayed allocation, journaling ideas (we replace journal with COW). |
| **XFS** | Allocation groups; B+tree-indexed free space; scalability. |
| **NTFS** | B+tree directory indexes; a metadata log; alternate data streams (→ typed xattrs). |
| **ReFS** | **Integrity streams** (per-block checksums); COW B+tree; "no fsck, ever". |
| **ZFS** | **Merkle checksums**, COW, **snapshots**, pooled storage, **self-healing**, dedup, ARC cache. |
| **Btrfs** | COW subvolumes/snapshots; checksums; RAID; transparent compression. |
| **bcachefs** | **Bε-tree** metadata; checksums; COW; **tiering**; encryption; erasure coding. |
| **BetrFS** | The **Bε-tree** write-optimization (batch random writes → sequential). |
| **Hammer2** | Clustering; instant snapshots; COW; dedup. |
| **APFS** | **Containers (space sharing)**, **clones**, snapshots, encryption-first, COW. |
| **littlefs** | **Power-loss safety** via two-phase atomic commits; wear leveling. |
| **F2FS** | Log-structured, flash-friendly allocation. |
| **Sprite LFS** | Append-only log writes; segment **cleaning** (garbage collection). |
| **NILFS** | Continuous, cheap snapshots as a first-class feature. |
| **WAFL (NetApp)** | COW + snapshots designed for storage arrays. |
| **RedoxFS** | A clean ZFS-inspired design in a microkernel OS (our closest sibling). |
| **IPFS / casync** | **Content-addressed** chunks; dedup; delta/sync. |
| **Venti/Fossil** | Content-addressed archival of every version. |
| **Plan 9 / 9P** | "Everything is a file" — one namespace for FS, devices, network. |
| **TempleOS RedSeaFS** | The name + the SASOS "files are memory" ethos (done properly). |

**Net design:** ZFS's integrity + bcachefs/BetrFS's Bε-tree + APFS's containers/clones + littlefs's
power-loss discipline + IPFS's content addressing + Plan 9's unified namespace — **plus three things no
mainstream FS has**: SASOS zero-copy, JIT-compiled metadata, and executable (HolyC) files.

**Research basis:** BetrFS (betrfs.org, FAST '15), ZFS Merkle integrity, bcachefs (bcachefs.org), Hammer2,
RedoxFS (Redox OS), littlefs DESIGN.md, APFS clones/snapshots, ReFS integrity streams, Sprite LFS,
IPFS/casync content addressing, Apache Fury / Cornflakes zero-copy+JIT serialization, CheriOS
(single-address-space capabilities), SPDK/NVMe multi-queue.

## 9.6 The driver suite — rebuild everything, "10000%" (roadmap)

`(research this session via Tavily; slot into P3/P4/P9)`

| # | Subsystem | Perfect-driver goal | Basis |
|---|---|---|---|
| 1 | Block: virtio-blk → NVMe, AHCI, SDHCI, USB-MSC | multi-queue async, zero-copy DMA, polled mode, hotplug | SPDK / NVMe |
| 2 | Partitioning: GPT/MBR/RedSea | GUIDs, redundant headers, auto-discovery | UEFI/GPT |
| 3 | Storage mgmt: RAID/erasure, **AES-XTS** encryption, integrity | self-healing, keys never touch disk | ZFS/bcachefs |
| 4 | Network: virtio-net/e1000 + HolyC TCP/IP | zero-copy, SMP-scalable, modern CC | lwIP ideas |
| 5 | Input: virtio-input, USB HID, PS/2 | sub-ms latency, multi-touch, hotplug | — |
| 6 | Display/GPU: virtio-gpu + GOP | 2D/3D accel, vsync, multi-monitor | — |
| 7 | Interrupts: GICv2/v3 + MSI/MSI-X | per-CPU, priorities, low latency | ARM GICv3 |
| 8 | PCIe: ECAM enum, BAR/IOMMU | hotplug, DMA remapping | — |
| 9 | Timers/RTC: ARM generic timer, RTC | nanosecond, tickless, monotonic | — |
| 10 | Power: PSCI + ACPI | suspend/shutdown/thermal | — |
| 11 | RNG: virtio-rng + `RNDR` | crypto-grade | — |
| 12 | Sound: virtio-snd | low-latency mixing | — |
| 13 | Memory: PMM/buddy, DMA pools, optional MMU/MTE | NUMA-aware, huge pages, SASOS-preserving | — |
| 14 | Security: capability model (no rings) | fine-grained caps, no ambient authority | CheriOS |
| 15 | Firmware: UEFI runtime, ACPI, FDT | unified device discovery, de-hardcode MMIO | — |
| 16 | Console: PL011/16550/framebuffer | one unified console | — |
| 17 | Watchdog / thermal | auto-recover, throttle | — |
| 18 | Telemetry: PMU, tracepoints | zero-overhead profiling | — |

**Cross-cutting foundations:** one async/polled I/O model; DMA + IOMMU; capability security; power management;
zero-overhead telemetry; device discovery (ACPI/FDT) so nothing is hardcoded.

### 9.7 P3 implementation decisions & references (research, 2026-10)
The *chosen* implementations for the P3 steps (doc 2 §P3), with sources.
- **GIC — stay GICv2 for P3.** QEMU `virt` under TCG defaults to **GICv2** (`GICD 0x08000000`, `GICC 0x08010000`),
  which is exactly what `Gic.HC` already programs; GICv3/ITS is a later platform item. Refs: QEMU `virt`
  docs / libvirt commit "Use GICv2 for aarch64/virt TCG guests"; Löwenware "AArch64 GIC and timer interrupt".
- **Timer IRQ — arm the EL1 virtual timer.** `CNTV_TVAL_EL0 = freq/hz`, `CNTV_CTL_EL0 = 1`, PPI **27** on QEMU
  virt (`HalPlatform` already has `irq_timer = 27`); the EL1 *physical* timer is INTID **30**. Re-arm `TVAL` each
  tick (level-sensitive). Refs: "AArch64 Programmer's Guide: Generic Timer"; Löwenware.
- **Context switch — save callee-saved x19-x30 + SP + D8-D15.** The existing `kernel/sched/switch.S` already does
  this (AArch64 AAPCS64 callee-saved set); it just needs a caller (the tick/scheduler). Refs: CS3210 Lab 4
  (preemptive multitasking on AArch64); Harvard CS161 "Kernel yields"; Waterloo CS452 lec04.
- **Scheduler — round-robin within priority bands**, quantum ~10–50 ms, no starvation. Refs: osdev
  "Scheduling Algorithms"; Round-robin scheduling (Wikipedia).
- **Exceptions — derive recoverable-vs-panic from `ELR_EL1`/`SPSR_EL1`, not a hardcoded flag.** `ESR_EL1` EC
  (bits 31:26) classifies the fault; `FAR_EL1` holds the faulting address; `ELR_EL1` the return PC; `SPSR_EL1`
  the pre-exception PSTATE. Kernel (EL1) faults must reach the BSOD; only JIT-pool faults are recoverable.
  Refs: osdev "AArch64 Exceptions"; Wenbo Shen "AArch64 Exception Handling".
- **SMP — PSCI `CPU_ON`, per-core stacks/queues, cache coherency, `wfe`/`sev` idle.** Secondary cores must have
  identical `SCTLR/TCR/MAIR/TTBR0/VBAR` and shared data cleaned before handoff; prefer PSCI over spin-table.
  Refs: Bootlin "SMP bring-up on ARM SoCs"; optee_os "aarch64 MMU setup sequence"; Zephyr SMP docs.
- **Spinlocks — `LDXR/STXR` (or `LDAXR/STLXR`) + `wfe`/`sev`.** Load/store-exclusive with acquire/release
  semantics; `wfe` to back off. Refs: Linux arm64 memory-model; Arm "Software Synchronization Primitives in A64";
  Microsoft "The AArch64 processor, part 14: Barriers".
- **Memory discovery — UEFI `GetMemoryMap` (already used), not hardcoded.** `boot_probe_memory()` sizes the heap
  and JIT pool from `EfiConventionalMemory`. Ref: UEFI spec §7 Boot Services.

---

## 10. Things explicitly classified DEAD (do not resurrect)

`(from 00-CONSOLIDATED §3.4, 02-audit §2.5, forensic dossier §2.1)`
`Table.HC` (dup of `StdLib.HC`), `StdLib.HC` (unused), `Lexer.HC` (3rd tokenizer), `WasmJit.HC` (toy),
`Bench.HC`, `HolyBenchmark3D.HC`, `HolyGLTest.HC`; demos `Showcase/Menu/Top/calc/fact/Filer/Editor/SmpDemo`;
legacy C GUI `gui/*.c`, `drivers/gpu/*.c`, `drivers/input/*.c`, `kernel/arch/aarch64/{exceptions,gic,smp,timer}.c`,
`kernel/bench/*`, `kernel/math/*`, `kernel/physics/*`, `kernel/sched/sched.c`, non-AArch64 CRTs + linker scripts.
**Lua** (`compiler/lua*`) — **[GONE]** (excised Phase 5; see doc 04).

---

## 11. Consolidated research briefs (2026-10) — external best-in-class, mapped to NeoOS

Two read-only research briefs were produced (agents that only read the tree + the web; they did **not** edit
`neo-os`) and are persisted at:
- `docs/research/NEO_OS_AARCH64_ENGINEERING_BRIEF.md` — graphics / NEON / SMP / FS / fonts / compiler.
- `docs/research/holyc-aarch64-sasos-engineering-brief.md` — JIT/SIC / single-pass compiler / HolyC idioms /
  DolDoc 3.0 / reactive shell / SDF.

They give, per topic, the algorithm/pseudocode, the exact ARM64/NEON or C reference, pitfalls, and the SASOS
structure, with ~80 cited primary sources. The highest-value extracts:

**Rendering (P4.3/P4.4).**
- Perspective-correct attributes: `u = Σ wᵢ(uᵢ/Wᵢ) / Σ wᵢ(1/Wᵢ)`; the `area` factor **cancels** with the
  un-normalized edge functions, so the perspective divide is a single scalar `SDIV` per pixel (no per-pixel
  `area` divide). Keep coverage exact `I64`; attributes `16.16`. *(Scratchapixel; Andrew Chan.)*
- Bilinear weights **must sum to exactly 256** (compute 3, derive the 4th) or gradients "pump".
- `REPEAT` = `(u>>16) & (w-1)` (power-of-two; two's-complement handles negatives via `ASR`); `CLAMP` =
  `SMIN/SMAX` per tap. Alpha blend exact `/255`: `t=x+128; out=(t+(t>>8))>>8`.
- **NEON has no gather** (`TBL`/`TBX` are 64-byte register lookups, not memory). Fetch 8 texels with scalar
  `LDR`+`INS`; SIMD only the coordinate math (`SCVTF/FRINTM/FCVTZS`), the filter and the blend. Prefer the
  integer 16.16 path (matches the existing exact-Z kernel). *(ARM ARM C7.2.397; corsix.)*
  **Implemented in p4.3b:** a compact mask-skipped 8-lane loop, exact 64-bit `SDIV` for `u,v`, scalar gather
  packed to a stack buffer, and NEON bilinear (`UXTL`/`UMULL`/`UMLAL`/`SHRN`), modulate and alpha blend — all
  in the one `RasterSpanNEON` kernel. See doc 02 §p4.3b and doc 04 §D8.
- Fonts: **stb_truetype v2** signed-area AA rasterizer + `GetGlyphSDF` (or rasterize-then-**Felzenszwalb EDT**);
  SDF texel = `128 + 127*clamp(d/range,-1,1)`; reconstruct with `screenPxRange = range*(screen_h/tex_h)`.
  *(nothings.org; Valve 2007; redblobgames.)*
  **Implemented in P4.4:** a stroke font has no closed contours, so instead of a signed field the outlines are
  rasterised at 4x supersample and box-downsampled to a 24x24 **coverage** cell baked into a PoT atlas;
  `smoothstep` is folded into that coverage (a fixed-function composite can't evaluate SDF per fragment — that
  waits for P4.6). Composited by a bilinear coverage read into the framebuffer. See doc 02 §P4.4, doc 04 §D9.

**Concurrency (P3.9).** Vyukov bounded **MPMC** (per-cell sequence ⇒ ABA-free) + MPSC per-core inboxes;
`LDAXR/STLXR` (acquire/release) vs `LDXR/STXR` (+`DMB`); `STLR`/`LDAR` for the handoff; `WFE`/`SEV` idle.
Cortex-A72 is Armv8.0 ⇒ no LSE `CAS`; probe `ID_AA64ISAR0_EL1`. *(ARM sync guide; Linux arm64 memory model.)*

**File system (P2.8).** **CRC32C** reflected `0x82F63B78`, check vector `0xE3069283`; optional
`CRC32CB/CH/CW/CX`. littlefs metadata-pair + ZFS **uberblock ring** (monotonic `txg`, highest valid wins) for
power-loss-atomic commits; `DC CVAC`+`DSB SY` durability. *(mazzo.li; littlefs SPEC; ZFS case study.)*

**Compiler (P1.3).** The **SIC cell is the GOT/PLT slot** (`ldr x16,[&sym->address]; blr x16`) — indirect
call through data, not self-modifying code; no I-cache hazard. Hash: **FNV-1a 64-bit**. Single-pass: publish
a function **before** its body; arena + interned strings (P0.7 already did this for literals); fixup lists;
`CBZ/CBNZ` range = ±1 MiB (thunks for far). *(chibicc; SubC; MaskRay PLT.)*

**DolDoc 3.0 / shell (P5/P6).** Flat index-based `CDNode`; React **O(n) keyed reconciliation** (diff same-level
children only; keys from content/binding, never index); **memory-watch bindings** (`$DA`) replace an event bus;
symbol-table **O(1)** shell dispatch; command output is a mounted `CDoc`; `WFE` idle with `SEVL;WFE`.
*(React reconciliation; Smalltalk/LOOM SASOS; TempleOS DolDoc grammar.)*

**HolyC idioms (cross-cutting).** Pointer arithmetic is **byte-based** (only `[]` scales) — the P0.7b audit;
`#define` persists across modules; `class` (no `typedef`); no headers (whole-file compile + `#include` splice);
all values widened to 64-bit. *(TempleOS HolyC doc; Harrison Totty analysis.)*
