# NeoOS — Dossier Técnico Completo

> Análise sistemática baseada em leitura integral de todos os 132 arquivos do projeto.
> Cobre: princípio arquitetural, realidade de cada subsistema, capacidades reais vs. declaradas,
> falhas e placeholders, e o futuro da integração Lua como extensão natural do JIT.

---

## Parte I — Princípio e Filosofia do Sistema

### O que NeoOS realmente é

NeoOS é um **UEFI application** que roda em EL1 (equivalente a Ring 0 em AArch64) como único processo no sistema. Não existe kernel separado de userspace — o binário `BOOTAA64.EFI` é carregado pelo firmware UEFI, toma controle do hardware e nunca devolve. Tudo que roda — drivers, shell, JIT compiler, apps — está no mesmo espaço de endereçamento, no mesmo nível de privilégio, compartilhando o mesmo heap e a mesma VRAM.

Isso é a essência do **TempleOS SASOS** (Single Address Space Operating System): sem syscalls, sem contexto de troca de privilégio, sem MMU separando processos. O JIT compila código HolyC diretamente em páginas RWX dentro do mesmo espaço — uma função JIT compilada pode chamar `kmalloc()` ou `gfx_put_pixel()` diretamente por ponteiro, sem nenhuma barreira.

### Sequência de boot real (boot/main.c)

```
UEFI Firmware → EFI_MAIN (main.c)
  1. FP/SIMD enable (cpacr_el1)
  2. Heap: AllocatePages(32MB) → kheap_init()
  3. Symbol table: symbols_init() + ~25 symbols registrados manualmente
  4. GOP framebuffer: SetMode(2) = 1024×768
  5. gfx_init() → aloca backbuffer RAM (ou não, em Zero-RAM)
  6. font_ttf_init(16pt)
  7. disable_interrupts()
  8. sched_init() → cria KernelMain task
  9. gic_init() + install_vector_table() + timer_init(100Hz)
 10. keyboard_init() + mouse_init()
 11. wm_init() + wm_create_window("NeoOS Shell")
 12. doldoc_init()
 13. virtio_blk_init() + redsea_init()
 14. jit_init() + shell_init()
 15. shell_run_command("jittest") → 7 self-tests
 16. shell_run_command("zeroram on") → back=front
 17. shell_run_command("bench3d") → abre janelas 3D
 18. task_create("TelemetryTask")
 19. smp_init() → PSCI CPU_ON cores 1–3
 20. enable_interrupts()
 21. Loop principal: shell_poll + mouse_poll + wm_handle_mouse + wm_draw_animating_windows + task_yield + wfi
```

**Observação crítica**: O SMP é inicializado **depois** de `bench3d` estar rodando. Os cores secundários começam a escrever VRAM via `smp_secondary_core_worker` enquanto o core 0 está no loop principal sem nenhuma sincronização. Esta é a janela onde o data race de VRAM acontece.

---

## Parte II — JIT Compiler: Realidade Completa

### O que está implementado de verdade

O JIT é um **compilador de descida recursiva single-pass** que emite instruções ARM64 de 32 bits diretamente em memória. Não há IR, não há passes de otimização, não há registro de alocação real. O pipeline é:

```
Source text → Lexer (tokens) → parse_statement() → emit_*() → uint32_t[] → mprotect(RWX) → BLR
```

**Lexer** (`lexer.c`): Completo para o subconjunto implementado. Reconhece: números inteiros/float, strings, identificadores, todos operadores aritméticos/lógicos/relacionais, keywords `if/else/while/for/do/switch/case/default/break/continue/return/I64/U0`, literais de char `'A'/'\n'`, chaves/colchetes/parênteses, ponto-e-vírgula, vírgula, seta `->`.

**Hierarquia de parsing**:
```
parse_expr()        → ternary cond ? a : b
parse_logical()     → && ||
parse_equality()    → == !=
parse_relational()  → < <= > >=
parse_bitwise()     → & | ^
parse_shift()       → << >>
parse_additive()    → + -
parse_term()        → * / %
parse_unary()       → ! ~ unary-minus
parse_primary()     → literals, identifiers, function calls, table literals, array indexing, (expr)
```

