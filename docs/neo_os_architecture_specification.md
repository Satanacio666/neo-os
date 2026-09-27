# NeoOS Architecture Specification: Livro Técnico do Kernel (ARM64 SASOS)

Este documento estabelece a especificação formal, exaustiva e de nível de engenharia para o **NeoOS** — um sistema operacional de espaço de endereçamento único (**SASOS - Single Address Space Operating System**) operando em **Ring 0 / EL1 (Exception Level 1)** sobre a arquitetura **ARMv8-A (AArch64)**.

---

## 1. Arquitetura de Hardware & Registradores da CPU

O NeoOS elimina a separação de privilégios de anéis de hardware (Ring 0 / Ring 3 ou EL1 / EL0). Todo o código do sistema operacional, drivers, compiladores e aplicações é executado em **EL1 (Kernel Mode)** com acesso irrestrito ao processador.

```text
+-------------------------------------------------------------------------+
|                  EXCEPTION LEVELS DA ARQUITETURA ARM64                  |
+-------------------------------------------------------------------------+
| EL3: Secure Monitor / Firmware                                          |
| EL2: Hypervisor (KVM / Virtualização)                                  |
| EL1: NeoOS Kernel, Drivers, Compiladores, Lua VM & Apps (SASOS RING 0)  |
| EL0: Não utilizado (Zero context switch penalty)                        |
+-------------------------------------------------------------------------+
```

### 1.1 Conjunto de Registradores de Uso Geral (64-bit)

O NeoOS utiliza a totalidade dos 31 registradores gerais de 64 bits do ARM64:

| Registrador | Nome Arquitetural | Convenção de Uso no NeoOS |
| :--- | :--- | :--- |
| `X0` - `X7` | Argumentos de Função | Passagem de parâmetros e valores de retorno (C ABI). |
| `X8` | Indirect Result / XR | Ponteiro para retorno de structs grandes. |
| `X9` - `X15` | Caller-Saved Temporaries | Registradores de rascunho rápido para computação imediata. |
| `X16`, `X17` | Intra-Procedure Call (IP0/1) | Usados por stubs de salto e resolução de símbolos dinâmicos. |
| `X18` | Platform Register | Reservado para ponteiro da Tarefa Ativa (`CurrentTask`). |
| `X19` - `X28` | Callee-Saved Registers | Preservados entre chamadas de função; base da troca de contexto. |
| `X29` | Frame Pointer (FP) | Encadeamento da pilha de chamadas (*Call Stack Unwinding*). |
| `X30` | Link Register (LR) | Endereço de retorno de sub-rotinas (`BL` / `RET`). |
| `SP_EL1` | Stack Pointer EL1 | Ponteiro da pilha de execução da tarefa corrente. |
| `XZR` | Zero Register | Registrador de leitura zero e descarte de escrita. |

### 1.2 Registradores Vetoriais NEON / SIMD (128-bit)

* **`V0` - `V31` (ou `Q0` - `Q31`):** 32 registradores vetoriais de 128 bits.
* Usados extensivamente pelo motor gráfico de software (DolDoc 2.0 e Compositor) para processar 4 pixels RGBA de 32 bits em uma única instrução de CPU (`LD1`, `ST1`, `FADD`, etc.).
* Habilitação no boot via registrador de controle de arquitetura:
  ```assembly
  mrs x0, cpacr_el1
  orr x0, x0, #(0x3 << 20)    // Habilita FP/NEON em EL1 e EL0 (bits 20 e 21)
  msr cpacr_el1, x0
  isb
  ```

### 1.3 Registradores de Controle do Sistema

* `SCTLR_EL1` (System Control Register): Habilitação da MMU, cache L1/L2 e alinhamento estrito.
* `TCR_EL1` (Translation Control Register): Configuração da profundidade das tabelas de páginas.
* `TTBR0_EL1` (Translation Table Base Register 0): Ponteiro físico para a tabela de páginas raiz (PML4).
* `MAIR_EL1` (Memory Attribute Indirection Register): Definição dos tipos de memória (RAM vs MMIO).
* `VBAR_EL1` (Vector Base Address Register): Ponteiro alinhado a 2048 bytes para os 16 vetores de interrupção.
* `DAIF`: Máscaras de interrupção da CPU (`D` = Watchpoints/Debug, `A` = SError, `I` = IRQ, `F` = FIQ).

