/*
 * profile.c — E5 — perfil como DADO na ESP.
 *
 * A SEPARACAO QUE ESTE MODULO FECHA:
 *
 *   DESCOBERTA (E1-E4)  fatos      — o que a maquina TEM. Sempre descobrivel.
 *   IDENTIDADE  (E5)    chave      — quem e a maquina, derivada da descoberta.
 *   PERFIL      (aqui)  politica   — como o NeoOS deve se comportar NELA.
 *
 * Politica NAO e descobrivel: nenhum firmware diz "ligue o tiling Morton de 64
 * neste GPU" nem "este lote de A72 precisa deste barrier". Isso e conhecimento.
 *
 * A INVARIANTE QUE PRESERVA A UNIVERSALIDADE:
 *   Perfil AUSENTE => defaults seguros => boota igual.
 *   Perfil PRESENTE => tuning ativo    => boota melhor.
 *   Nunca "boota ou nao".
 * Se a CORRECAO do boot depender do perfil, o sistema voltou a ser uma lista de
 * hardware suportado — so que disfarcada.
 *
 * POR QUE O PERFIL E DADO E NAO CODIGO: adicionar suporte a um aparelho passa a
 * ser SOLTAR UM ARQUIVO na ESP, sem recompilar o OS. E coerente com o que o
 * projeto ja faz: os 34 modulos .HC tambem sao dados lidos da ESP.
 *
 * Formato (texto simples, chave = valor, '#' comenta). Zero alocacao dinamica.
 */

#include <uefi.h>
#include "discovery.h"
#include "seed_fs.h"

typedef struct {
    uint32_t loaded;                /* 0 = defaults, 1 = veio da ESP */
    char     profile_name[64];
    /* Renderizacao */
    uint32_t tile_size;             /* default 32 (seguro) */
    uint32_t use_morton_order;      /* default 0 (linear) */
    /* CPU / SMP */
    uint32_t smp_max_active_cores;  /* 0 = o que a descoberta achou */
    uint32_t smp_affinity_policy;   /* default 0 (balanceado) */
    /* Silicio */
    uint32_t errata_flags;          /* default 0 */
    uint32_t throttle_delay_us;     /* default 0 */
    uint32_t dcache_line_bytes;     /* 0 = ler de CTR_EL0 */
} neo_profile_t;

neo_profile_t g_active_profile;

void profile_defaults(void) {
    g_active_profile.loaded              = 0;
    g_active_profile.profile_name[0]     = 0;
    g_active_profile.tile_size           = 32;
    g_active_profile.use_morton_order    = 0;
    g_active_profile.smp_max_active_cores = 0;
    g_active_profile.smp_affinity_policy = 0;
    g_active_profile.errata_flags        = 0;
    g_active_profile.throttle_delay_us   = 0;
    g_active_profile.dcache_line_bytes   = 0;
}

/* Acessores para o HolyC. */
uint32_t profile_loaded(void)      { return g_active_profile.loaded; }
uint32_t profile_tile_size(void)   { return g_active_profile.tile_size; }
uint32_t profile_morton(void)      { return g_active_profile.use_morton_order; }
uint32_t profile_smp_cores(void)   { return g_active_profile.smp_max_active_cores; }
uint32_t profile_errata(void)      { return g_active_profile.errata_flags; }
uint32_t profile_throttle_us(void) { return g_active_profile.throttle_delay_us; }
const char *profile_name(void)     { return g_active_profile.profile_name; }

/* --- helpers de parse (sem alocacao) ------------------------------------ */

static int key_is(const char *buf, int s, int e, const char *key) {
    int i = 0;
    for (; s < e && key[i]; i++, s++) if (buf[s] != key[i]) return 0;
    return s == e && key[i] == 0;
}