**Tipos de statement** (`parse_statement()`): `if/else`, `while`, `for`, `do-while`, `switch/case/default`, `break`, `continue`, `return`, declaração de variável `I64 x = expr`, definição de função `I64 f(...) { body }`, assignment `x = expr`, expression statement.

**Codegen ARM64 real**: Cada emit function produz uma instrução ARM64 válida de 32 bits:
- `emit_mov_imm64`: movz + movk chain para constante 64-bit
- `emit_add/sub/mul/sdiv/and/orr/eor/lsl/lsr/asr`: instruções reais
- `emit_cmp + emit_b_cond`: comparação + branch condicional com backpatch
- `emit_cbz/emit_cbnz`: compare-and-branch
- `emit_blr(cb, rn)`: BLR Xn — chamada indireta de função
- `emit_push_x/emit_pop_x`: STP/LDP para salvar/restaurar registradores na stack
- `emit_ldr_ptr/emit_str_ptr`: load/store 64-bit

**Sistema de chamada de função externa**: O mecanismo mais importante. Quando o JIT encontra `bench3d_start()`, faz:
1. `symbols_lookup_entry("bench3d_start")` — busca no hash table
2. Se encontrado: `emit_mov_imm64(cb, 16, sym->address)` → `emit_blr(cb, 16)`
3. Se `sym->address == NULL`: emite `LDR X16, [X16]` para dereference em runtime (late binding)

Isso é o coração do SASOS: **qualquer função C registrada no symbol table pode ser chamada diretamente do HolyC sem FFI, sem marshalling, sem overhead**. É zero-overhead porque ambos estão no mesmo espaço de endereçamento e usam a mesma AArch64 calling convention.

**Tabelas dinâmicas** (`table.c`): Hash map `table_t` com chaves string e valores `int64_t`. Suporta `{ key = val, key2 = val2 }` como literal. `table_create/set/get/has` estão registrados no symbol table. É a estrutura de dados dinâmica do HolyC 2.0 — equivalente ao que seriam structs simples em TempleOS.

### O que está incompleto / placeholder no JIT

**`class` keyword**: O lexer tokeniza `class` como `TOK_IDENT` — não há token especial. `parse_statement()` não tem nenhum branch para `class`. Quando o parser vê `class EditorState { I64 lines; }`, tenta interpretar `EditorState` como um identifier statement, falha silenciosamente ou avança tokens de forma incorreta. **Não implementado.**

**`auto` keyword**: Idêntico ao `class` — tokenizado como identificador, sem parsing especial. `auto conf = { ... }` — o parser vê `auto` como variável, tenta ler `conf` como próximo token, encontra `=`, tenta parsing de assignment sem ter declarado a variável. **Não implementado.**

**`U0` return type**: Tokenizado como identificador. Na definição de função, o parser espera `I64 fname(...)` — se vê `U0`, não reconhece o padrão. **Não implementado** (funções void não têm suporte).

**Ponteiros**: Não há tipo ponteiro. O lexer reconhece `*` apenas como multiplicação. `I64 *ptr = &x` não parseia corretamente — `*` seria multiplicação, `&` não existe como operador de address-of.

**Arrays**: `emit_ldr_ptr` existe e há parsing parcial de `ident[index]` em `parse_primary` (lê o base address do symbol table como inteiro e faz `LDR X0, [X1, X0, LSL #3]`), mas não há declaração `I64 arr[10]` — apenas indexação em ponteiros registrados como símbolos.

**Strings mutáveis**: Strings são imutáveis (alocadas em heap no momento da compilação, ponteiro em X0). Sem concatenação, sem `sprintf` nativo.

**Múltiplos tipos de retorno**: Funções sempre retornam `I64` em X0. Funções void que chamam `doldoc_print` dentro do JIT funcionam apenas porque `doldoc_print` é chamada como side-effect e X0 é ignorado pelo caller.

**Argumento stack incorreto para >1 argumento**: `parse_primary` para function calls: empilha todos os argumentos, depois desempilha em ordem inversa para X0–X7. Para `f(a, b, c)`: empilha a, b, c na stack → desempilha em X2=c, X1=b, X0=a. A ordem de avaliação e o mapeamento estão invertidos para funções com mais de 1 argumento — `f(1, 2)` chama `f(X0=2, X1=1)` em vez de `f(X0=1, X1=2)`.