---

## 2. O Modelo de Memória SASOS & Paginação Identitária 1:1

O NeoOS adota o paradigma **SASOS (Single Address Space)**. Não existem tabelas de páginas isoladas por processo. Todo o hardware e memória compartilham uma única tabela de tradução identitária:

$$\text{Endereço Virtual (VA)} = \text{Endereço Físico (PA)}$$

```text
[0x00000000_00000000 - 0x00000000_3FFFFFFF] : MMIO Periféricos (UART, GIC, GPU) -> Device-nGnRE
[0x00000000_40000000 - 0x00000007_FFFFFFFF] : RAM Física (Normal Memory Write-Back Cacheable)
```

### 2.1 Configuração do `MAIR_EL1` (Atributos de Memória)

Definimos dois índices de atributo:
* **Índice 0 (`Atributo 0` = `0x04`):** `Device-nGnRE` (Não-reordenável, sem reunião de escrita, não-cacheável). Usado estritamente para registradores de periféricos (UART, GIC, PCIe).
* **Índice 1 (`Atributo 1` = `0xFF`):** `Normal Memory, Inner Write-Back Cacheable, Outer Write-Back Cacheable`. Usado para toda a memória RAM.

```assembly
// Configura MAIR_EL1
ldr x0, =( (0x04 << 0) | (0xFF << 8) )
msr mair_el1, x0
```

### 2.2 Configuração do `TCR_EL1`

* Granularidade de página: **4 KB** (`TG0 = 0b00`).
* Tamanho do espaço de endereçamento: **48 bits** ($2^{48}$ bytes = 256 TB) com `T0SZ = 16` ($64 - 16 = 48$).
* Compartilhamento: Inner Shareable (`SH0 = 0b11`).
* Políticas de Cache: Inner/Outer Write-Back Read-Allocate Write-Allocate (`IRGN0 = 0b01`, `ORGN0 = 0b01`).

```assembly
ldr x0, =( (16 << 0) | (0b01 << 8) | (0b01 << 10) | (0b11 << 12) | (0b00 << 14) )
msr tcr_el1, x0
isb
```

### 2.3 Estrutura das Tabelas de Páginas de 4 Níveis

1. **Level 0 (PGD / PML4):** Mapeia blocos de 512 GB (512 entradas de 64 bits).
2. **Level 1 (PUD):** Mapeia blocos de 1 GB (512 entradas de 64 bits).
3. **Level 2 (PMD):** Mapeia blocos de 2 MB (512 entradas de 64 bits).
4. **Level 3 (PTE):** Mapeia páginas individuais de 4 KB (512 entradas de 64 bits).

### 2.4 Alocador Físico de Páginas (PMM - Physical Memory Manager)

O PMM consome o mapa de memória fornecido pelo UEFI (`BS->GetMemoryMap`) e cria um bitmap de bits onde $1 \text{ bit} = 1 \text{ página de } 4\text{ KB}$.

```c
typedef struct {
    uint64_t *bitmap;
    uint64_t total_pages;
    uint64_t free_pages;
    uint64_t last_scanned_index;
} pmm_state_t;

// Assinaturas do PMM:
void     pmm_init(efi_memory_descriptor_t *map, uintn_t map_size, uintn_t desc_size);
void*    pmm_alloc_page(void);
void*    pmm_alloc_pages(uint64_t count);
void     pmm_free_page(void *phys_addr);
void     pmm_free_pages(void *phys_addr, uint64_t count);
uint64_t pmm_get_free_ram_bytes(void);
```

### 2.5 Kernel Heap Allocator (`KHeap`: Slab + Buddy)