static uint32_t parse_u32(const char *buf, int s, int e) {
    uint32_t v = 0;
    while (s < e && (buf[s] == ' ' || buf[s] == '\t')) s++;
    while (s < e && buf[s] >= '0' && buf[s] <= '9') {
        v = v * 10u + (uint32_t)(buf[s] - '0');
        s++;
    }
    return v;
}

/* --- carga --------------------------------------------------------------- */

int profile_load(void) {
    profile_defaults();

    const char *id = disco_identity();
    if (!id || !id[0]) {
        printf("[PROFILE] Sem identidade (descoberta nao produziu nada) -> defaults seguros\n");
        return 0;
    }

    /* Caminho: profiles\<identidade>.conf */
    char path[128];
    int n = 0;
    const char *pre = "profiles\\";
    for (int i = 0; pre[i] && n < 100; i++) path[n++] = pre[i];
    for (int i = 0; id[i] && n < 118; i++) path[n++] = id[i];
    const char *suf = ".conf";
    for (int i = 0; suf[i] && n < 126; i++) path[n++] = suf[i];
    path[n] = 0;

    static char buf[2048];
    int64_t got = seed_read_file_at(path, buf, sizeof(buf) - 1);

    printf("[PROFILE] Identidade: %s\n", id);

    if (got <= 0) {
        printf("[PROFILE] Nenhum perfil em %s -> mantendo defaults seguros\n", path);
        return 0;
    }
    buf[got] = 0;

    int i = 0;
    while (i < (int)got) {
        int ls = i;
        while (i < (int)got && buf[i] != '\n' && buf[i] != '\r') i++;
        int le = i;
        while (i < (int)got && (buf[i] == '\n' || buf[i] == '\r')) i++;

        while (ls < le && (buf[ls] == ' ' || buf[ls] == '\t')) ls++;
        while (le > ls && (buf[le - 1] == ' ' || buf[le - 1] == '\t')) le--;
        if (ls >= le || buf[ls] == '#') continue;

        int eq = ls;
        while (eq < le && buf[eq] != '=') eq++;
        if (eq >= le) continue;

        int ke = eq;
        while (ke > ls && (buf[ke - 1] == ' ' || buf[ke - 1] == '\t')) ke--;
        int vs = eq + 1;

        if      (key_is(buf, ls, ke, "tile_size"))           g_active_profile.tile_size = parse_u32(buf, vs, le);
        else if (key_is(buf, ls, ke, "use_morton_order"))    g_active_profile.use_morton_order = parse_u32(buf, vs, le);
        else if (key_is(buf, ls, ke, "smp_max_active_cores"))g_active_profile.smp_max_active_cores = parse_u32(buf, vs, le);
        else if (key_is(buf, ls, ke, "smp_affinity_policy")) g_active_profile.smp_affinity_policy = parse_u32(buf, vs, le);
        else if (key_is(buf, ls, ke, "errata_flags"))        g_active_profile.errata_flags = parse_u32(buf, vs, le);
        else if (key_is(buf, ls, ke, "throttle_delay_us"))   g_active_profile.throttle_delay_us = parse_u32(buf, vs, le);
        else if (key_is(buf, ls, ke, "dcache_line_bytes"))   g_active_profile.dcache_line_bytes = parse_u32(buf, vs, le);
    }

    g_active_profile.loaded = 1;
    int k = 0;
    while (id[k] && k < 63) { g_active_profile.profile_name[k] = id[k]; k++; }
    g_active_profile.profile_name[k] = 0;

    printf("[PROFILE] Perfil carregado: %s\n", path);
    printf("[PROFILE] Tunings: tile_size=%u morton=%u smp_cores=%u errata=0x%X throttle_us=%u\n",
           (unsigned)g_active_profile.tile_size,
           (unsigned)g_active_profile.use_morton_order,
           (unsigned)g_active_profile.smp_max_active_cores,
           (unsigned)g_active_profile.errata_flags,
           (unsigned)g_active_profile.throttle_delay_us);
    return 1;
}
