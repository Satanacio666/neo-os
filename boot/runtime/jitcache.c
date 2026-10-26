/*
 * jitcache.c — P8 Nível 1 — cache persistente do Compiler.HC na ESP.
 *
 * O QUE E CACHEADO E POR QUE NAO TUDO:
 * O Compiler.HC (157 KB de fonte) e compilado pelo seed C em ~14 s (medido na
 * POCO throttled) — mais da metade do tempo de compilacao do boot. Ele e
 * compilado FUNCAO POR FUNCAO, cada uma alocada incrementalmente no bump-allocator
 * do pool persistente, e cada uma registra seu simbolo na tabela global.
 *
 * O artefato cacheado e, portanto, TRES coisas:
 *   1. os bytes de codigo de maquina que o Compiler.HC ocupou no pool;
 *   2. os simbolos que apontam para dentro dessa regiao (nome + endereco);
 *   3. o codigo do top-level (compilado no scratch), que e o entrypoint.
 *
 * O ENTRYPOINT CONTINUA RODANDO. Isto e deliberado e e a diferenca entre um
 * cache correto e um boot quebrado: e o top-level do Compiler.HC que chama
 * HcInit() e inicializa o compilador auto-hospedado. Pular o entrypoint
 * economizaria mais alguns milissegundos e deixaria o sistema sem compilador.
 * A regra vale para qualquer nivel: cacheia-se COMPILACAO, nunca INICIALIZACAO.
 *
 * VALIDACAO POR ANCORA (fail-safe total):
 * O codigo emitido embute enderecos ABSOLUTOS (MOVZ/MOVK de 4 instrucoes) para
 * o heap, para funcoes do binario EFI e para o proprio pool. Se qualquer um
 * mudar, o codigo restaurado estaria errado e o boot quebraria de forma obscura.
 * Por isso o cabecalho guarda as ancoras e QUALQUER divergencia vira CACHE MISS
 * — recompila e regrava. O cache nunca e uma aposta.
 *
 * PREREQUISITO (commit 333b0b7): os tamanhos de heap e pool sao FIXOS. Antes
 * disto eles vinham da memoria livre, que varia entre boots, e as ancoras nunca
 * bateriam — o cache seria peso morto com aparencia de otimizacao.
 */

#include <uefi.h>
#include "seed_fs.h"
#include "symbols.h"

#define JC_MAGIC      0x54494A4Eu      /* 'NJIT' em little-endian */
#define JC_VERSION    1u
#define JC_NAME_MAX   48
#define JC_MAX_SYMS   4096
#define JC_MAX_CODE   (512u * 1024u)   /* teto do que se aceita restaurar */

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t version;
    uint64_t source_fnv1a;
    uint64_t anchor_printf;      /* detecta realocacao do BOOTAA64.EFI */
    uint64_t anchor_heap_base;   /* detecta mudanca do heap */
    uint64_t anchor_pool_base;   /* detecta mudanca do pool de codigo */
    uint32_t pool_off_start;     /* offset EXATO onde o codigo deve aterrissar */
    uint32_t code_size;          /* bytes de codigo de maquina */
    uint64_t entry_addr;         /* endereco do entrypoint (scratch) */
    uint32_t sym_count;
    uint32_t scratch_size;
    uint32_t payload_size;       /* simbolos + codigo + scratch */
    uint32_t reserved;
} jc_hdr_t;

typedef struct __attribute__((packed)) {
    uint64_t address;
    uint8_t  name[JC_NAME_MAX];
} jc_sym_t;

/* --- ancoras, preenchidas pelo boot -------------------------------------- */

static uint64_t s_anchor_heap = 0;
void jitcache_set_heap(uint64_t heap_base) { s_anchor_heap = heap_base; }

/* --- hash FNV-1a 64 ------------------------------------------------------ */

uint64_t jitcache_fnv1a(const void *data, size_t len) {
    const uint8_t *p = (const uint8_t*)data;
    uint64_t h = 0xCBF29CE484222325ULL;
    for (size_t i = 0; i < len; i++) {
        h ^= (uint64_t)p[i];
        h *= 0x100000001B3ULL;
    }
    return h;
}

/* --- estado da captura --------------------------------------------------- */

static uint64_t s_hash        = 0;
static uint32_t s_off_before  = 0;
static int      s_begin_done  = 0;

/* Captura dos simbolos: guardamos apenas os que apontam para dentro da regiao
 * recem-compilada — os demais vieram de main.c e nao pertencem a este cache. */
static jc_sym_t s_syms[JC_MAX_SYMS];
static uint32_t s_sym_count = 0;
static uint64_t s_range_lo = 0, s_range_hi = 0;