Para alocações dinâmicas de uso geral, o NeoOS implementa um alocador híbrido:
1. **Slab Allocator:** Para tamanhos fixos pequenos e frequentes (16B, 32B, 64B, 128B, 256B, 512B, 1KB, 2KB, 4KB). Evita fragmentação e opera em $O(1)$.
2. **Canários de Proteção:** Cada bloco alocado é precedido por um cabeçalho de 16 bytes contendo a tag de integridade `0xDEADBEEFCAFECAFE` e tamanho. Se um ponteiro corromper os limites do buffer, `kfree` detecta imediatamente o transbordo e identifica o módulo culpado.

```c
typedef struct heap_chunk {
    uint64_t canary;         // 0xDEADBEEFCAFECAFE
    uint32_t size;           // Tamanho real alocado
    uint32_t flags;          // 0x01 = Em uso, 0x02 = Slab
    struct heap_chunk *next; // Lista encadeada livre
    struct heap_chunk *prev;
} __attribute__((aligned(16))) heap_chunk_t;

// Assinaturas do Heap:
void* kmalloc(uint64_t size);
void  kfree(void *ptr);
void* kcalloc(uint64_t num, uint64_t size);
void* krealloc(void *ptr, uint64_t new_size);
void  kheap_dump_stats(void);
```

---

## 3. Arquitetura de Exceções & Interrupções (`VBAR_EL1`)

O ARM64 exige uma tabela de 16 vetores alinhada a **2048 bytes** ($2^{11}$ bytes), com cada manipulador ocupando exatamente **128 bytes** (32 instruções de 4 bytes).

```text
VBAR_EL1 Base + 0x000: Current EL with SP0 (Synchronous)
VBAR_EL1 Base + 0x080: Current EL with SP0 (IRQ)
VBAR_EL1 Base + 0x100: Current EL with SP0 (FIQ)
VBAR_EL1 Base + 0x180: Current EL with SP0 (SError)

VBAR_EL1 Base + 0x200: Current EL with SPx (Synchronous)  <-- Trap handler ativo
VBAR_EL1 Base + 0x280: Current EL with SPx (IRQ)          <-- Preemptive Timer / I/O
VBAR_EL1 Base + 0x300: Current EL with SPx (FIQ)          <-- High priority
VBAR_EL1 Base + 0x380: Current EL with SPx (SError)       <-- Hardware Bus Abort

VBAR_EL1 Base + 0x400: Lower EL using AArch64 (4 entradas)
VBAR_EL1 Base + 0x600: Lower EL using AArch32 (4 entradas)
```

### 3.1 O Frame de Exceção (`trap_frame_t`)

Ao disparar qualquer interrupção ou abort, o NeoOS empilha instantaneamente o contexto da CPU:

```assembly
.macro SAVE_CONTEXT
    sub sp, sp, #272
    stp x0, x1, [sp, #16 * 0]
    stp x2, x3, [sp, #16 * 1]
    stp x4, x5, [sp, #16 * 2]
    stp x6, x7, [sp, #16 * 3]
    stp x8, x9, [sp, #16 * 4]
    stp x10, x11, [sp, #16 * 5]
    stp x12, x13, [sp, #16 * 6]
    stp x14, x15, [sp, #16 * 7]
    stp x16, x17, [sp, #16 * 8]
    stp x18, x19, [sp, #16 * 9]
    stp x20, x21, [sp, #16 * 10]
    stp x22, x23, [sp, #16 * 11]
    stp x24, x25, [sp, #16 * 12]
    stp x26, x27, [sp, #16 * 13]
    stp x28, x29, [sp, #16 * 14]
    
    mrs x21, elr_el1
    mrs x22, spsr_el1
    stp x30, x21, [sp, #16 * 15] // Salva LR e ELR
    str x22,      [sp, #16 * 16] // Salva SPSR
.endm
```

### 3.2 O Controlador de Interrupções GIC (GICv2 / GICv3)

