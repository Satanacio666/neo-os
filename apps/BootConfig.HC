// ==============================================================================
// apps/BootConfig.HC - BLOCO A (A1 + A3): CONFIGURACAO ATIVA DO KERNEL
// Architecture: ARMv8-A Ring 0 (EL1) | Single Address Space OS (SASOS)
//
// Handover de Plataforma em 3 camadas, UMA estrutura:
//   (1) HARDWARE DESCOBERTO  -> HalPlatform.HC (HAL v2: uart/storage/input/gop)
//   (2) PERFIL PERSISTIDO    -> profiles/<identidade>.conf (DADO na ESP, nao codigo)
//   (3) CONFIGURACAO ATIVA   -> CBootConfig (esta struct) <- o kernel le' daqui
//
// POR QUE UMA SO' ESTRUTURA (e nao dois parsers / duas structs):
// a config de video (CGpuConfig), a de kernel (heap/jit/cores) e a de plataforma
// (hal v2) descrevem o MESMO boot. Separa-las criaria dois donos para o mesmo
// conceito. A CBootConfig ABSORVE os parametros de GPU e ESPELHA nos campos de
// video que os testes existentes ja' cobrem (gpu_get_tile_size etc.).
//
// ZERO FALLBACK SILENCIOSO: chave desconhecida ou valor malformado num .conf
// incrementa g_bootcfg_parse_errors e imprime [BOOTCFG] WARN/ERR. Perfil ausente
// NAO e' erro (o arquivo e' opcional): defaults seguros + contador proprio.
//
// ZERO KMALLOC: tudo em BSS estatica (regra do CENSUS).
// ==============================================================================

#define BOOTCFG_MAX_KEYS     24
#define BOOTCFG_PROFILE_MAX  40

class CBootConfig {
  // --- identidade (DADO; vem da descoberta de firmware, nunca digitada) ---
  U8  profile_name[40];     // ex.: "QEMU_VIRT", "BOCHS_BXPC", "SM8250"
  I64 profile_loaded;       // 1 = um .conf foi lido e aplicado

  // --- kernel ---
  I64 heap_mb;
  I64 jit_pool_mb;
  I64 smp_cores;

  // --- plataforma (espelho do HAL v2, na config ATIVA) ---
  I64 uart_type;
  I64 storage_type;
  I64 input_type;
  I64 has_gop;

  // --- video (ESPELHO de CGpuConfig; A3) ---
  I64 fb_width;
  I64 fb_height;
  I64 tile_size;
  I64 buffer_mode;
  I64 pixfmt;

  // --- politicas do perfil ---
  I64 use_morton_order;
  I64 smp_affinity_policy;
  I64 throttle_delay_us;
  I64 errata_flags;

  // --- diagnostico ---
  I64 parse_errors;         // chave desconhecida / valor malformado
  I64 keys_applied;         // quantas chaves validas foram aplicadas
};

CBootConfig g_bootcfg;

// Buffer de leitura do .conf (estatico; CENSUS nao conta file-scope).
#define BOOTCFG_BUF_BYTES 2048
U8 g_bootcfg_buf[BOOTCFG_BUF_BYTES];

// -----------------------------------------------------------------------------
// Defaults seguros: os valores que garantem 0xD28836F no QEMU virt.
// -----------------------------------------------------------------------------
U0 BootConfigDefaults() {
  BootCfgCopy(g_bootcfg.profile_name, "DEFAULTS");
  g_bootcfg.profile_loaded = 0;
  g_bootcfg.heap_mb = 8;
  g_bootcfg.jit_pool_mb = 2;
  g_bootcfg.smp_cores = 4;
  g_bootcfg.uart_type = HAL_UART_PL011;
  g_bootcfg.storage_type = HAL_STORAGE_VIRTIO;
  g_bootcfg.input_type = HAL_INPUT_UART | HAL_INPUT_VIRTIO;
  g_bootcfg.has_gop = 1;
  g_bootcfg.fb_width = 1024;
  g_bootcfg.fb_height = 768;
  g_bootcfg.tile_size = 64;
  g_bootcfg.buffer_mode = GPU_BUF_DOUBLE;
  g_bootcfg.pixfmt = 0;
  g_bootcfg.use_morton_order = 0;
  g_bootcfg.smp_affinity_policy = 0;
  g_bootcfg.throttle_delay_us = 0;
  g_bootcfg.errata_flags = 0;
  g_bootcfg.parse_errors = 0;
  g_bootcfg.keys_applied = 0;
}

