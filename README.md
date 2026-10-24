# NeoOS — AArch64 Ring 0 SASOS

> **TempleOS-inspired Single Address Space Operating System for AArch64, booting natively via UEFI.**  
> No Linux. No userspace. Ring 0 only. Real hardware. Zero compromises.

---

## Philosophy

NeoOS follows the **TempleOS Ring 0 SASOS philosophy**:

- **No gambiarras** — no workarounds, no mockups, no abstraction layers hiding reality
- **No userspace** — all code runs at EL1 (Ring 0 equivalent on AArch64) with full hardware access
- **Single Address Space** — kernel, JIT-compiled HolyC scripts, drivers, and apps share one flat 64-bit virtual address space
- **Zero-RAM & Double-Buffered Dual Mode** — NEON non-temporal blits (`stnp`) by default for artifact-free rendering, with on-demand zero-copy direct VRAM scanout (`zeroram on`) eliminating the 3.14 MB backbuffer entirely
- **Sovereign L1 Tile NEON SIMD** — hardware-aligned tile rasterizer with cache-resident depth and color rendering

<p align="center">
  <img src="docs/images/three_gears_perfect_render.png" alt="NeoOS 3D Gears HolyGL Engine" width="48%">
  <img src="docs/images/sixteen_phase_scorecard_live.png" alt="NeoOS 16-Phase Empirical Benchmark Scorecard" width="48%">
</p>

---

## 📚 Documentation

The documentation was consolidated to **exactly five canonical files** (the older 44 planning docs were merged
losslessly into them and archived under `docs/_superseded-old-docs/`):

- [**docs/00 — Master Plan**](docs/00-MASTER-PLAN.md): vision, invariants, and the full **P0 → P10 priority ladder**.
- [**docs/01 — Reality Audit**](docs/01-REALITY-AUDIT.md): verified claim-by-claim reality of the code, plus the upstream salvage audit (§L).
- [**docs/02 — Task List & Runbooks**](docs/02-TASKLIST.md): the per-phase task list and the **executable P7 runbooks**.
- [**docs/03 — Ideas & Research**](docs/03-IDEAS-AND-RESEARCH.md): every idea, design, and research direction.
- [**docs/04 — Contradictions, Decisions & Open Questions**](docs/04-CONTRADICTIONS-DECISIONS-OPEN-QUESTIONS.md): every decision `D1…D33`.

Also: [`AGENTS.md`](AGENTS.md) (standing directives + **§0 START HERE** — current state and the exact build/test loop),
[`SKILL.md`](SKILL.md) (the 20 sovereign mandates), and the [`harness/`](harness/README.md) browser console.

## Features

### 🧠 HolyC 2.0 JIT Compiler (AArch64 Native)

A from-scratch JIT compiler targeting native **ARM64 machine code**, inspired by Terry Davis's HolyC:

| Feature | Details |
|---------|---------|
| **Native AArch64 output** | Emits real 32-bit ARM64 instructions directly into executable memory pages |
| **All arithmetic** | `+`, `-`, `*`, `/`, `%`, `&`, `\|`, `^`, `~`, `<<`, `>>` |
| **All comparisons** | `==`, `!=`, `<`, `<=`, `>`, `>=` |
| **Logical operators** | `&&`, `\|\|`, `!` |
| **Ternary operator** | `cond ? expr_true : expr_false` |
| **Control flow** | `if/else`, `while`, `do-while`, `for` |
| **Switch/case/default** | Full fallthrough + break support, jump-dispatch table |
| **Break & continue** | Nested up to 16 loops deep, switch-aware |
| **Variables** | Up to 16 local 64-bit variables per function |
| **Functions** | Define and call functions from the REPL/scripts |
| **Character literals** | `'A'`, `'\n'`, `'\t'`, `'\0'` |
| **Branch backpatching** | CBZ/CBNZ/B.cond placeholders patched after code generation |
| **Self-test suite** | `selftest` runs the in-guest battery (99 checks) + two-engine parity, twins, symbols — validated on live hardware |