**Funções registradas no symbol com `sym->address == NULL`**: Quando `symbols_lookup_entry` retorna um símbolo com `address == NULL` (símbolo registrado antecipadamente mas sem endereço), o JIT emite `LDR X16, [X16]` onde X16 = `&sym->address`. Isso dereference o ponteiro para o campo address da struct, não o ponteiro em si — `&sym->address` é o endereço de um campo dentro da struct heap, `LDR X16, [X16]` carrega os primeiros 8 bytes da struct (o campo `name`), não `address`. **Bug de late binding**.

**Overflow de `code_buffer_t` na stack**: `jit_compile_and_run` aloca `uint32_t code[8192]` na stack (32 KB). `jit_eval` aloca `uint32_t code[2048]` (8 KB). Funções definidas pelo usuário dentro do JIT usam `uint32_t fn_code[4096]` (16 KB) também na stack. Aninhamento de 3 níveis = 56 KB de stack só de buffers de código — a task tem 64 KB total. Overflow para qualquer programa HolyC não trivial.

---

## Parte III — Symbol Table: O Hub do SASOS

### Função central

`symbols.c` implementa um hash table DJB2 com 256 buckets. Cada `symbol_t` contém: `name[64]`, `address` (void*), `type` (FUNC/VAR/HW), `hash`, `next`.

No boot, `main.c` registra manualmente ~25 símbolos: `kmalloc`, `kfree`, `doldoc_print`, `jit_eval`, `bench3d_start`, `glxgears_start`, `math3d_sin`, `math3d_cos`, etc.

O JIT usa `symbols_lookup_entry()` em cada function call do HolyC. Qualquer função C que esteja registrada é **diretamente invocável a partir do HolyC sem nenhuma camada intermediária**. Este é o mecanismo que faz o SASOS funcionar: o `bench3d_start()` chamado de um `.HC` script é literalmente o mesmo `bench3d_start()` do kernel, no mesmo endereço, no mesmo stack frame context.

### Fraquezas do symbol table

- **Sem type safety**: `symbols_register("kmalloc", kmalloc, SYM_FUNC)` registra o endereço bruto. O JIT pode chamar `kmalloc(42, "hello")` — isso passa `X0=42, X1=ptr_to_string` para `kmalloc(size_t size)` — o segundo argumento é ignorado (AArch64 calling convention: extras em registradores são silenciosos). Chamada com argumento a menos: `bench3d_start()` que não recebe argumentos — correto. Mas `glxgears_start(r, g, b)` com 3 `I64` args: os floats esperados recebem os bits de um `int64_t` interpretados como `float` — valores completamente errados.

- **Sem garbage collection**: Símbolos registrados vivem para sempre no heap. Funções JIT definidas em scripts são registradas como `SYM_FUNC` com `sym->address = fn_cb.code`. Quando o script termina, `fn_cb.code` ainda existe (não é freed) e o símbolo continua válido. Segundo script pode chamar função do primeiro. Mas se a mesma função for redefinida, o endereço antigo fica órfão (memory leak de páginas JIT).

- **256 buckets para tudo**: Com ~25 símbolos do kernel + símbolos de cada subsistema + símbolos de scripts, o hash table é sparse. Mas colisões acontecem — DJB2 distribui bem, mas sem resize. Cenário com centenas de scripts rodados acumula símbolos sem limite.

---

## Parte IV — Rendering: Capacidades Reais

### Pipeline 3D real

```
mesh_t (vertices + indices)
  → mat4_mul(model × view × projection) → vec4_t clip coords
  → clip_triangle_near_plane() → clipagem homogênea
  → perspective divide (x/w, y/w, z/w) → NDC
  → viewport transform → screen coords (int)
  → back-face cull (cross product sign)
  → rasterize_triangle_fixed() → scanline fill 16.16
  → Z-test 16-bit per pixel
  → gfx_put_pixel() → canvas.back_buffer[y*pitch+x]
```

**O que funciona de verdade**: Cubo rotacionando com 12 triângulos, projeção perspectiva correta, back-face culling correto (após fix de winding), near-clip para triângulos que cruzam câmera, Z-buffer 16-bit conectado ao Viewport B, flat shading com cores diferentes por face.