O NeoOS programa o Generic Interrupt Controller mapeado em MMIO:
* **GIC Distributor (`GICD_BASE = 0x08000000`):**
  * `GICD_CTLR`: Habilita distribuição de interrupções para a CPU (`bit 0 = 1`).
  * `GICD_ISENABLERn`: Habilita linhas específicas de IRQ (como Timer IRQ #27 ou #30, UART IRQ #33).
  * `GICD_IPRIORITYRn`: Prioridade de interrupções (0x00 = máxima, 0xFF = mínima).
* **GIC CPU Interface (`GICC_BASE = 0x08010000`):**
  * `GICC_PMR`: Filtro de prioridade (`0xFF` para aceitar todas as prioridades).
  * `GICC_IAR` (Interrupt Acknowledge Register): Leitura obtém o ID da interrupção disparada.
  * `GICC_EOIR` (End Of Interrupt Register): Escrita sinaliza que a interrupção foi processada.

### 3.3 ARM Generic Timer (O Relógio Preemptivo)

O temporizador de alta resolução é programado para disparar a cada 1 milissegundo (1000 Hz):

```c
void timer_init(uint32_t frequency_hz) {
    uint64_t cntfrq;
    asm volatile("mrs %0, cntfrq_el0" : "=r"(cntfrq));
    
    uint64_t ticks_per_quantum = cntfrq / frequency_hz;
    
    // Escreve o valor de contagem regressiva
    asm volatile("msr cntv_tval_el0, %0" : : "r"(ticks_per_quantum));
    
    // Habilita o timer e desmascara interrupção (bit 0 = enable, bit 1 = unmask)
    asm volatile("msr cntv_ctl_el0, %0" : : "r"(1));
}
```

---

## 4. Multitarefa & Scheduler (Troca de Contexto em 20ns)

O modelo de multitarefa do NeoOS baseia-se na ausência de fronteiras entre processos. Como o espaço de memória é único (SASOS), **o registrador de tabela de páginas `TTBR0_EL1` nunca é trocado**.

### 4.1 Bloco de Controle de Tarefa (TCB - Task Control Block)

```c
typedef enum {
    TASK_STATE_READY = 0,
    TASK_STATE_RUNNING,
    TASK_STATE_SLEEPING,
    TASK_STATE_DEAD
} task_state_t;

typedef struct {
    uint64_t x19, x20, x21, x22, x23, x24, x25, x26, x27, x28;
    uint64_t x29; // Frame Pointer
    uint64_t x30; // Link Register (PC de retorno)
    uint64_t sp;  // Stack Pointer
    
    // Registradores NEON callee-saved (D8-D15)
    uint64_t d8, d9, d10, d11, d12, d13, d14, d15;
} cpu_context_t;

typedef struct task {
    uint64_t      id;
    char          name[32];
    task_state_t  state;
    uint32_t      priority;
    uint64_t      wake_tick;      // Timestamp para sleep
    uint8_t       *stack_base;
    uint64_t      stack_size;
    cpu_context_t context;        // Estado dos registradores salvos
    struct task   *next;
    struct task   *prev;
} task_t;
```

### 4.2 A Rotina de Troca de Contexto em Assembly Puro (`cpu_switch_context`)

A troca de contexto salva apenas os registradores não voláteis (callee-saved) da tarefa anterior e carrega os da próxima:

```assembly
.global cpu_switch_context
.type cpu_switch_context, %function

// void cpu_switch_context(cpu_context_t *prev, cpu_context_t *next);
// x0 = ponteiro para o contexto anterior
// x1 = ponteiro para o próximo contexto
cpu_switch_context:
    // Salva registradores gerais callee-saved da tarefa saindo
    stp x19, x20, [x0, #0]
    stp x21, x22, [x0, #16]
    stp x23, x24, [x0, #32]
    stp x25, x26, [x0, #48]
    stp x27, x28, [x0, #64]
    stp x29, x30, [x0, #80]
    mov x2, sp
    str x2,       [x0, #96]

    // Salva registradores NEON callee-saved (D8-D15)
    stp d8,  d9,  [x0, #104]
    stp d10, d11, [x0, #120]
    stp d12, d13, [x0, #136]
    stp d14, d15, [x0, #152]

    // Restaura registradores gerais da próxima tarefa
    ldp x19, x20, [x1, #0]
    ldp x21, x22, [x1, #16]
    ldp x23, x24, [x1, #32]
    ldp x25, x26, [x1, #48]
    ldp x27, x28, [x1, #64]
    ldp x29, x30, [x1, #80]
    ldr x2,       [x1, #96]
    mov sp, x2

    // Restaura registradores NEON
    ldp d8,  d9,  [x1, #104]
    ldp d10, d11, [x1, #120]
    ldp d12, d13, [x1, #136]
    ldp d14, d15, [x1, #152]

    ret // Pula diretamente para o x30 (endereço salvo) da próxima tarefa!
```

> **Tempo de Execução:** Menos de 30 instruções de máquina. Em um processador moderno rodando a 2 GHz, essa troca é realizada em **aproximadamente 15 a 20 nanossegundos**, uma ordem de grandeza mais rápida do que uma troca de processo convencional no Linux.

---

## 5. A Tabela Global de Símbolos Dinâmica (`k_symbols`)

Herdada diretamente da filosofia de Terry Davis, toda função ou variável exportada pelo kernel ou carregada por módulos fica indexada em uma Hash Table global residente na memória RAM:

```c
typedef enum {
    SYM_FUNCTION = 1,
    SYM_VARIABLE,
    SYM_HARDWARE_REG,
    SYM_LUA_EXPORT
} symbol_type_t;

typedef struct symbol {
    char          name[64];
    void          *address;
    symbol_type_t type;
    uint32_t      hash;
    struct symbol *next; // Tratamento de colisão por encadeamento
} symbol_t;

#define SYMBOL_BUCKETS 4096

typedef struct {
    symbol_t *buckets[SYMBOL_BUCKETS];
    uint64_t count;
} symbol_table_t;

// Assinaturas da Tabela de Símbolos:
void     k_symbol_init(void);
void     k_symbol_register(const char *name, void *address, symbol_type_t type);
void*    k_symbol_lookup(const char *name);
void     k_symbol_dump_all(void);
```

### 5.1 Invocação Dinâmica por String

Qualquer função do kernel pode ser executada em tempo real apenas com o seu nome:

```c
void CallKernelFunction(const char *fn_name) {
    void (*func_ptr)(void) = (void(*)(void))k_symbol_lookup(fn_name);
    if (func_ptr) {
        func_ptr(); // Invoca diretamente o código em execução
    }
}
```

---

## 6. O Canvas Unificado (DolDoc 2.0) & Pipeline Gráfico

O NeoOS não possui display servers nem abstrações X11/Wayland. A tela inteira é tratada como um **Canvas Unificado**:

```text
[Backbuffer em RAM Normal Cacheada (RGBA 32bpp)]
                     |
        (SIMD NEON Blit - 16 bytes/ciclo)
                     v
[GOP Linear Framebuffer (VRAM Física de Hardware)]
```

### 6.1 Estrutura de Superfície Gráfica (`surface_t`)

```c
typedef struct {
    uint32_t *buffer;
    uint32_t width;
    uint32_t height;
    uint32_t pitch; // Pixels por linha
} surface_t;
```

### 6.2 Alpha Blending Vetorial em Ponto Fixo (NEON)

A mistura de cores com canal alfa (transparência de janelas) calcula:

$$C_{\text{resultado}} = \frac{A \cdot C_{\text{src}} + (255 - A) \cdot C_{\text{dst}}}{255}$$

Implementação em C puro otimizada para ser compilada em vetor NEON:
```c
static inline uint32_t blend_pixel(uint32_t src, uint32_t dst) {
    uint32_t a = (src >> 24) & 0xFF;
    if (a == 255) return src;
    if (a == 0)   return dst;

    uint32_t inv_a = 255 - a;

    uint32_t r = ((src >> 16 & 0xFF) * a + (dst >> 16 & 0xFF) * inv_a) >> 8;
    uint32_t g = ((src >> 8  & 0xFF) * a + (dst >> 8  & 0xFF) * inv_a) >> 8;
    uint32_t b = ((src       & 0xFF) * a + (dst       & 0xFF) * inv_a) >> 8;

    return (0xFF000000) | (r << 16) | (g << 8) | b;
}
```

---

## 7. Runtime de Linguagem: Lua 5.4 em Ring 0 / EL1

O interpretador oficial de Lua 5.4 opera dentro do próprio kernel sem bibliotecas `libc` externas.

### 7.1 Alocador de Memória Bare-Metal (`lua_Alloc`)

```c
static void* l_kernel_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    (void)ud;
    (void)osize;
    if (nsize == 0) {
        if (ptr) kfree(ptr);
        return NULL;
    }
    return krealloc(ptr, nsize);
}

lua_State* lua_kernel_create_state(void) {
    return lua_newstate(l_kernel_alloc, NULL);
}
```

### 7.2 Ponte com a Tabela Global de Símbolos (FFI Dinâmico)

Os scripts Lua podem acessar funções do kernel através do módulo global `neo`:

```c
static int lua_neo_call_symbol(lua_State *L) {
    const char *sym_name = luaL_checkstring(L, 1);
    void *fn = k_symbol_lookup(sym_name);
    if (!fn) {
        return luaL_error(L, "Simbolo do kernel nao encontrado: %s", sym_name);
    }
    // Invoca função genérica do kernel
    typedef int64_t (*generic_fn)(int64_t, int64_t);
    int64_t arg1 = luaL_optinteger(L, 2, 0);
    int64_t arg2 = luaL_optinteger(L, 3, 0);
    int64_t res = ((generic_fn)fn)(arg1, arg2);
    lua_pushinteger(L, res);
    return 1;
}
```

---

## 8. Catálogo Completo de Arquivos & Módulos da Fundação

```text
/neo-os/
├── Makefile                          # Build script com cross-compilação e QEMU
├── /boot/
│   ├── main.c                        # Ponto de entrada UEFI e salto para o Kernel
│   └── /uefi/                        # Runtime posix-uefi AArch64 (crt, link.ld, uefi.h)
├── /kernel/
│   ├── /arch/aarch64/
│   │   ├── mmu.h / mmu.c             # Tradução 1:1, TCR_EL1, MAIR_EL1
│   │   ├── vectors.S                 # Vetor de 16 exceções ARM64 (VBAR_EL1)
│   │   ├── gic.h / gic.c             # Driver do Controlador GICv2/v3
│   │   └── timer.h / timer.c         # Driver do ARM Generic Timer (1000 Hz)
│   ├── /mem/
│   │   ├── pmm.h / pmm.c             # Physical Memory Manager (Bitmap 4KB)
│   │   └── kheap.h / kheap.c         # Slab/Buddy Allocator (kmalloc/kfree)
│   ├── /sched/
│   │   ├── task.h                    # TCB e enumerações de estado
│   │   ├── switch.S                  # Rotina de troca de registradores em 20ns
│   │   └── sched.h / sched.c         # Scheduler preemptivo Round-Robin
│   ├── /symbols/
│   │   ├── symbols.h / symbols.c     # Tabela Hash Global de Símbolos
│   └── /lua/
│       ├── lua_kernel.h / lua_kernel.c # Adaptador do Lua 5.4 para EL1
├── /drivers/
│   ├── /serial/uart_pl011.c          # Console serial bare-metal
│   └── /video/gop_lfb.c              # Linear Framebuffer GOP
└── /gui/
    ├── render.h / render.c           # Motor gráfico 2D (Alpha blending, double buffer)
    └── font.h / font.c               # Tipografia TrueType / DolDoc 2.0 Canvas
```

---

Este livro técnico consolida o blueprint completo de todas as estruturas de dados, registradores, instruções e subsistemas do **NeoOS**. Toda a implementação subsequente seguirá estritamente estas definições.