**Example HolyC scripts:**
```c
// Ternary
I64 x = 10;
I64 result = (x > 5) ? 42 : 99;

// Do-while
I64 n = 0;
do { n = n + 1; } while (n < 5);

// Switch with fallthrough
I64 v = 1;
switch (v) {
  case 1: v = v + 10;
  case 2: v = v + 20;
    break;
  default: v = 888;
}

// For loop with break/continue
I64 sum = 0;
for (I64 i = 0; i < 10; i = i + 1) {
  if (i == 3) continue;
  if (i == 7) break;
  sum = sum + i;
}
```

---

### 🎮 3D Rendering Engine

Fully software-rendered 3D engine running on the raw GOP framebuffer:

| Component | Details |
|-----------|---------|
| **Perspective projection** | 4×4 matrix pipeline with near/far planes |
| **Near-plane clipping** | Homogeneous clip-space triangle clipping prevents wrap-around artifacts |
| **16.16 fixed-point rasterizer** | Scanline fill with sub-pixel accuracy |
| **Z-buffer (16-bit)** | Per-pixel depth test for correct occlusion |
| **Top-left fill convention** | CubeCoders Jet-style tie-breaking for rasterizer correctness |
| **Back-face culling** | CCW outward winding, cross-product sign test |
| **Rotating 3D cubes** | `bench3d` — dual viewports: flat-shaded + Z-buffered |
| **GLXGears-style gears** | `gears` — 3 intermeshing gears with correct CCW winding on all faces |
| **SMP-accelerated** | Rendering dispatched across 4 Cortex-A72 cores |

---

### 🖥️ Zero-RAM Direct-to-VRAM Architecture

Default boot mode eliminates the traditional double-buffer RAM overhead:

```
Traditional:  CPU → RAM backbuffer (3.14 MB) → memcpy → VRAM GOP framebuffer
NeoOS:        CPU → VRAM GOP framebuffer directly (0 copies, 0 ms blit latency)
```

- `gfx_set_zero_ram_mode(1)` — activates Zero-RAM mode: `canvas.back_buffer = canvas.front_buffer`
- `gfx_swap_buffers()` and `gfx_swap_rect()` short-circuit immediately when `front == back`
- The dedicated RAM backbuffer is preserved for reversible mode switching
- RAM savings reported in real-time by `zeroram status` via DolDoc telemetry

---

### 🪟 Documents (DolDoc 3.0 — no separate window manager)

- **Windows are documents**: a `CDoc`/`CTree` scene graph (`$WIN$`/`$SPLIT$`/`$BLUR$`/`$ELEV$`); the old
  `WM.HC` and `Compositor.HC` were dissolved into `DolDoc.HC` in P5
- Per-character attributes (`$FG`/`$BG`/…), the full two-letter tag set, macros/forms/anchors/links/trees
- One damage tracker + one present; reactive cells and an action protocol (`DOC_ACT_*`)
- The shell is an inline document (`$REPL$`) over an O(1) FNV-1a command registry

---

### ⚙️ SMP — 4-Core Symmetric Multiprocessing

- Secondary cores brought up via **ARM PSCI** (`CPU_ON` hypercall)
- All 4 Cortex-A72 cores active from boot
- Cooperative + preemptive scheduler
- Spin-locks for SMP-safe shared state

---

### 💾 Memory Subsystem

- `kmalloc()` / `kfree()` — custom kernel heap allocator
- Page allocator for JIT code pages (RWX)
- Zero-RAM mode removes the 3.14 MB dedicated backbuffer page
- Memory map reported at boot via UEFI `GetMemoryMap`

---

## Screenshots

> All screenshots are real QEMU framebuffer captures — no mocks.