**O que o `gfx_backend.c` realmente faz**: A função `gfx_backend_transform_vertices_neon()` existe mas é **C escalar puro** — loop `for (i=0; i<count; i++)` com multiplicações float. O nome "NEON" é aspiracional: nenhuma instrução NEON/SIMD é emitida pelo compilador sem `__attribute__((target("neon")))` explícito ou intrinsics. Com `-O2`, o GCC pode auto-vectorizar parcialmente, mas não é garantido. A função `gfx_backend_fast_clear()` é um loop 8x unrolled — pode ser auto-vectorizado mas também não usa intrinsics explícitos.

**`GFX_MODE_HW_ACCELERATED`**: `gfx_backend_set_mode(GFX_MODE_HW_ACCELERATED)` muda o nome para "VirtIO/Neon HW Accel" e seta `feature_flags = 0x0F`. **Não faz nada além disso**. O rendering continua sendo CPU software. Virtio GPU (protocolo `virtio-gpu`) não está implementado — nenhum comando virtio é enviado.

### DolDoc

`doldoc_print()` e `doldoc_printf()` renderizam texto com tags inline:
- `$FG,COLOR$` — muda cor de foreground
- `$BT,"label",LM="cmd"$` — botão clicável que executa comando no shell
- `$PB,VAL=n,MAX=m$` — progress bar
- `$LK,"label",A="cmd"$` — hyperlink

A implementação parseia estas tags em `wm.c/render.c` e renderiza usando `font_ttf_draw_char()`. Os botões `$BT$` são rastreados: quando `wm_handle_mouse()` detecta um clique na área do botão, chama `shell_run_command(cmd)` — fechando o loop GUI↔shell↔JIT.

**É a feature mais sofisticada e integrada do projeto.** Um script HolyC pode emitir `doldoc_print("$BT,\"Run\",LM=\"bench3d\"$")` e criar um botão interativo que inicia o benchmark — sem nenhuma API especial, apenas strings formatadas.

---

## Parte V — Subsistemas: Status Real

### Scheduler

**O que funciona**: `task_create()`, circular linked list, `task_yield()` (cooperative switch via `cpu_switch_context` em assembly), `task_exit()` com remoção da lista.

**O que não funciona**: `sched_tick()` é `(void)ticks; return;` — timer não dispara preemption. Com 4 cores, `current_task` é uma variável global única — sem per-core queue. Os cores 1–3 rodam `smp_secondary_core_worker()` em loop infinito **completamente fora do scheduler** — eles não são tasks, não aparecem em `sched_dump()`, não fazem `task_yield()`. O "scheduler" gerencia apenas tasks no core 0.

**TelemetryTask**: Única task real criada (`task_create("TelemetryTask", ...)`). Imprime no UART a cada 500 yields. Como yield é cooperative e o main loop chama `task_yield()` a cada iteração, a telemetry task roda entre frames. É a única prova de que o context switch funciona.

### GIC e Interrupções

`gic_init()` configura o GIC-3 (GICD + GICR). `timer_init(100)` programa o ARM Generic Timer para 100Hz. `install_vector_table()` instala o vetor de exceções.

O timer gera IRQs a 100Hz, que são recebidas pelo handler em `vectors.S`. O handler chama `sched_tick()` — que não faz nada. O timer existe e funciona como clock source para `timer_get_ticks()`, mas **não drive preemption**.

**GIC version mismatch**: O Makefile usa `-M virt` sem `gic-version=3`. QEMU `virt` padrão usa GIC-2. `gic.c` escreve nos registradores GICD_CTLR com o bit ARE_S (GIC-3 specific) — em GIC-2 esse bit não existe, a escrita é ignorada. O timer IRQ pode funcionar mesmo assim (GIC distributor é compatível em parte), mas IRQs de dispositivos externos podem não funcionar.

### Filesystem RedSea

**Funcional**: Format, list, mkdir, cd, write, read, delete. O `redsea_format()` cria README.TXT, fact.HC, calc.HC, Editor.HC, Filer.HC, Top.HC, Gears.HC, Bench3D.HC, BenchSuite.HC automaticamente. Subdiretorios System/, Apps/, Docs/ com GUIDE.TXT.

