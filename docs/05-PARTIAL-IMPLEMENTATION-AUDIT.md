# NeoOS — 05 PARTIAL-IMPLEMENTATION AUDIT (Raven dossier & prior plans)

> **Purpose.** The user's order (ADR **D55**): *never implement anything partially.* This document is the
> **implacable, honest audit** of everything implemented so far in a preliminary / partial way, measured against
> the reference dossier **`docs/research/RAVEN_GUI_FORENSIC_STUDY.md`** (the forensic translation of
> `oscar-soirey/Raven`) and the prior plans (`DOLDOC_SOVEREIGN_UNIFIED_CONTINUUM_SPEC.md`,
> `SHELL_DOLDOC_SYMBIOSIS_BLUEPRINT.md`), **plus the completeness plan** for each item.
>
> **No mayonnaise.** Every row is grounded in real files/lines or a gate output. Where something was only a
> sketch, it is stated as such.

**Status legend:** ✅ DONE (full, verified by a gate) · 🟡 PARTIAL (real code, incomplete) · ⬜ NOT STARTED.

**Answer to the user's direct question** — *"was the Raven dossier fully ported?"* — **No.** Of the dossier's
six chapters, only a fraction is real: §2.3 springs (basic), §3.1 dual-Kawase blur (single-level), §4.1–4.3 a
rudimentary Slate measure/arrange, and §5 widget *vocabulary* (the tags parse and draw a placeholder body).
The optical physics (§3.2–3.4), the layout slot semantics (§4.2–4.5), the industrial widget *behaviour*
(§5.1–5.6), the typography (§4/§6) and the in-text shader pipeline are **not** ported.

---

## 1. Glassmorphism & optical physics (`apps/Effects.HC`, `apps/Render.HC`) — dossier §3

| # | Dossier item (§) | Status | Evidence / gap |
|---|---|---|---|
| 1.1 | Backdrop capture + dual-Kawase pyramid down/up (§3.1) | ✅ | **G2**: `EffectsKawasePyramid` (N levels, `EffectsPyrDown` 4-tap / `EffectsPyrUp` blend, exact UHADD, `g_fx_pyr` ping-pong), `EffectsGlassRegion` captures the framebuffer. |
| 1.2 | SDF rounded corners (§3.2) | ✅ | **G2**: `FxSdRoundRect` (analytic signed distance; d<0 inside, |d| = distance to the boundary). |
| 1.3 | Analytic normals from the SDF (§3.2) | ✅ | **G2**: central differences of the SDF → normalised surface normal. |
| 1.4 | Optical refraction (ray distortion at the rim) (§3.3) | ✅ | **G2**: sample displaced along the normal by `edge² * 9`. |
| 1.5 | Chromatic aberration (per-channel rim offset) (§3.3) | ✅ | **G2**: R and B sampled at ±`edge*2.5` along the normal. |
| 1.6 | Specular rim light (top-left light catch) (§3.3) | ✅ | **G2**: `|n·l|⁴ * edge * 230` with the light at the top-left. |
| 1.7 | Procedural grain (§3.4) | ✅ | **G2**: stable positional hash, ±3 levels. (Surrounding reflection is folded into the refraction sample.) |
| 1.8 | NEON kernel for the blur (§3.5) | ✅ | **G2**: the 1-D pass is the NEON `UHADD` kernel; the per-pixel **material** is scalar HolyC (correct; the dossier specifies NEON for the *blur*, not the material). |

**G2 COMPLETE (this phase).** `GLASS: PASS (4/4)` (SDF inside/outside/corner, rim brightness, chromatic
aberration, corner preservation) and `TRANS: PASS (6/6)`. Wired into `DolDocDrawGlass` via `EffectsGlassRegion`.

## 2. Slate layout (`apps/DolDoc.HC`) — dossier §4

| # | Dossier item (§) | Status | Evidence / gap |
|---|---|---|---|
| 2.1 | Measure (bottom-up) / Arrange (top-down) contract (§4.1) | 🟡 | `DolDocSlateLayout` + `DolDocSlatePass` arrange a container's following sibling run; there is **no per-node intrinsic measure** pass (sizes come from the tag). |
| 2.2 | Slot semantics: padding, Auto/Fill, spans, anchors, alignment (§4.2) | ⬜ | none. No `slot` on nodes; no `Fill()`/`Auto()`. |
| 2.3 | VBox/HBox **proportional** distribution (§4.3) | 🟡 | proportional split exists but ignores slot fill/auto and sub-pixel padding. |
| 2.4 | Matrix grid with spanning + track stretching (§4.4) | 🟡 | uniform `cols=` cells only; no row/col spans, no track sizing. |
| 2.5 | Splitter panes + interactive proportional resize (§4.5) | ⬜ | `$SPLIT$` draws two panes at a fixed `ratio`; **not interactive** (no drag, no elastic bar). |