U0 BootCfgCopy(U8 *dst, U8 *src) {
  I64 i = 0;
  while (src[i] != 0 && i < (BOOTCFG_PROFILE_MAX - 1)) { dst[i] = src[i]; i = i + 1; }
  dst[i] = 0;
}

// -----------------------------------------------------------------------------
// HAL v2 -> config ativa. A camada (1) alimenta a (3). Chamada sempre, antes do
// parse do perfil: assim o perfil so' PRECISA descrever o que difere da verdade
// fisica ja' descoberta.
// -----------------------------------------------------------------------------
U0 BootConfigApplyHal() {
  g_bootcfg.uart_type    = (I64)g_hal_uart_type;
  g_bootcfg.storage_type = (I64)g_hal_storage_type;
  g_bootcfg.input_type   = (I64)g_hal_input_type;
  g_bootcfg.has_gop      = (I64)g_hal_has_gop;
}

// -----------------------------------------------------------------------------
// A3: a config de video da CBootConfig ESPELHA no CGpuConfig canonico. Os testes
// existentes (GPUCFG 21/21) continuam lendo gpu_get_tile_size() e passam a refletir
// a config ATIVA do boot — sem dois donos, sem segundo parser.
// -----------------------------------------------------------------------------
U0 BootConfigApplyGpu() {
  gpu_set_tile_size(g_bootcfg.tile_size);
  gpu_set_buffer_mode(g_bootcfg.buffer_mode);
  gpu_set_smp_cores(g_bootcfg.smp_cores);
}