**`run <arquivo.HC>`** funciona: `shell.c` lê o arquivo via `redsea_read_file()`, passa o buffer para `jit_compile_and_run()`. **Mas o conteúdo dos `.HC` que o `redsea_format()` escreve no disco usa `class`, `auto`, `U0`** — não implementados no JIT. O `run Bench3D.HC` do disco vai tentar parsear `class BenchConfig { I64 c1; I64 c2; }` e falhar silenciosamente. As versões em `/home/carlos/.gemini/antigravity/scratch/neo-os/apps/` são mais simples (chamam apenas `bench3d_start()`) e funcionariam se fossem o que está no disco — mas o que está no **disco formatado** é a versão complexa com `class`.

**Sem reclaim**: contiguous allocation watermark-only. Delete marca entrada como livre mas não reclaim setores de dados.

### Mouse

**Situação completa**: `pointer_proto = NULL` permanente. `mouse_poll()` é body-less. O cursor aparece na posição inicial `(width/2, height/2)` = `(512, 384)` e nunca muda porque nenhum delta é lido. Os eventos de click em `wm_handle_mouse()` ainda funcionam para botões DolDoc e drag de janela via `mouse_set_pos()` — mas apenas se algo externo chamar `mouse_set_pos()`. No QEMU com `-device usb-tablet`, o UEFI expõe `EFI_ABSOLUTE_POINTER_PROTOCOL` que daria coordenadas absolutas — nunca tentado. **O sistema é operável apenas via teclado/shell.**

---

## Parte VI — Lua e HolyC: O que existe e o que pode existir

### O que existe agora

**Zero.** Não há uma linha de código Lua no projeto. Nem interpretador, nem binding, nem arquivo `.lua`. A palavra "lua" aparece 3 vezes no codebase: uma vez num comentário sobre `do-while` (coincidência de palavra), uma vez na stb_truetype (referência interna), uma vez no README (menção ao futuro).

### Por que faz sentido integrar — análise arquitetural

O SASOS tem uma propriedade única que torna Lua integração **natural e teoricamente superior** ao que qualquer runtime embedado convencional oferece:

**No SASOS, não existe barreira de memória entre Lua e o kernel.** Um `lua_State*` vive no mesmo heap que `kmalloc()`. Funções C do kernel registradas no `symbols` table têm ponteiros nus que Lua pode chamar via `lua_pushcfunction()`. O GC do Lua varre sua própria heap — que é subconjunto da heap do kernel — sem precisar de nenhuma camada de tradução.

A visão de integração perfeita seria:

```
HolyC JIT                          Lua 5.4 / LuaJIT
    ↓ symbols_lookup()                ↓ lua_getglobal()
    ↓ BLR X16                         ↓ lua_call()
    └──────────→ kernel C functions ←──────────┘
                (kmalloc, gfx_put_pixel, doldoc_print, ...)
```

**Mesmo symbol table, zero distinção.** Do ponto de vista do developer, `bench3d_start()` chamável de HolyC via `BLR` e chamável de Lua via `lua_call()` para o mesmo endereço físico — ambos dentro do mesmo EL1, mesmo address space.

### O que seria necessário para implementar corretamente

**1. Porta bare-metal de Lua 5.4 para AArch64 UEFI**

Lua 5.4 depende de: `malloc/free` (→ `kmalloc/kfree`), `memcpy/memset/strcmp` (→ já disponíveis via uefi.h), `setjmp/longjmp` (→ implementação manual ou usar `_setjmp` do crt), `printf/fputs` (→ `uart_puts`/`doldoc_print`). O arquivo `luaconf.h` permite substituir `LUAI_UACNUMBER`, `lua_getlocaledecpoint`, e todas as calls de I/O.

O maior obstáculo é `setjmp`/`longjmp` para error handling. Em bare-metal AArch64 pode ser implementado em ~20 linhas de assembly (salvar X19–X28, SP, LR em um buffer, restaurar com `br x30`).

Estimativa de código extra: ~500 linhas de `lua_baremetal_port.c` + substituição de `luaconf.h`.

**2. Registro bidirecional no symbol table**