| Scene | Image |
|-------|-------|
| Dual 3D Cube Benchmark | ![bench3d](screenshots/bench3d_fixed.png) |
| GLXGears 3-Gear Demo | ![gears](screenshots/glxgears_fixed.png) |
| Both benchmarks side-by-side | ![dual](screenshots/dual_cubes_benchmarks_live.png) |
| Interactive shell | ![shell](screenshots/interactive_shell.png) |
| Boot menu | ![menu](screenshots/menu_live.png) |
| JIT self-tests + Zero-RAM live | ![jit](screenshots/all_enhancements_live.png) |

---

## Build Requirements

### Dependencies

```bash
# Ubuntu / Debian / Pop!_OS
sudo apt-get update
sudo apt-get install -y \
    gcc-aarch64-linux-gnu \
    binutils-aarch64-linux-gnu \
    qemu-system-arm \
    qemu-efi-aarch64 \
    mtools \
    python3-pillow \
    git make

# Fedora / RHEL
sudo dnf install -y \
    gcc-aarch64-linux-gnu \
    qemu-system-aarch64 \
    edk2-aarch64 \
    mtools \
    python3-pillow \
    git make
```

### Toolchain Versions Tested

| Tool | Minimum Version |
|------|----------------|
| `aarch64-linux-gnu-gcc` | 10.x |
| `aarch64-linux-gnu-ld` | 2.35 |
| `aarch64-linux-gnu-objcopy` | 2.35 |
| `qemu-system-aarch64` | 6.x |
| UEFI firmware | from `qemu-efi-aarch64` package |

---

## Build

```bash
git clone https://github.com/Carlos-Pina/neo-os.git
cd neo-os
make all
```

Produces:
- `build/BOOTAA64.EFI` — UEFI application (PE/COFF AArch64)
- `build/disk.img` — FAT32 bootable disk image

### Clean

```bash
make clean
```

---

## Run

### Interactive (GTK window — requires X11/Wayland)

```bash
make run
```

Boots in ~30 seconds: the C seed JIT compiles the 34 HolyC modules from RedSea, then the sovereign
`DolDocShell` starts. Run `selftest` at the prompt for the full in-guest regression battery, or
`bash scripts/golden-boot.sh` for the one-shot gate (which also captures a screenshot).

### Headless (screendump via QEMU monitor)

```bash
make run-headless &
sleep 10
echo "screendump /tmp/output.ppm" | socat - UNIX-CONNECT:/tmp/qemu-mon.sock
python3 -c "from PIL import Image; Image.open('/tmp/output.ppm').save('/tmp/output.png')"
```

### QEMU flags

```bash
qemu-system-aarch64 \
  -M virt,gic-version=2 \
  -accel tcg,thread=single,tb-size=512 \
  -cpu cortex-a72 \
  -smp 4 \
  -m 1024 \
  -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
  -device ramfb \
  -device virtio-gpu-device,xres=1024,yres=768 \
  -device virtio-keyboard-device \
  -device virtio-tablet-device \
  -device usb-ehci \
  -device usb-kbd \
  -device usb-tablet \
  -net none \
  -drive file=build/disk.img,format=raw,id=bootdisk,if=none \
  -device virtio-blk-pci,drive=bootdisk,bootindex=0 \
  -drive file=build/redsea.img,format=raw,id=redsea,if=none \
  -device virtio-blk-device,drive=redsea \
  -display gtk \
  -serial stdio
```

### Web console (browser harness)

[`harness/`](harness/README.md) is a Next.js app that drives the guest in a browser — live framebuffer streaming,
keyboard/pointer input, a UART console, and VM start/stop — over the QEMU VNC + UART sockets that
`scripts/run-viewer-vm.sh` creates.

```bash
cd harness
bun install
bun run dev        # http://localhost:3000/neo-os
```

---

## Shell Commands Reference

### 3D Graphics & HolyGL

