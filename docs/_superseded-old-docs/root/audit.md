# NeoOS — Deep Technical Audit

> Full source read of all 132 files. Findings ordered by severity.

---

## 1. JIT Compiler (`compiler/`)

### 🔴 Critical

**No icache flush after emission** — `jit_compile_and_run()` does `mprotect(RWX)` but emits no `dc cvau / ic ivau / dsb ish / isb` sequence. On real Cortex-A72 the I-cache is not coherent with the D-cache. Code written via data stores may not be visible to instruction fetch → undefined execution, wrong results, or prefetch abort. This is the single most dangerous bug in the project.

**AArch64 ABI violation — callee-saved registers** — JIT prologues save X29/X30 but never save X19–X28. Any JIT function that triggers a callback into C code corrupts the C caller's X19–X28. Silent data corruption.

**Stack alignment at call sites** — AArch64 requires SP % 16 == 0 before every `BL`. The JIT does not enforce this for nested calls → alignment fault or silent corruption.

**`do-while` continue target is wrong** — `continue` in a `do-while` should jump to the *condition* (after body). The loop context records `loop_start` (top of body) as the continue target. `continue` re-executes the entire body → wrong C semantics.

**Switch dispatch — no bounds check** — if no case matches and no `default` exists, the dispatch loop falls off the end of the emitted table into garbage memory and executes it. No safe exit emitted.

**Ternary backpatch off-by-one** — the false-branch `B` placeholder is patched with `cb->count` *after* emitting the branch itself — the offset is 1 instruction short, jumping into the middle of the next expression.

**Buffer capacity — stack overflow risk** — `fn_cb` is a stack-allocated `code_buffer_t` of 4096 instructions (16 KB). No stack guard. Deeply nested JIT code overflows the 64 KB task stack silently.

**`class`, `auto`, `U0` not implemented** — all `.HC` app files use these constructs. The lexer tokenizes `class`/`auto` as identifiers; the parser silently skips or misparses them. `run Editor.HC`, `run Bench3D.HC` etc. produce wrong output or crash the parser.

### 🟡 Architectural

- **Single register (X0) for all expressions** — no register allocator. Multi-operand expressions that need two live intermediates silently reuse X0 → wrong results.
- **O(n) local variable lookup** — acceptable at 16 vars, but no hash table.
- **No type system** — no `U8/U16/U32`, no pointers, no arrays, no structs.
- **No line tracking in lexer** — parse errors give no location info.
- **Self-tests cover only happy paths** — `do-while continue` bug, switch-no-default, and nested ternary are all untested.

---

## 2. Rendering & 3D Engine (`gui/`, `kernel/math/`, `kernel/bench/`)

### 🔴 Critical

**Z-buffer never cleared between frames** — allocated once and initialized to `0xFFFF`. Never reset per frame. As the cube rotates, stale depth values from prior frames fail depth tests for pixels that should be visible → ghost faces, invisible geometry. Visually obvious bug.

**Zero-RAM mode + SMP = write tearing** — with `back_buffer == front_buffer`, four cores write VRAM concurrently with no locks, no barriers. GOP VRAM is mapped write-combining; stores from different cores are unordered → visible tearing artifacts at core-boundary scanlines.

**Near-clip W not interpolated** — `clip_triangle_near_plane()` interpolates X/Y/Z but not W. The clipped vertex gets a wrong W → wrong perspective divide → distorted triangles near camera.

**Perspective divide-by-zero** — no guard for `clip.w == 0` (vertex exactly on eye plane). FDIV produces ±Inf, triangle rasterizes across entire screen.

**Fixed-point overflow at screen edges** — edge function values as `int32_t` can overflow at large screen coordinates (Y-span > ~512 px on 1280-wide viewport) → wrong triangle coverage, missing geometry in lower screen half.

### 🟡 Architectural

- **No VSync / frame pacing** — render loop runs uncapped; visible tearing even without SMP in Zero-RAM mode.
- **16-bit Z-buffer** — 65536 depth levels across [0.1, 100.0] frustum; Z-fighting at distances > 10 units.
- **Flat shading only** — no Gouraud, no Phong (claimed in BenchSuite.HC).
- **No UV texturing** — claimed in BenchSuite phases, not implemented in rasterizer.
- **Gear meshing is visual only** — rotation ratios don't model actual tooth-pitch contact; gears interpenetrate instead of truly meshing.
- **WM window list not SMP-safe** — `wm_draw_animating_windows()` iterates `win_list` with no read lock while other cores may modify it.
- **Mouse input not wired to 3D camera** — Gears.HC README claims "drag to rotate camera"; mouse events are read but no 3D camera rotation is implemented.