```c
// Registrar todas as funções C do kernel como globals Lua
lua_State *L = luaL_newstate();
// Iterar o symbol table do NeoOS e expor cada SYM_FUNC como global Lua
symbols_iterate(function(sym, L) {
    lua_pushcfunction(L, make_lua_trampoline(sym->address));
    lua_setglobal(L, sym->name);
    return 0;
}, L);

// Registrar o Lua eval como símbolo HolyC
symbols_register("lua_eval", lua_eval, SYM_FUNC);
symbols_register("lua_call", lua_call_sym, SYM_FUNC);
```

O `make_lua_trampoline()` seria uma função que converte args Lua (inteiros/floats/userdata) para registradores X0–X7 e faz BLR para o endereço C — **um JIT de trampoline em tempo real**.

**3. Tipo unificado: `I64` ↔ `lua_Integer`**

Lua 5.4 usa `lua_Integer` = `long long` = `int64_t` por default. HolyC usa `I64` = `int64_t`. **São o mesmo tipo.** Para inteiros não há conversão — é a mesma representação em registradores. Para floats: HolyC float é IEEE-754 `double` nos bits de X0 — Lua float também é `double`. Zero conversão necessária para os tipos primitivos.

**4. A integração perfeita — sem distinção**

O ideal: o shell aceita tanto HolyC quanto Lua no mesmo REPL. O parser tenta HolyC primeiro (começa com `I64`, identificador, `if`, etc.); se falhar, tenta Lua. Ambos compartilham o symbol table. Uma função definida em HolyC é invocável de Lua e vice-versa.

```
NeoOS Shell> bench3d_start()          -- HolyC: chama via JIT + BLR
NeoOS Shell> lua bench3d_start()      -- Lua: chama via trampoline + BLR
NeoOS Shell> function f(x) return x*2 end  -- define em Lua
NeoOS Shell> I64 r = f(21)            -- HolyC chama função Lua via lua_call trampoline
```

O princípio JIT de zero overhead se mantém porque ambos os caminhos terminam no mesmo `BLR <endereço C>` no mesmo address space.

**5. GC coordination**

O único problema real: Lua GC pode coletar uma `table_t*` que o HolyC JIT ainda referencia como ponteiro nu em `I64 tbl = table_create()`. Solução: registrar `table_t*` como Lua userdata com `__gc` metamethod, e manter um ref count manual ou usar `lua_ref()` para ancorar objetos referenciados pelo JIT.

### Complexidade estimada

| Componente | LOC estimadas | Complexidade |
|-----------|--------------|-------------|
| Lua 5.4 bare-metal port | ~500 | Média |
| setjmp/longjmp AArch64 | ~30 | Baixa |
| Symbol table ↔ Lua bridge | ~200 | Baixa |
| Trampoline generator (C→Lua, Lua→C) | ~300 | Alta |
| REPL dual-language | ~100 | Baixa |
| GC coordination | ~150 | Alta |
| **Total** | **~1280** | **Média-Alta** |

É factível em 1-2 semanas de trabalho focado. O SASOS na verdade **facilita** a integração porque elimina toda a complexidade de FFI cross-process.

---

## Parte VII — Capacidades Reais do Sistema

### O que funciona sem reservas

| Capacidade | Status |
|-----------|--------|
| Boot UEFI AArch64 em ~10s | ✅ Real |
| GOP framebuffer 1024×768 32bpp | ✅ Real |
| Heap kmalloc/kfree com coalescing | ✅ Real (com bugs) |
| JIT HolyC: aritmética, comparações, lógica | ✅ Real |
| JIT: if/else, while, for, do-while | ✅ Real |
| JIT: switch/case/default com fallthrough | ✅ Real |
| JIT: break/continue com 16 níveis | ✅ Real |
| JIT: ternary operator | ✅ Real |
| JIT: chamada de função via symbol table | ✅ Real |
| JIT: tabelas dinâmicas `{ key=val }` | ✅ Real |
| JIT: 7 self-tests PASS em hardware | ✅ Real |
| Symbol table DJB2 hash | ✅ Real |
| DolDoc: texto colorido, botões, progress bars | ✅ Real |
| Window Manager: múltiplas janelas, drag | ✅ Real |
| Dirty-rect swapping | ✅ Real |
| 3D: cubo rotacionando com projeção perspectiva | ✅ Real |
| 3D: near-plane clipping | ✅ Real |
| 3D: scanline rasterizer 16.16 fixed-point | ✅ Real |
| 3D: Z-buffer 16-bit | ✅ Real (sem clear por frame) |
| 3D: back-face culling CCW | ✅ Real |
| Gears 3-engrenagens | ✅ Real |
| Zero-RAM mode (back==front) | ✅ Real (com tearing) |
| SMP 4 cores via PSCI | ✅ Real |
| Spinlock AArch64 | ✅ Real (com bug stxr→stlxr) |
| RedSea FS: format, list, read, write, mkdir, cd, rm | ✅ Real |
| RAMDisk 16MB /tmp | ✅ Real |
| run .HC scripts | ✅ Real (limitado ao subconjunto JIT) |
| Keyboard: UART + UEFI ConIn | ✅ Real |
| Physics bounce sim (bench3d) | ✅ Real |
| ARM Generic Timer 100Hz | ✅ Real |