// -----------------------------------------------------------------------------
// Parse "chave = valor" linha a linha. Ignora '#' e linhas em branco.
// NUNCA falha em silencio: chave desconhecida ou valor malformado conta erro.
// -----------------------------------------------------------------------------
U0 BootCfgApplyKey(U8 *k, I64 kval, I64 kvalid, I64 line) {
  if (kvalid == 0) {
    g_bootcfg.parse_errors = g_bootcfg.parse_errors + 1;
    doldoc_printf("$FG,RED$[BOOTCFG] ERR: valor malformado para '%s' na linha %lld$FG$\n", k, line);
    return;
  }
  if (strcmp(k, "heap_mb") == 0)            { g_bootcfg.heap_mb = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else if (strcmp(k, "jit_pool_mb") == 0)   { g_bootcfg.jit_pool_mb = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else if (strcmp(k, "smp_cores") == 0)     { g_bootcfg.smp_cores = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else if (strcmp(k, "smp_max_active_cores") == 0) { g_bootcfg.smp_cores = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else if (strcmp(k, "tile_size") == 0)     { g_bootcfg.tile_size = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else if (strcmp(k, "buffer_mode") == 0)   { g_bootcfg.buffer_mode = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else if (strcmp(k, "fb_width") == 0)      { g_bootcfg.fb_width = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else if (strcmp(k, "fb_height") == 0)     { g_bootcfg.fb_height = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else if (strcmp(k, "use_morton_order") == 0) { g_bootcfg.use_morton_order = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else if (strcmp(k, "smp_affinity_policy") == 0) { g_bootcfg.smp_affinity_policy = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else if (strcmp(k, "throttle_delay_us") == 0) { g_bootcfg.throttle_delay_us = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else if (strcmp(k, "errata_flags") == 0)  { g_bootcfg.errata_flags = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else if (strcmp(k, "uart_type") == 0)     { g_bootcfg.uart_type = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else if (strcmp(k, "storage_type") == 0)  { g_bootcfg.storage_type = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else if (strcmp(k, "input_type") == 0)    { g_bootcfg.input_type = kval; g_bootcfg.keys_applied = g_bootcfg.keys_applied + 1; }
  else {
    g_bootcfg.parse_errors = g_bootcfg.parse_errors + 1;
    doldoc_printf("$FG,RED$[BOOTCFG] ERR: chave desconhecida '%s' na linha %lld$FG$\n", k, line);
  }
}

// Aceita decimal e hexa (0x...). Devolve 1 se converteu algo.
I64 BootCfgParseInt(U8 *s, I64 *out) {
  I64 i = 0;
  while (s[i] == ' ' || s[i] == '\t') i = i + 1;
  I64 hex = 0;
  if (s[i] == '0' && (s[i+1] == 'x' || s[i+1] == 'X')) { hex = 1; i = i + 2; }
  I64 v = 0;
  I64 digits = 0;
  while (s[i] != 0) {
    U8 c = s[i];
    I64 d = -1;
    if (c >= '0' && c <= '9') d = c - '0';
    else if (hex && c >= 'a' && c <= 'f') d = 10 + (c - 'a');
    else if (hex && c >= 'A' && c <= 'F') d = 10 + (c - 'A');
    else if (c == ' ' || c == '\t') break;
    else if (c == '\r' || c == '\n') break;   // FIM DE LINHA (CRLF da ESP)
    else return 0;               // caractere invalido -> malformado
    v = v * (hex ? 16 : 10) + d;
    digits = digits + 1;
    i = i + 1;
  }
  if (digits == 0) return 0;
  *out = v;
  return 1;
}

// Parseia o buffer. Devolve o numero de chaves aplicadas.
I64 BootConfigParse(U8 *buf, I64 len) {
  I64 i = 0;
  I64 line = 1;
  I64 applied = 0;
  while (i < len) {
    // Pula espacos iniciais.
    while (i < len && (buf[i] == ' ' || buf[i] == '\t')) i = i + 1;
    // Linha vazia ou comentario? Salta ate' o fim da linha.
    if (i >= len || buf[i] == '#' || buf[i] == '\r' || buf[i] == '\n') {
      while (i < len && buf[i] != '\n') i = i + 1;
      if (i < len) { i = i + 1; line = line + 1; }
      continue;
    }
    // Le' a chave.
    U8 kbuf[40];
    I64 kl = 0;
    while (i < len && buf[i] != '=' && buf[i] != '\n' && buf[i] != '\r' && kl < 39) {
      kbuf[kl] = buf[i]; kl = kl + 1; i = i + 1;
    }
    kbuf[kl] = 0;
    // Apara espacos a' direita da chave.
    while (kl > 0 && (kbuf[kl-1] == ' ' || kbuf[kl-1] == '\t')) { kl = kl - 1; kbuf[kl] = 0; }
    if (i >= len || buf[i] != '=') {
      // Linha sem '=' — se tem conteudo, e' malformada.
      if (kl > 0) {
        g_bootcfg.parse_errors = g_bootcfg.parse_errors + 1;
        doldoc_printf("$FG,RED$[BOOTCFG] ERR: linha %lld sem '=' ('%s')$FG$\n", line, kbuf);
      }
      while (i < len && buf[i] != '\n') i = i + 1;
      if (i < len) { i = i + 1; line = line + 1; }
      continue;
    }
    i = i + 1;   // consome '='
    I64 kval = 0;
    I64 kvalid = BootCfgParseInt(&buf[i], &kval);
    // Salta ate' o fim da linha.
    while (i < len && buf[i] != '\n') i = i + 1;
    if (kval != 0 || kvalid != 0 || 0) { }   // (kval pode ser 0 legitimamente)
    BootCfgApplyKey(kbuf, kval, kvalid, line);
    if (kvalid != 0 && kl > 0) applied = applied + 1;
    if (i < len) { i = i + 1; line = line + 1; }
  }
  return applied;
}

// -----------------------------------------------------------------------------
// Carrega o perfil. A identidade vem da DESCOBERTA de firmware (ACPI: oem_id +
// oem_table_id), ja' saneada para [A-Za-z0-9_.-] por disco_set_identity(), o que
// coincide com o nome do arquivo na ESP. Sem identidade -> perfil opcional
// ausente (nao e' erro).
// -----------------------------------------------------------------------------
U0 BootConfigLoad() {
  BootConfigDefaults();
  BootConfigApplyHal();

  // Identidade (camada 2 -> 3): quem SOMOS, dito pelo firmware.
  {
    U8 *idn = (U8*)disco_identity();
    if (idn && idn[0] != 0) BootCfgCopy(g_bootcfg.profile_name, idn);
  }

  // Monta "profiles\<id>.conf".
  U8 path[72];
  I64 p = 0;
  U8 *pfx = "profiles\\";
  while (pfx[p] != 0) { path[p] = pfx[p]; p = p + 1; }
  I64 q = 0;
  while (g_bootcfg.profile_name[q] != 0 && p < 60) { path[p] = g_bootcfg.profile_name[q]; p = p + 1; q = q + 1; }
  U8 *suf = ".conf";
  I64 s = 0;
  while (suf[s] != 0 && p < 70) { path[p] = suf[s]; p = p + 1; s = s + 1; }
  path[p] = 0;

  I64 n = (I64)seed_read_file_at(path, g_bootcfg_buf, BOOTCFG_BUF_BYTES - 1);
  if (n <= 0) {
    // Perfil ausente e' NORMAL (o arquivo e' opcional). Nao e' erro de parse.
    g_bootcfg.profile_loaded = 0;
    BootConfigApplyGpu();
    doldoc_printf("[BOOTCFG] perfil '%s' ausente -> defaults seguros (heap=%lldMB, tile=%lld)\n",
                  g_bootcfg.profile_name, g_bootcfg.heap_mb, g_bootcfg.tile_size);
    return;
  }
  g_bootcfg_buf[n] = 0;
  BootConfigParse(g_bootcfg_buf, n);
  g_bootcfg.profile_loaded = 1;
  BootConfigApplyGpu();
  if (g_bootcfg.parse_errors == 0) {
    doldoc_printf("[BOOTCFG] perfil '%s' carregado (%lld chaves, 0 erros) | heap=%lldMB jit=%lldMB cores=%lld tile=%lld\n",
                  g_bootcfg.profile_name, g_bootcfg.keys_applied, g_bootcfg.heap_mb,
                  g_bootcfg.jit_pool_mb, g_bootcfg.smp_cores, g_bootcfg.tile_size);
  } else {
    doldoc_printf("$FG,RED$[BOOTCFG] perfil '%s' carregado com %lld ERRO(S) de parse ($FG,YELLOW$%lld chaves ok$FG,RED$)$FG$\n",
                  g_bootcfg.profile_name, g_bootcfg.parse_errors, g_bootcfg.keys_applied);
  }
}

// ---- acessores (fonte unica de verdade) ----
I64 BootCfgHeapMb()      { return g_bootcfg.heap_mb; }
I64 BootCfgJitPoolMb()   { return g_bootcfg.jit_pool_mb; }
I64 BootCfgSmpCores()    { return g_bootcfg.smp_cores; }
I64 BootCfgTileSize()    { return g_bootcfg.tile_size; }
I64 BootCfgFbWidth()     { return g_bootcfg.fb_width; }
I64 BootCfgFbHeight()    { return g_bootcfg.fb_height; }
I64 BootCfgUartType()    { return g_bootcfg.uart_type; }
I64 BootCfgStorageType() { return g_bootcfg.storage_type; }
I64 BootCfgInputType()   { return g_bootcfg.input_type; }
I64 BootCfgHasGop()      { return g_bootcfg.has_gop; }
I64 BootCfgParseErrors() { return g_bootcfg.parse_errors; }
I64 BootCfgKeysApplied() { return g_bootcfg.keys_applied; }
I64 BootCfgProfileLoaded() { return g_bootcfg.profile_loaded; }
U8 *BootCfgProfileName() { return g_bootcfg.profile_name; }

if (g_kernel_booting) {
  // BootConfigLoad() e' chamado por KernelInit.HC depois do HAL v2 (o perfil le'
  // a verdade fisica descoberta). Nao inicializar aqui: g_kernel_booting zera
  // antes da descoberta de firmware terminar.
}