| Command | Description |
|---------|-------------|
| `holygl` | Run sovereign pure HolyC 3D matrix stack & rotating cube benchmark (`apps/HolyGL.HC`) |
| `gears` | Launch 3D GLXGears involute gear demo (`apps/Gears3D.HC`) |
| `physics` | Launch 3D Newtonian multi-body rigid dynamics (`apps/Physics3D.HC`) |
| `explode` | Trigger dynamic explosion impulse on polyhedra |
| `impulse` | Apply dynamic directional collision impulse to bodies |
| `stopbench` | Stop active 3D viewport rendering |
| `bench3d` | Dual-viewport rotating 3D cube demo |

### JIT Compiler & Applications

| Command | Description |
|---------|-------------|
| `run <script>` | Compile and run a HolyC script from RedSea disk (e.g. `run HolyGL.HC`, `run Mesh.HC`) |
| `jittest` | Run HolyC JIT self-tests on live AArch64 machine code |
| `smp` | Launch the 4-core parallel dispatch benchmark (`apps/Smp.HC`) |
| `filer` | Open the interactive RedSea file manager (a CDoc tool in `apps/DolDoc.HC`) |
| `edit <file>` | Open the syntax-highlighted CDoc editor (`apps/Shell.HC`) |
| `save <file>` | Save edited text buffer back to RedSea disk |

### System & Memory

| Command | Description |
|---------|-------------|
| `top` / `tasks` | Live CPU, memory, and task monitor |
| `bench` | Full automated system benchmark suite |
| `ls` / `dir` | List files on RedSea filesystem |
| `zeroram <on\|off\|status>` | Switch between direct-VRAM zero-copy mode and dedicated backbuffer |
| `vsync <on\|off>` | Toggle VSYNC synchronization |
| `perf` | Toggle RivaTuner-style performance HUD overlay |
| `help` | Interactive DolDoc command catalog with clickable buttons |
| `clear` / `cls` | Clear DolDoc terminal surface |
| `reboot` | Reset system via UEFI ResetSystem |

---

## Architecture Deep-Dive

### Boot Sequence

```
UEFI Firmware
    └─► EFI_MAIN  (boot/main.c)
            ├─ GOP framebuffer + kernel heap (boot/runtime)
            ├─ C seed JIT (boot/seed) loads & compiles KernelInit.HC from the FAT ESP
            ├─ KernelInit.HC loads the other 33 .HC modules from RedSea and
            │     JIT-compiles each (peephole pass per module)
            ├─ HalPlatform.HC + SMP: bring up cores 1–3 via PSCI CPU_ON
            ├─ Sovereign handover: KHeap.HC + Symbols.HC own kmalloc/kfree/symbols_*
            ├─ Timer IRQ armed @ 1000 Hz; interrupts enabled
            └─ DolDocShellEventLoop()  ← the interactive document shell
```

### Memory Layout (flat SASOS, 64-bit)

```
0x0000_0000_0000_0000  ┌─────────────────────────┐
                       │  UEFI Runtime Services   │
0x0000_0000_4000_0000  ├─────────────────────────┤
                       │  Kernel Image (EFI load) │
                       ├─────────────────────────┤
                       │  Kernel Heap (kmalloc)   │
                       ├─────────────────────────┤
                       │  JIT Code Pages (RWX)    │
                       ├─────────────────────────┤
                       │  GOP VRAM Framebuffer    │  ← Zero-RAM writes here directly
                       └─────────────────────────┘
```

### JIT Compiler Pipeline