---

## 3. Kernel, SMP & Memory

### 🔴 Critical

**Spinlock uses `stxr` not `stlxr`** (`smp_entry.S`) — the store-exclusive lacks release semantics. The critical section write is not ordered with respect to subsequent memory operations on other cores → ABA race on ARMv8 weakly-ordered memory model.

**SMP job dispatch missing `DMB SY`** (`smp.c` `smp_dispatch()`) — writes `.fn`, `.arg`, `.pending = 1` then `SEV` with no memory barrier. Secondary cores read `.pending` with a plain load; `.fn`/`.arg` stores may not be visible before `.pending` → worker calls a garbage function pointer.

**Heap not SMP-safe** — `kmalloc()`/`kfree()` walk a shared free list with no spinlock. Two cores calling `kmalloc()` simultaneously can receive the same block → double-allocation, heap corruption.

**Heap coalesce double-counts bytes** (`kheap.c kfree()`) — forward-coalesces with `next`, then backward-coalesces with `prev` using the already-enlarged `block->size`. Counts the absorbed `next` block twice → `stats.free_memory` corrupts, and the linked list may form a cycle.

**`kcalloc` integer overflow** — `size_t total = num * size` with no overflow check. `kcalloc(SIZE_MAX/2+1, 2)` wraps to 0 → `kmalloc(0)` → NULL returned to caller → deref.

**Task stack never freed** (`sched.c task_exit()`) — unlinks the task, calls `task_yield()`, but `task->stack_base` is never `kfree()`d. Each dead task leaks 64 KB permanently.

**PSCI entry — X19 used before SP set** (`smp_entry.S`) — `mov x19, x0` runs before the stack is established. X19 is callee-saved; PSCI spec says only X0 is defined at entry. Should use a scratch register until after `add sp, x1, x2`.

**Exception handler does not save SP or FP/NEON regs** (`exceptions.c`) — `trap_frame_t` captures X0–X30 + ELR + SPSR but not SP_EL1 or any NEON/FP registers. An exception mid-render corrupts FP state with no way to recover or diagnose.

### 🟡 Architectural

- **Scheduler is not SMP-aware** — `current_task` is a single global pointer shared by all 4 cores. Secondary cores run their own infinite loop *outside* the scheduler entirely. No per-core run queue, no affinity, no load balancing.
- **No preemption** — `sched_tick()` is a `(void)ticks` stub. The timer fires but never calls `task_yield()`. Any non-yielding task (bench3d render loop) starves everything else forever.
- **RedSea never reclaims sectors** — `redsea_delete_file()` zeroes the directory entry but the data sectors are permanently lost. Disk fills over time with no recovery path.
- **RedSea ignores `sector_count`** — `redsea_format(lba, sector_count)` does `(void)sector_count`. The total disk capacity is ignored.
- **RAMDisk overwrite leaks space** — overwriting an existing file appends new data at the watermark and orphans the old bytes. Used-bytes counter grows indefinitely.
- **Max 32 files per directory** — hard-coded; no expansion.

---

## 4. Build System

| Issue | Impact |
|-------|--------|
| No `run-headless` Makefile target | README documents it; `make run-headless` fails |
| `-device ramfb` with no ROM | Non-fatal warning every boot; redundant, remove it |
| `-M virt` defaults to GIC-2 | `gic.c` configures GIC-3 registers → IRQs never acked on default machine |
| `libuefi` not a dependency of `$(TARGET_SO)` | `make -j` can race link before `libuefi` is built |
| No `-Werror` | `-Wall` warnings silently accepted |
| 35 MB of `.ppm` files in git history | Not prunable without rewriting history; repo bloated |

---

## 5. Claimed vs. Reality

| Feature | Claimed | Reality |
|---------|---------|---------|
| HolyC `class` | Mentioned in apps + README | Not implemented in JIT |
| HolyC pointers / arrays / structs | Implied by SASOS | Not in parser or codegen |
| UV texturing | BenchSuite phase 3 | Not in rasterizer |
| Phong shading | BenchSuite phase 4 | Not implemented |
| Preemptive scheduler | README states it | Timer tick is a stub |
| Per-core SMP scheduler | Implied | Single global `current_task` |
| Mouse 3D camera | Gears.HC comment | Not wired up |
| Virtio GPU acceleration | Roadmap + `gfx_backend.c` | File is a stub, all rendering is software |
| Physics in benchmarks | BenchSuite phase 6 | `physics3d.c` exists but is not integrated into the bench |

---

## Priority Matrix

