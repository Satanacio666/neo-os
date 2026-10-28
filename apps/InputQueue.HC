// ==============================================================================
// InputQueue.HC - BLOCO 2: DUTO UNICO DE ENTRADA (teclado + mouse)
// ------------------------------------------------------------------------------
// Antes deste modulo a entrada tinha DOIS caminhos independentes e paralelos:
//   * VirtioInput.HC -> KeyboardQueueChar()  (teclado) e MouseSetPos() (mouse)
//   * Keyboard.HC    -> KeyboardQueueChar()  (UART / console serial)
// Nenhum deles tinha um ponto unico onde o DolDoc pudesse ter o PRIMEIRO olhar
// (atalhos globais) antes de a tecla cair no Shell.
//
// Agora TODA entrada de hardware vira um CInputEvent nesta fila unica, e o unico
// consumidor e DolDocDispatchInput() (apps/DolDoc.HC): ele decide o que e atalho
// global do XFCE e o que desce para o Shell (buffer de teclado) ou para o cursor.
//
// ORCAMENTO DE SIMBOLOS (medido, nao suposto): o compilador HolyC tem tabelas de
// tamanho FIXO - HC_MAX_GLOBALS = 512 (apps/Compiler.HC:214). O baseline 7bda729
// ja usa 502 globais (impresso pelo proprio compilador). Este modulo declara
// APENAS 4 globais de proposito, para nao cruzar o limite e corromper a tabela
// (foi exatamente o que aconteceu na 1a versao, com 13 globais novos: crash
// NULL-deref no caminho de erro do compilador, ELR=0x7825C0F0).
//
// Ordem de carga: apps/KernelInit.HC, Stage 5, ANTES de Keyboard.HC.
// ==============================================================================

#define INPUT_Q_SIZE     64
#define INPUT_Q_MASK     63

// Tipos de evento do duto
#define INPUT_EV_KEY       1
#define INPUT_EV_MOUSE     2

// Modificadores (bitmask)
#define INPUT_MOD_SHIFT    1
#define INPUT_MOD_CTRL     2
#define INPUT_MOD_ALT      4

// Limite de workspaces alcancaveis por atalho global (Alt+1..4)
#define INPUT_ALT_WS_MAX   4

class CInputEvent {
  I64 type;        // INPUT_EV_KEY | INPUT_EV_MOUSE
  I64 modifiers;   // INPUT_MOD_SHIFT | CTRL | ALT
  I64 mouse_x;
  I64 mouse_y;
  I64 mouse_dx;
  I64 mouse_dy;
  I64 buttons;     // bit0 = esquerdo, bit1 = direito
  I64 key_code;    // codigo bruto (ASCII ou KEY_UP/KEY_DOWN/...)
  I64 key_char;    // caractere traduzido (0 quando a tecla e especial)
};

CInputEvent g_input_q[INPUT_Q_SIZE];
I64 g_input_q_head = 0;
I64 g_input_q_tail = 0;
I64 g_input_q_drops = 0;   // eventos descartados por fila cheia (nunca silencioso)

U0 InputQueueClear() {
  g_input_q_head = 0;
  g_input_q_tail = 0;
}

I64 InputQueueCount() {
  return (g_input_q_head - g_input_q_tail) & INPUT_Q_MASK;
}

// Empurra um evento. Devolve 0 em sucesso, -1 se a fila estiver cheia
// (o evento e DESCARTADO e contado em g_input_q_drops).
I64 InputQueuePush(CInputEvent *ev) {
  if (!ev) return -1;
  I64 next = (g_input_q_head + 1) & INPUT_Q_MASK;
  if (next == g_input_q_tail) {
    g_input_q_drops = g_input_q_drops + 1;
    return -1;
  }
  CInputEvent *dst = &g_input_q[g_input_q_head];
  dst->type      = ev->type;
  dst->modifiers = ev->modifiers;
  dst->mouse_x   = ev->mouse_x;
  dst->mouse_y   = ev->mouse_y;
  dst->mouse_dx  = ev->mouse_dx;
  dst->mouse_dy  = ev->mouse_dy;
  dst->buttons   = ev->buttons;
  dst->key_code  = ev->key_code;
  dst->key_char  = ev->key_char;
  g_input_q_head = next;
  return 0;
}

// Retira um evento. Devolve 0 em sucesso, -1 se a fila estiver vazia.
I64 InputQueuePop(CInputEvent *out) {
  if (!out) return -1;
  if (g_input_q_head == g_input_q_tail) return -1;
  CInputEvent *src = &g_input_q[g_input_q_tail];
  out->type      = src->type;
  out->modifiers = src->modifiers;
  out->mouse_x   = src->mouse_x;
  out->mouse_y   = src->mouse_y;
  out->mouse_dx  = src->mouse_dx;
  out->mouse_dy  = src->mouse_dy;
  out->buttons   = src->buttons;
  out->key_code  = src->key_code;
  out->key_char  = src->key_char;
  g_input_q_tail = (g_input_q_tail + 1) & INPUT_Q_MASK;
  return 0;
}

// ------------------------------------------------------------------------------
// Construtores - sao ESTES que os drivers usam. Nenhum driver fala com o Shell
// nem com o cursor diretamente.
// ------------------------------------------------------------------------------
I64 InputQueuePushKey(I64 key_code, I64 key_char, I64 modifiers) {
  CInputEvent ev;
  ev.type      = INPUT_EV_KEY;
  ev.modifiers = modifiers;
  ev.mouse_x   = 0;
  ev.mouse_y   = 0;
  ev.mouse_dx  = 0;
  ev.mouse_dy  = 0;
  ev.buttons   = 0;
  ev.key_code  = key_code;
  ev.key_char  = key_char;
  return InputQueuePush(&ev);
}

I64 InputQueuePushMouse(I64 x, I64 y, I64 dx, I64 dy, I64 buttons, I64 modifiers) {
  CInputEvent ev;
  ev.type      = INPUT_EV_MOUSE;
  ev.modifiers = modifiers;
  ev.mouse_x   = x;
  ev.mouse_y   = y;
  ev.mouse_dx  = dx;
  ev.mouse_dy  = dy;
  ev.buttons   = buttons;
  ev.key_code  = 0;
  ev.key_char  = 0;
  return InputQueuePush(&ev);
}

I64 InputQueueDrops() { return g_input_q_drops; }

if (g_kernel_booting) {
  InputQueueClear();
}