static void jc_sym_visitor(const char *name, void *address, int64_t type) {
    (void)type;
    if (!name || !address) return;
    uint64_t a = (uint64_t)(uintptr_t)address;
    if (a < s_range_lo || a >= s_range_hi) return;   /* fora da regiao: nao e nosso */
    if (s_sym_count >= JC_MAX_SYMS) return;
    jc_sym_t *s = &s_syms[s_sym_count];
    s->address = a;
    int i = 0;
    while (name[i] && i < JC_NAME_MAX - 1) { s->name[i] = (uint8_t)name[i]; i++; }
    s->name[i] = 0;
    s_sym_count++;
}

/* --- acesso ao pool e ao scratch (definidos em jit_arm64.c) -------------- */

extern uint8_t *jit_pool_base(void);
extern uint32_t jit_pool_used(void);
extern void     jit_pool_advance(uint32_t bytes);
extern uint8_t *jit_scratch_ptr(void);
extern uint32_t jit_scratch_capacity(void);
extern void     jit_flush(void *addr, uint32_t bytes);

static char s_name[64];

static void jc_path(char *dst, const char *name) {
    /* NEOJIT\<nome>.bin — fora de holyc\, junto dos dados de runtime. */
    int n = 0;
    const char *pre = "NEOJIT\\";
    for (int i = 0; pre[i] && n < 100; i++) dst[n++] = pre[i];
    for (int i = 0; name[i] && n < 110; i++) dst[n++] = name[i];
    const char *suf = ".bin";
    for (int i = 0; suf[i] && n < 120; i++) dst[n++] = suf[i];
    dst[n] = 0;
}

/* --------------------------------------------------------------------------
 * MISS: registra o estado inicial antes de compilar.
 * ------------------------------------------------------------------------ */

void jitcache_begin(const char *name, const char *source) {
    s_begin_done = 0;
    s_sym_count  = 0;
    s_off_before = jit_pool_used();
    s_hash       = jitcache_fnv1a(source, strlen(source));

    int i = 0;
    while (name[i] && i < 63) { s_name[i] = name[i]; i++; }
    s_name[i] = 0;
    s_begin_done = 1;
}

/* --------------------------------------------------------------------------
 * MISS: captura o resultado e grava na ESP.
 * ------------------------------------------------------------------------ */

int jitcache_end_and_store(void) {
    if (!s_begin_done) return -1;

    uint32_t off_after = jit_pool_used();
    if (off_after <= s_off_before) return -1;          /* nada foi emitido */

    uint32_t code_size = off_after - s_off_before;
    if (code_size > JC_MAX_CODE) return -1;            /* grande demais: nao cacheia */

    uint8_t *pool = jit_pool_base();
    if (!pool) return -1;

    /* Simbolos que apontam para dentro da regiao recem-emitida. */
    s_range_lo = (uint64_t)(uintptr_t)(pool + s_off_before);
    s_range_hi = (uint64_t)(uintptr_t)(pool + off_after);
    symbols_foreach(jc_sym_visitor);

    uint8_t *scratch = jit_scratch_ptr();
    uint32_t scratch_size = jit_scratch_capacity();

    uint32_t sym_bytes = s_sym_count * (uint32_t)sizeof(jc_sym_t);
    uint32_t payload   = sym_bytes + code_size + scratch_size;

    static jc_hdr_t hdr;
    hdr.magic           = JC_MAGIC;
    hdr.version         = JC_VERSION;
    hdr.source_fnv1a    = s_hash;
    hdr.anchor_printf   = (uint64_t)(uintptr_t)&printf;
    hdr.anchor_heap_base = s_anchor_heap;
    hdr.anchor_pool_base = (uint64_t)(uintptr_t)pool;
    hdr.pool_off_start  = s_off_before;
    hdr.code_size       = code_size;
    hdr.entry_addr      = (uint64_t)(uintptr_t)scratch;
    hdr.sym_count       = s_sym_count;
    hdr.scratch_size    = scratch_size;
    hdr.payload_size    = payload;
    hdr.reserved        = 0;

    /* Buffer de gravacao: cabecalho + simbolos + codigo + scratch.
     * Estatico de proposito — o caminho nao pode depender de heap. */
    static uint8_t buf[sizeof(jc_hdr_t) + JC_MAX_SYMS * sizeof(jc_sym_t) + JC_MAX_CODE + 64 * 1024];
    if (sizeof(jc_hdr_t) + payload > sizeof(buf)) return -1;

    uint8_t *w = buf;
    for (uint32_t i = 0; i < sizeof(jc_hdr_t); i++) w[i] = ((uint8_t*)&hdr)[i];
    w += sizeof(jc_hdr_t);

    for (uint32_t i = 0; i < sym_bytes; i++) w[i] = ((uint8_t*)s_syms)[i];
    w += sym_bytes;

    for (uint32_t i = 0; i < code_size; i++) w[i] = (pool + s_off_before)[i];
    w += code_size;

    for (uint32_t i = 0; i < scratch_size; i++) w[i] = ((uint8_t*)scratch)[i];

    char path[128];
    jc_path(path, s_name);
    int64_t wrote = seed_write_file_at(path, buf, sizeof(jc_hdr_t) + payload);

    printf("[JIT-CACHE] %s MISS -> compilado (%u B de codigo, %u simbolos) e gravado (%lld B)\n",
           s_name, (unsigned)code_size, (unsigned)s_sym_count, (long long)wrote);
    return 0;
}