| # | Severity | Fix Effort | Issue |
|---|----------|-----------|-------|
| 1 | 🔴 P0 | Low | Add `dc cvau / ic ivau / dsb / isb` after JIT emit |
| 2 | 🔴 P0 | Low | Clear Z-buffer at start of each frame |
| 3 | 🔴 P0 | Low | Add `DMB SY` before `SEV` in `smp_dispatch()` |
| 4 | 🔴 P0 | Low | Change `stxr` → `stlxr` in spinlock |
| 5 | 🔴 P0 | Medium | Add spinlock around `kmalloc`/`kfree` |
| 6 | 🔴 P1 | Low | Fix `do-while` continue target to point at condition |
| 7 | 🔴 P1 | Low | Add `w == 0` guard before perspective divide |
| 8 | 🔴 P1 | Medium | Interpolate W in near-clip |
| 9 | 🔴 P1 | Low | Fix heap backward-coalesce double-count |
| 10 | 🔴 P1 | Low | Free task stack in `task_exit()` |
| 11 | 🟡 P2 | High | Per-core run queues (true SMP scheduler) |
| 12 | 🟡 P2 | Medium | Preemption: call `task_yield()` from timer tick |
| 13 | 🟡 P2 | High | Implement `class`, pointers, arrays in JIT |
| 14 | 🟡 P2 | Medium | VSync / frame cap (ARM generic timer) |
| 15 | 🟡 P2 | Medium | RedSea sector reclaim on delete |
| 16 | 🟡 P3 | Low | Fix Makefile: add `run-headless`, fix GIC version, remove `ramfb` |
| 17 | 🟡 P3 | Medium | UV interpolation + Phong shading in rasterizer |
| 18 | 🟡 P3 | Low | Save NEON/FP regs + SP in exception handler |

---

## 6. Mouse System — Completo Diagnóstico

### 🔴 Dead Input Pipeline
`mouse_poll()` está **completamente vazio** — é um stub com apenas um comentário. O `pointer_proto` (EFI_SIMPLE_POINTER_PROTOCOL) é declarado globalmente mas **nunca inicializado**: `mouse_init()` seta `pointer_proto = NULL` e não chama `BS->LocateProtocol()`. Resultado: o mouse nunca lê nenhum evento de hardware. A posição do cursor é **estática em (512, 384) para sempre** após o boot — nunca se move.

### 🔴 Cursor Causa Flickering Direto em Zero-RAM
Em Zero-RAM mode (`back == front`), `mouse_draw_cursor()` escreve 256 pixels diretamente no VRAM. O cursor é desenhado **sem salvar nem restaurar os pixels anteriores** (nenhum "save-under"). A cada frame:
1. Render 3D sobrescreve VRAM (inclui a área do cursor)
2. `mouse_draw_cursor()` desenha cursor por cima
3. Próximo frame: render sobrescreve os pixels do cursor com conteúdo 3D — cursor pisca/some

Sem double-buffer para esconder essa sequência, o artefato é visível a cada frame — **o cursor pisca junto com o framerate do render**.

### 🔴 `mouse_draw_cursor()` Chamado 10+ Vezes por Evento
`wm.c` chama `mouse_draw_cursor()` em cada branch do handler de eventos — 10 call sites diferentes — sem verificar se a posição mudou. Cada chamada produz uma escrita VRAM independente. Em Zero-RAM mode isso é diretamente visível como cursor "fantasma" em múltiplas posições ao clicar.

### 🟡 Sem EFI Absolute Pointer (Touch / Tablet)
Só tenta `EFI_SIMPLE_POINTER_PROTOCOL` (mouse relativo). QEMU virt expõe `EFI_ABSOLUTE_POINTER_PROTOCOL` via `-device usb-tablet` — sem ele, não há cursor absoluto posicionável. Com `pointer_proto = NULL` permanente, não há nem o relativo.

### 🟡 Sem Aceleração de Cursor
Mesmo que o polling fosse implementado, deltas de movimento do `EFI_SIMPLE_POINTER` são em microns — sem fator de aceleração, o cursor seria inutilizável (muito lento em movimentos suaves, muito rápido em movimentos bruscos).

### 🟡 Sem Wiring a 3D Camera
`wm_handle_mouse()` só processa cliques em janelas e taskbar. Nenhum evento de mouse é forwarded para `bench3d` ou `glxgears` para rotação de câmera — a claim do README ("drag to rotate") não existe no código.

---

## 7. Integração Lua / HolyC — Não Existe