### O que não funciona / placeholder / stub

| Capacidade | Status |
|-----------|--------|
| Mouse: leitura de hardware | ❌ stub vazio |
| Mouse: movimento do cursor | ❌ estático em (512,384) |
| Mouse: wiring 3D camera | ❌ não existe |
| HolyC `class` | ❌ não implementado |
| HolyC `auto` | ❌ não implementado |
| HolyC `U0` (void functions) | ❌ não implementado |
| HolyC ponteiros (`*`, `&`) | ❌ não implementado |
| UV texturing | ❌ não existe |
| Phong shading | ❌ não existe |
| Virtio GPU HW accel | ❌ stub (muda nome, não faz nada) |
| NEON SIMD explícito | ❌ apenas auto-vectorization possível |
| Preemption (timer→yield) | ❌ stub `(void)ticks` |
| SMP-aware scheduler | ❌ single global current_task |
| Lua integration | ❌ zero código |
| Network stack | ❌ zero código |
| mario64-recomp | ❌ zero código |
| VSync / frame pacing | ❌ não existe |
| Cursor save-under (anti-flicker) | ❌ não existe |
| Heap thread-safety | ❌ sem spinlock |
| icache flush pós-JIT | ❌ ausente |

---

## Parte VIII — Futuro Real do Sistema

### O que pode ser construído sobre esta base

A base está sólida para 3 direções:

**1. Completar o JIT HolyC (2-3 semanas)**
- Adicionar `class` como syntactic sugar sobre `table_t` (structs = tabelas com campos fixos)
- Ponteiros: adicionar `TOK_STAR` como type modifier, `&` como address-of, `*ptr` como dereference
- Corrigir os P0s: icache flush, argumento ordering, do-while continue, switch bounds
- `U0`: emitir sem prólogo de retorno, tratar chamada como void

**2. Integrar Lua 5.4 (1-2 semanas)**
- Port bare-metal + bridge bidirecional com symbol table
- Zero distinção HolyC/Lua no REPL e nos scripts
- Lua GC gerencia seus objetos, HolyC JIT gerencia os seus, shared objects via ref count

**3. Resolver SMP e rendering (1-2 semanas)**
- Spinlock em kmalloc/kfree
- Per-core task queues (um `current_task[4]` array indexed by MPIDR)
- Timer tick → task_yield() para preemption real
- Frame pacing com ARM Generic Timer (16.67ms budget)
- Cursor save-under (salvar 16×16 pixels antes de desenhar, restaurar antes do próximo frame)
- Clear Z-buffer no início de cada frame (um `memset` de 1024×768×2 bytes = 1.5MB por frame — gargalo, otimizar com NEON)

### A realidade do projeto hoje

NeoOS é um **proof-of-concept altamente funcional** de um SASOS AArch64. O JIT compila e executa código real em hardware real. A renderização 3D funciona. O DolDoc é interativo. O SMP traz 4 cores. O filesystem persiste dados.

Os gaps são **engenharia**, não pesquisa. Cada item da lista de bugs é corrigível com código, não exige rethinking da arquitetura. O SASOS como conceito está correto e funcionando — a integração Lua é uma extensão natural e tecnicamente elegante do que já existe.

O projeto está a **4-6 semanas de trabalho focado** de ser um sistema genuinamente utilizável para scripting, demonstrações 3D e experimentação OS-level em hardware ARM.
