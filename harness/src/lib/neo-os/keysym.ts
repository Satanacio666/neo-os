/**
 * DOM KeyboardEvent -> X11/RFB keysym mapping (client-safe).
 */

export const KEYSYMS: Record<string, number> = {
  Enter: 0xff0d,
  NumpadEnter: 0xff0d,
  Backspace: 0xff08,
  Tab: 0xff09,
  Escape: 0xff1b,
  Delete: 0xffff,
  ArrowLeft: 0xff51,
  ArrowUp: 0xff52,
  ArrowRight: 0xff53,
  ArrowDown: 0xff54,
  Home: 0xff50,
  End: 0xff57,
  PageUp: 0xff55,
  PageDown: 0xff56,
  Insert: 0xff63,
  Shift: 0xffe1,
  Control: 0xffe3,
  Alt: 0xffe9,
  Meta: 0xffe7,
  CapsLock: 0xffe5,
  ContextMenu: 0xff67,
  F1: 0xffbe,
  F2: 0xffbf,
  F3: 0xffc0,
  F4: 0xffc1,
  F5: 0xffc2,
  F6: 0xffc3,
  F7: 0xffc4,
  F8: 0xffc5,
  F9: 0xffc6,
  F10: 0xffc7,
  F11: 0xffc8,
  F12: 0xffc9,
};

/**
 * Convert a keyboard event to an X11 keysym, or 0 when the key is unmapped.
 * Printable characters map to their Unicode code point (Latin-1 is identity;
 * higher code points use the 0x01000000 Unicode keysym space).
 */
export function toKeysym(e: KeyboardEvent): number {
  const named = KEYSYMS[e.key];
  if (named !== undefined) return named;
  if (e.key.length === 1) {
    const code = e.key.codePointAt(0) ?? 0;
    if (code === 0) return 0;
    return code < 0x100 ? code : 0x01000000 | code;
  }
  return 0;
}