```
HolyC Source Text
    │
    ▼
Lexer (boot/seed/lexer.c)  —  and, once self-hosted, apps/Compiler.HC
    │  Tokens: numbers, identifiers, keywords, char literals
    ▼
Recursive Descent Parser + Code Generator (boot/seed/jit_arm64.c → apps/Compiler.HC)
    │
    │  parse_expr()       → ternary ?:
    │  parse_logical()    → && ||
    │  parse_equality()   → == !=
    │  parse_relational() → < <= > >=
    │  parse_bitwise()    → & | ^
    │  parse_shift()      → << >>
    │  parse_additive()   → + -
    │  parse_term()       → * / %
    │  parse_unary()      → ! ~ unary-
    │  parse_primary()    → literals, idents, calls, (expr)
    │
    │  parse_statement()  → if/else, while, do-while, for,
    │                       switch/case/default, break, continue,
    │                       return, var decls, fn defs, assignments
    ▼
AArch64 Machine Code Buffer (uint32_t[])
    │  Branch backpatching: placeholder → patch after codegen
    │  Loop context stack: loop_stack[16] tracks break/continue
    │  Switch context: jump-over dispatch table, CMP+B.EQ per case
    ▼
mprotect(RWX) + icache flush + function pointer call
    └─► Live execution on Cortex-A72
```

### Zero-RAM Rendering

```c
// Traditional double-buffer (3.14 MB extra RAM):
canvas.back_buffer  = kmalloc(width * height * 4);  // RAM allocation
canvas.front_buffer = gop->Mode->FrameBufferBase;    // VRAM
// ... render to back_buffer ...
memcpy(front_buffer, back_buffer, size);             // 3.14 MB copy per frame

// NeoOS Zero-RAM mode (default):
canvas.back_buffer  = canvas.front_buffer;            // SAME VRAM pointer
// ... render directly to VRAM ...
gfx_swap_buffers();  // short-circuits: front==back → immediate return
// Zero copies. Zero extra RAM. Zero blit latency.
```

### 3D Rendering Pipeline

```
Scene Graph (mesh vertices + indices)
    │
    ▼
Model → World → View → Clip space (4×4 matrix multiply)
    │
    ▼
Near-plane triangle clipping (homogeneous clip space)
    │  Prevents behind-camera wrap-around artifacts
    ▼
Perspective divide → NDC → Screen space
    │
    ▼
Back-face culling (cross product sign, CCW = front-facing)
    │
    ▼
16.16 fixed-point scanline rasterizer
    │  Top-left fill convention (CubeCoders Jet-style)
    │  Sub-pixel accurate edge functions
    ▼
Z-buffer test (16-bit depth per pixel)
    │
    ▼
GOP VRAM write (direct, Zero-RAM mode)
```

---

## Source Tree

```
neo-os/
├── apps/                   # 100% pure HolyC suite — 34 modules, JIT-compiled at boot
│   ├── KernelInit.HC       # boot orchestrator: loads every module from RedSea
│   ├── Compiler.HC         # self-hosting HolyC compiler (AArch64 JIT, peephole optimizer)
│   ├── HolyGL.HC           # OpenGL-style 3D state machine (matrix stacks, lighting)
│   ├── RasterTile.HC       # the ONE tiled NEON rasterizer (Z, textures, Blinn-Phong)
│   ├── Render.HC           # framebuffer, damage tracker, single present
│   ├── GfxDevice.HC        # the ONE GPU device (virtio-gpu)
│   ├── DolDoc.HC           # CDoc/CTree document engine (windows are documents)
│   ├── Shell.HC            # O(1) action-executor shell (FNV-1a registry)
│   ├── Math3D.HC Gears3D.HC Mesh.HC Physics3D.HC ShaderVM.HC ShaderEditor.HC
│   ├── Fonts.HC Theme.HC HalPlatform.HC KHeap.HC Symbols.HC
│   ├── Sched.HC Smp.HC Gic.HC Timer.HC Exceptions.HC
│   ├── VirtioBlk.HC VirtioInput.HC Keyboard.HC Mouse.HC RedSea.HC
│   ├── BenchCpu.HC BenchReport.HC HolyBenchmark.HC PerfOverlay.HC Profiler.HC
│   ├── SelfTest.HC         # in-guest regression battery + engine parity (the `selftest` gate)
│   └── cube.obj sphere.obj GUIDE.TXT README.TXT
├── boot/                   # the ONLY C (bootstrap; each piece retires to .HC)
│   ├── main.c              # UEFI entry point + boot sequence + seed bring-up
│   ├── seed/               # the C JIT seed (lexer.c, jit_arm64.c, table.c, tok.h, seed_fs.c)
│   ├── runtime/            # C runtime substrate (kheap.c, symbols.c) — retired at handover
│   └── uefi/               # UEFI protocol headers + linker script
├── kernel/                 # the remaining assembly
│   ├── arch/aarch64/       # vectors.S, smp_entry.S, ffi_arm64.S
│   └── sched/switch.S      # context switch
├── gui/                    # font8x16.h (bitmap font)
├── docs/                   # canonical docs 00–04 (+ research/, images/, _superseded-old-docs/)
├── harness/                # browser console (Next.js): framebuffer stream, VNC input, UART, VM control
├── scripts/                # build + verification harness (golden-boot.sh, run-viewer-vm.sh, neo_uart.py, …)
├── tests/                  # census-baseline.txt + jit_golden/cases.json
├── screenshots/            # verified QEMU screendumps
├── AGENTS.md SKILL.md      # directives + §0 START HERE
├── Makefile  README.md  LICENSE
└── build/                  # (gitignored) BOOTAA64.EFI, disk.img, redsea.img
```