**Completion plan (G2/G3).** Real `CSlot` (padding/align/fill/auto/span) read by the parent; intrinsic measure
pass; interactive splitters on the spring engine; grid track sizing. Regression: `LAYOUT: PASS` extended.

## 3. Industrial widgets (`apps/DolDoc.HC`) — dossier §5

| # | Dossier item (§) | Status | Evidence / gap |
|---|---|---|---|
| 3.1 | `$NODE_GRAPH$`: cubic-Bézier wires, harmonic sway, pin snapping, canvas pan/zoom (§5.1) | 🟡 | the tag parses and draws 3 static circles + 2 straight lines (`DolDocDrawWidget`). No Bézier, no pins, no sway, no pan/zoom. |
| 3.2 | `$BLOCK_EDITOR$`: Scratch puzzle notches, nesting mouths, magnetic snap (§5.2) | 🟡 | draws stacked rounded bars. No notch geometry, no mouth containment, no snap. |
| 3.3 | Pro text editor: line buffer, incremental lexer, gliding caret (§5.3–5.4) | 🟡 | caret spring added (G1); no line buffer/lexer/token spans. |
| 3.4 | `$DOCK$`: binary-tree (BSP) split, animated chasing, tab tearing (§5.5) | ⬜ | no dock; `$SPLIT$` is a fixed two-pane container. |
| 3.5 | `$ISLAND$`: morphing capsule physics + content crossfade (§5.6) | 🟡 | draws a static capsule panel. No morph, no crossfade. |
| 3.6 | Timeline / TreeView / color picker (§5.7) | 🟡 | `$TREE$`/`$GRAPH$` exist (basic); no timeline, no color picker. |

**Completion plan (G3).** Bézier wires with spring sway + pin hit-testing + canvas pan/zoom; block notch geometry
+ snap; real BSP dock with drag; island morph (SDF interpolation) + badge crossfade; timeline + color picker.
Regression: `INDUS: PASS`.

## 4. Typography & vectors (`apps/Fonts.HC`, `apps/DolDoc.HC`) — dossier §4/§6

| # | Dossier item | Status | Evidence / gap |
|---|---|---|---|
| 4.1 | `FontVector.HC`: analytic strokes for all 95 printable ASCII glyphs | 🟡 | `apps/Fonts.HC` has a boot-baked AA atlas + some vector work; **not** a complete analytic 32..126 stroke set. |
| 4.2 | Elastic tabstops (column alignment by real word width) | ⬜ | the text flow still advances by `col * 8` / `row * 18` cells. |
| 4.3 | Math formatting (`$EQ$`/`$MA$`): centred fraction bar, stretching radical | 🟡 | `DolDocRenderEquation` draws a basic expression; no fraction/radical layout. |

**Completion plan (G4).** Complete the 95-glyph analytic set with dynamic scaling; elastic tabstops replacing the
cell grid; real fraction/radical/limit math layout. Regression: `TYPE: PASS`.

## 5. WM / Shell / Compositor dissolution — prior plans

| # | Item | Status | Evidence |
|---|---|---|---|
| 5.1 | `WM.HC` / `Compositor.HC` deleted | ✅ | files do not exist; absorbed into `DolDoc.HC` (P5). |
| 5.2 | Windows are `$WIN$` document nodes | ✅ | `DolDocParseWindow` → `DolDocWinCreate`; `DOC_WINDOW` drawn by `DolDocDrawWindowNode`. |
| 5.3 | No rigid 128×48 character grid | ✅ | `g_doc_chars`/`g_doc_fg`/`g_doc_bg` gone; `g_doc_attr` is the per-char attribute **arena**. |
| 5.4 | Shell is a `$REPL$` node on the tape | 🟡 | `$REPL$` parses + draws a "Shell" panel; it is **not yet a live interactive input** bound to the shell. |
| 5.5 | `Desktop;` elevates the tape to tiled/windowed containers | ⬜ | not present. |

**Completion plan (G3/G5).** Make `$REPL$` a live input node (events → shell → DolDoc emit) and add the
`Desktop;` elevation. Regression: `SHELL: PASS` extended.

---

## 6. Execution order (each phase completes FULLY before the next; no partials)

1. **G2 (▶ now)** — Glassmorphism photorealistic + transition physics: Kawase **pyramid** (NEON), SDF rounded
   corners + specular rim, refraction + chromatic aberration, the full transition suite. Gate: `GLASS: PASS`,
   `SPRING: PASS`, `RENDER: PASS (0xD28836F)`.
2. **G3** — Slate slot semantics + interactive splitters + BSP dock + node-graph/block/island behaviour + `$REPL$`.
3. **G4** — 95-glyph analytic type + elastic tabstops + math layout.
4. **G5** — in-document shaders (`iTime`/`iResolution`/`iMouse`), 3D sprites, oscilloscopes.

**Invariant D55 applies to every row above:** an item is only moved to ✅ when it is complete and a gate proves
it. Until then it is honestly ⬜/🟡 — never committed as a stub.