/* --------------------------------------------------------------------------
 * HIT: valida as ancoras e restaura. Retorna 1 se restaurou.
 * ------------------------------------------------------------------------ */

int jitcache_try(const char *name, const char *source) {
    char path[128];
    jc_path(path, name);

    /* Le so o cabecalho primeiro — evita ler megabytes para descobrir que nao serve. */
    static jc_hdr_t hdr;
    int64_t got = seed_read_file_at(path, &hdr, sizeof(hdr));
    if (got < (int64_t)sizeof(hdr)) return 0;                 /* ausente */
    if (hdr.magic != JC_MAGIC || hdr.version != JC_VERSION) return 0;

    uint8_t *pool = jit_pool_base();
    if (!pool) return 0;

    /* As seis ancoras. Qualquer divergencia = MISS, sem excecao. */
    uint64_t hash = jitcache_fnv1a(source, strlen(source));
    if (hdr.source_fnv1a     != hash)                                      return 0;
    if (hdr.anchor_printf    != (uint64_t)(uintptr_t)&printf)              return 0;
    if (hdr.anchor_heap_base != s_anchor_heap)                             return 0;
    if (hdr.anchor_pool_base != (uint64_t)(uintptr_t)pool)                 return 0;
    if (hdr.pool_off_start   != jit_pool_used())                           return 0;
    if (hdr.code_size == 0 || hdr.code_size > JC_MAX_CODE)                 return 0;
    if (hdr.sym_count > JC_MAX_SYMS)                                       return 0;

    /* Le o payload inteiro e restaura. */
    static uint8_t buf[sizeof(jc_hdr_t) + JC_MAX_SYMS * sizeof(jc_sym_t) + JC_MAX_CODE + 64 * 1024];
    if (sizeof(jc_hdr_t) + hdr.payload_size > sizeof(buf)) return 0;
    got = seed_read_file_at(path, buf, sizeof(hdr) + hdr.payload_size);
    if (got < (int64_t)(sizeof(hdr) + hdr.payload_size)) return 0;

    uint8_t *r = buf + sizeof(jc_hdr_t);

    /* 1. Simbolos: restaura na MESMA tabela, pelos nomes. */
    jc_sym_t *sy = (jc_sym_t*)r;
    for (uint32_t i = 0; i < hdr.sym_count; i++) {
        symbols_register((const char*)sy[i].name, (void*)(uintptr_t)sy[i].address, SYM_FUNC);
    }
    r += hdr.sym_count * sizeof(jc_sym_t);

    /* 2. Codigo no pool, no offset exato. */
    uint8_t *dst = pool + hdr.pool_off_start;
    for (uint32_t i = 0; i < hdr.code_size; i++) dst[i] = r[i];
    r += hdr.code_size;

    /* 3. Scratch (o top-level, que e o entrypoint). */
    uint8_t *scratch = jit_scratch_ptr();
    for (uint32_t i = 0; i < hdr.scratch_size && i < jit_scratch_capacity(); i++)
        scratch[i] = r[i];

    /* 4. Consistencia de cache: D-cache limpo + I-cache invalidado. Sem isto a
     *    CPU executaria instrucoes velhas — invisivel no QEMU (sem cache), fatal
     *    em silicio real. */
    /* 5. AVANCA O BUMP-ALLOCATOR. Sem isto a proxima compilacao comeca em
     *    pool_off_start e SOBRESCREVE o codigo que acabamos de restaurar — o
     *    boot chega a compilar tudo e depois falha de forma obscura. */
    jit_pool_advance(hdr.code_size);

    jit_flush(dst, hdr.code_size);
    jit_flush(scratch, hdr.scratch_size);

    printf("[JIT-CACHE] %s HIT -> %u B de codigo e %u simbolos restaurados do pool @ +0x%X\n",
           name, (unsigned)hdr.code_size, (unsigned)hdr.sym_count,
           (unsigned)hdr.pool_off_start);
    return 1;
}