---

## JIT Self-Test Results (Live Hardware)

Running `jittest` on boot (verified on QEMU Cortex-A72 SMP):

```
[JIT SELF-TEST] Running 7 tests on live AArch64 hardware...

[1/7] Ternary operator:
      (10>5)?42:99  = 42  PASS
      (3>8)?42:99   = 99  PASS

[2/7] Do-while loop:
      counter reached 5   PASS

[3/7] While + break + continue:
      sum=18, ctr=7       PASS

[4/7] For + break + continue:
      f_sum=13            PASS

[5/7] Switch-case + break:
      case 2 → 200        PASS

[6/7] Switch fallthrough:
      10+20+30 = 60       PASS

[7/7] Switch default:
      input 77 → 888      PASS

[JIT SELF-TEST] 7/7 PASS ✓
```

---

## Engineering Roadmap & Status

> **This section is superseded by the canonical docs.** The authoritative, always-current status is
> `docs/00-MASTER-PLAN.md` §3 (the P0→P10 ladder) and `docs/02-TASKLIST.md` (per-phase tasks + P7 runbooks).
> Older "Phase 0–N" milestone names (incl. the since-dissolved `WM.HC`, `Compositor.HC`, `SmpDemo.HC`) are
> historical; `WM.HC`/`Compositor.HC` were deleted in P5 (DolDoc 3.0) and SMP is in `Smp.HC`.

**Current state (2026-10):** P0–P6 ✅ DONE; **P7.0 ✅ DONE + P7.0-audit ✅ DONE**; **next = P7.1** (HolyGL GL 1.3
surface completion — runbook in `docs/02-TASKLIST.md` §P7.1).

**Frozen gate:** `GOLDEN BOOT: PASS` · `SELFTEST 99/99` · `PARITY 68/68 (0 diff)` · `CENSUS 181` ·
`SELF-HOST: PASS` · `DETERMINISM: PASS (0xD28836F)` · `RENDER: PASS (0xD28836F)`.

The remaining P7→P10 ladder (clipper + NEON kernels, tile binning, GPU config plane, PMU telemetry, 40-phase
benchmark, GL conformance, GPU provider, run-anything/MCU) is specified in `docs/00` §11 and `docs/02`.

---

## License

MIT License — see [LICENSE](LICENSE).

---

## Acknowledgments

- **Terry A. Davis** — TempleOS, HolyC, and the Ring 0 SASOS philosophy
- **CubeCoders / Jet** — Rasterizer fill convention reference
- **QEMU / EDK2** — AArch64 UEFI emulation platform
- **STB** — `stb_truetype.h` for TrueType font rasterization

---

<p align="center"><i>Built from scratch. Ring 0. Real hardware. No gambiarras.</i></p>