### Situação Real
Não há **nenhuma integração Lua** no projeto. As únicas ocorrências de "lua" no codebase são:
- `jit_arm64.c` linha 1054: comentário `// Continue target in do..while is the condition evaluation` (sem relação com Lua)
- `stb_truetype.h`: referência interna à lib (não Lua)
- `README.md`: menção zerada

O projeto não inclui nenhum interpretador Lua, nenhuma FFI Lua↔HolyC, nenhum binding, nenhum arquivo `.lua`. Se havia planos de integração, **zero código foi escrito**.

### O que seria necessário para implementar
Uma integração real Lua ↔ HolyC no SASOS exigiria:
1. **Porta de LuaJIT ou Lua 5.4** compilada para AArch64 bare-metal sem libc — não trivial (Lua usa `setjmp`/`longjmp`, `malloc`, `printf` do sistema)
2. **Bridge de tipos**: HolyC `I64` ↔ Lua `number`, ponteiros SASOS ↔ `userdata`
3. **Chamada cruzada**: JIT HolyC chamando função Lua (necessita empilhar `lua_State*`), e vice-versa (Lua chamando símbolo registrado no `symbols.c`)
4. **GC coordination**: Lua GC não pode coletar objetos que o HolyC JIT ainda referencia via ponteiro nu

**Complexidade**: alta. Não está no estado atual do projeto.

---

## 8. Zero-RAM / VRAM Zerocopy — Flickering Profundo

### Por que flicker ocorre estruturalmente

Em double-buffer tradicional:
```
Frame N:   render → back_buffer → swap (memcpy) → front (VRAM) → display estável
Frame N+1: render → back_buffer (invisível) → swap → front
```
O display sempre vê um frame **completo** porque a apresentação é atômica (memcpy sobrescreve tudo de uma vez).

Em Zero-RAM mode (`back == front`):
```
Frame N:   render → VRAM diretamente → display vê pixels parciais DURANTE o render
```
O display (GOP/ramfb) escaneia a VRAM continuamente. Se o rasterizador levar 16ms para desenhar um frame, a tela exibe **metade do frame anterior + metade do novo** simultaneamente — isso é tearing estrutural, não opcional.

### Causas específicas identificadas no código

**1. Sem VSync / sem espera por beam** — `wm_draw_animating_windows()` em `wm.c:217` chama `custom_render` e `gfx_swap_rect` sem nenhuma sincronização com o escaneamento do display. `gfx_swap_rect` em Zero-RAM mode retorna imediatamente (`front == back` → early return), então o "swap" não existe — pixels escritos são imediatamente visíveis.

**2. `gfx_swap_buffers()` é no-op em Zero-RAM** — linha `render.c:349`: `if (front != back) { ...copy... }`. Em Zero-RAM `front == back`, então o bloco nunca executa. Isso é intencional (zero-copy), mas significa que não há janela de tempo controlada para apresentar o frame.

**3. Cursor sem save-under agrava tearing** — o render 3D escreve o frame, depois `mouse_draw_cursor()` escreve 256 pixels por cima. Se o display escanear entre esses dois eventos, aparece o cursor "flutuando" sobre o frame anterior.

**4. Múltiplos `gfx_swap_buffers()` por iteração do main loop** — `wm.c:510,520,530` chama `wm_draw_all(); mouse_draw_cursor(); gfx_swap_buffers()` em 3 branches separados do mesmo handler de click. Em modo normal (com backbuffer RAM) isso causa 3 memcpys completos de 3.14MB por click. Em Zero-RAM mode, causa 3 cursor draws sobre VRAM sem qualquer proteção.

**5. Sem ARM Generic Timer fence** — não há `WFI` com timeout nem `timer_wait_for_vsync()`. Sem GPIO/display-controller no QEMU `virt`, não há sinal VSync real disponível, mas o ARM Generic Timer poderia ser usado para frame-pacing (ex: acordar a cada 16.67ms e só então começar o próximo frame).

### Solução correta (sem gambiarra)
A abordagem certa para Zero-RAM com 0 tearing:
1. **Page-flip duplo no GOP** — alocar 2× VRAM e alternar `SetMode` ou `BltBuffer` para fazer o flip atômico. Não disponível em UEFI GOP simples.
2. **Sincronizar com timer** — usar ARM Generic Timer EL1 para cadenciar renders a 60Hz e minimizar o janela de escaneamento parcial.
3. **Aceitar Zero-RAM apenas para conteúdo estático** — usar RAM backbuffer para animações 3D e Zero-RAM só para regiões que não animam (desktop estático, menus).

A implementação atual sacrifica consistência visual por RAM savings — adequado para demonstração, inadequado para uso interativo.

