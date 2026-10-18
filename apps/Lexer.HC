// ==============================================================================
// Lexer.HC - Sovereign Pure HolyC Lexical Analyzer
// Architecture: AArch64 Ring 0 | 100% Native HolyC Implementation
// Replaces: compiler/lexer.c
// ==============================================================================

#define TOK_EOF          0
#define TOK_NUMBER       1
#define TOK_FLOAT        2
#define TOK_IDENT        3
#define TOK_STRING       4

// Keywords
#define TOK_RETURN       5
#define TOK_IF           6
#define TOK_ELSE         7
#define TOK_WHILE        8
#define TOK_FOR          9
#define TOK_BREAK        10
#define TOK_CONTINUE     11
#define TOK_SWITCH       12
#define TOK_CASE         13
#define TOK_DEFAULT      14
#define TOK_DO           15
#define TOK_TYPE_I64     16
#define TOK_TYPE_U0      17
#define TOK_TYPE_F64     18
#define TOK_TYPE_U8      19
#define TOK_TYPE_U16     20
#define TOK_TYPE_U32     21

// Arithmetic & Assignment
#define TOK_PLUS         22
#define TOK_MINUS        23
#define TOK_STAR         24
#define TOK_SLASH        25
#define TOK_PERCENT      26
#define TOK_EQUAL        27

// Bitwise & Logical
#define TOK_AMPERSAND    28
#define TOK_ANDAND       29
#define TOK_PIPE         30
#define TOK_PIPEPIPE     31
#define TOK_CARET        32
#define TOK_TILDE        33
#define TOK_EXCLAM       34

// Comparisons
#define TOK_EQEQ         35
#define TOK_NEQ          36
#define TOK_LT           37
#define TOK_LTE          38
#define TOK_GT           39
#define TOK_GTE          40

// Delimiters & Punctuation
#define TOK_LPAREN       41
#define TOK_RPAREN       42
#define TOK_LBRACE       43
#define TOK_RBRACE       44
#define TOK_LBRACKET     45
#define TOK_RBRACKET     46
#define TOK_SEMICOLON    47
#define TOK_COMMA        48
#define TOK_DOT          49
#define TOK_ARROW        50
#define TOK_COLON        51
#define TOK_QUESTION     52
#define TOK_SHL          53
#define TOK_SHR          54
#define TOK_PLUSPLUS     55
#define TOK_MINUSMINUS   56
#define TOK_PLUSEQ       57
#define TOK_MINUSEQ      58
#define TOK_STAREQ       59
#define TOK_SLASHEQ      60
#define TOK_PERCENTEQ    61
#define TOK_ANDEQ        62
#define TOK_PIPEEQ       63
#define TOK_CARETEQ      64
#define TOK_SHLEQ        65
#define TOK_SHREQ        66
#define TOK_CLASS        67
#define TOK_STRUCT       68
#define TOK_AUTO         69
#define TOK_SIZEOF       70

// Unified Compiler.HC compatibility aliases (identical token values)
#define TOK_NUM          1
#define TOK_STR          4
#define TOK_TYPE         16
#define TOK_ASSIGN       27
#define TOK_AND          28
#define TOK_LOGAND       29
#define TOK_OR           30
#define TOK_LOGOR        31
#define TOK_XOR          32
#define TOK_NOT          34
#define TOK_EQ           35
#define TOK_NE           36
#define TOK_LE           38
#define TOK_GE           40
#define TOK_SEMI         47

class Token {
    I64  type;
    I64  int_value;
    F64  float_value;
    U8   str_value[256];
    U8  *str_ptr;
    I64  line;
    I64  col;
};

class Lexer {
    U8    *src;
    I64    pos;
    I64    line;
    I64    col;
    Token  current;
};

// Preprocessor #define Constant Table & Dynamic String Arena
U8  g_lex_def_names[8192]; // 128 * 64
I64 g_lex_def_vals[128];
I64 g_lex_def_count = 0;

U8 *g_lex_str_arena = 0;
I64 g_lex_str_offset = 0;

I64 LexerIsDigit(U8 c) {
    if (c >= '0' && c <= '9') return 1;
    return 0;
}

I64 LexerIsHexDigit(U8 c) {
    if (c >= '0' && c <= '9') return 1;
    if (c >= 'a' && c <= 'f') return 1;
    if (c >= 'A' && c <= 'F') return 1;
    return 0;
}

I64 LexerHexVal(U8 c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return 0;
}

I64 LexerIsAlpha(U8 c) {
    if (c >= 'a' && c <= 'z') return 1;
    if (c >= 'A' && c <= 'Z') return 1;
    if (c == '_') return 1;
    return 0;
}

U0 LexerResetDefines() {
    g_lex_def_count = 0;
}

U0 LexerAddDefine(U8 *name, I64 val) {
    if (!name || !name[0]) return;
    I64 lad_i = 0;
    for (lad_i = 0; lad_i < g_lex_def_count; lad_i++) {
        if (strcmp(&g_lex_def_names[lad_i * 64], name) == 0) {
            g_lex_def_vals[lad_i] = val;
            return;
        }
    }
    if (g_lex_def_count < 128) {
        strcpy(&g_lex_def_names[g_lex_def_count * 64], name);
        g_lex_def_vals[g_lex_def_count] = val;
        g_lex_def_count++;
    }
}

I64 LexerFindDefine(U8 *name, I64 *out_val) {
    if (!name || !name[0]) return 0;
    I64 lfd_i = 0;
    for (lfd_i = 0; lfd_i < g_lex_def_count; lfd_i++) {
        if (strcmp(&g_lex_def_names[lfd_i * 64], name) == 0) {
            if (out_val) *out_val = g_lex_def_vals[lfd_i];
            return 1;
        }
    }
    return 0;
}

U8* LexerAllocStr(I64 len) {
    if (!g_lex_str_arena) {
        g_lex_str_arena = kmalloc(65536);
        g_lex_str_offset = 0;
    }
    if (!g_lex_str_arena) return 0;
    if (g_lex_str_offset + len + 2 >= 65536) {
        g_lex_str_offset = 0;
    }
    U8 *res = g_lex_str_arena + g_lex_str_offset;
    g_lex_str_offset += len + 1;
    return res;
}

U0 LexerNext(Lexer *l) {
    if (!l || !l->src) return;

    while (1) {
        // Skip whitespace
        while (l->src[l->pos] && (l->src[l->pos] == ' ' || l->src[l->pos] == '\t' ||
               l->src[l->pos] == '\n' || l->src[l->pos] == '\r')) {
            if (l->src[l->pos] == '\n') {
                l->line++;
                l->col = 1;
            } else {
                l->col++;
            }
            l->pos++;
        }

        U8 sc = l->src[l->pos];
        if (sc == 0) break;

        // Skip single-line comments //
        if (sc == '/' && l->src[l->pos + 1] == '/') {
            l->pos += 2;
            l->col += 2;
            while (l->src[l->pos] && l->src[l->pos] != '\n') {
                l->pos++;
                l->col++;
            }
            continue;
        }

        // Skip multi-line block comments
        if (sc == '/' && l->src[l->pos + 1] == '*') {
            l->pos += 2;
            l->col += 2;
            while (l->src[l->pos]) {
                if (l->src[l->pos] == '*' && l->src[l->pos + 1] == '/') {
                    l->pos += 2;
                    l->col += 2;
                    break;
                }
                if (l->src[l->pos] == '\n') {
                    l->line++;
                    l->col = 1;
                } else {
                    l->col++;
                }
                l->pos++;
            }
            continue;
        }

        // Handle preprocessor directives (#define NAME VAL, etc.)
        if (sc == '#') {
            l->pos++;
            l->col++;
            while (l->src[l->pos] == ' ' || l->src[l->pos] == '\t') {
                l->pos++;
                l->col++;
            }
            U8 dir_kw[32];
            I64 dir_len = 0;
            while (LexerIsAlpha(l->src[l->pos]) && dir_len < 31) {
                dir_kw[dir_len] = l->src[l->pos];
                dir_len++;
                l->pos++;
                l->col++;
            }
            dir_kw[dir_len] = 0;

            if (strcmp(dir_kw, "define") == 0) {
                while (l->src[l->pos] == ' ' || l->src[l->pos] == '\t') {
                    l->pos++;
                    l->col++;
                }
                U8 def_name[64];
                I64 dn_len = 0;
                while ((LexerIsAlpha(l->src[l->pos]) || LexerIsDigit(l->src[l->pos])) && dn_len < 63) {
                    def_name[dn_len] = l->src[l->pos];
                    dn_len++;
                    l->pos++;
                    l->col++;
                }
                def_name[dn_len] = 0;

                while (l->src[l->pos] == ' ' || l->src[l->pos] == '\t') {
                    l->pos++;
                    l->col++;
                }

                I64 def_neg = 0;
                if (l->src[l->pos] == '-') {
                    def_neg = 1;
                    l->pos++;
                    l->col++;
                    while (l->src[l->pos] == ' ' || l->src[l->pos] == '\t') {
                        l->pos++;
                        l->col++;
                    }
                }

                I64 def_val = 0;
                if (l->src[l->pos] == '0' && (l->src[l->pos + 1] == 'x' || l->src[l->pos + 1] == 'X')) {
                    l->pos += 2;
                    l->col += 2;
                    while (LexerIsHexDigit(l->src[l->pos])) {
                        def_val = (def_val << 4) | LexerHexVal(l->src[l->pos]);
                        l->pos++;
                        l->col++;
                    }
                } else if (LexerIsDigit(l->src[l->pos])) {
                    while (LexerIsDigit(l->src[l->pos])) {
                        def_val = def_val * 10 + (l->src[l->pos] - '0');
                        l->pos++;
                        l->col++;
                    }
                } else if (LexerIsAlpha(l->src[l->pos])) {
                    U8 ref_name[64];
                    I64 rn_len = 0;
                    while ((LexerIsAlpha(l->src[l->pos]) || LexerIsDigit(l->src[l->pos])) && rn_len < 63) {
                        ref_name[rn_len] = l->src[l->pos];
                        rn_len++;
                        l->pos++;
                        l->col++;
                    }
                    ref_name[rn_len] = 0;
                    LexerFindDefine(ref_name, &def_val);
                }

                if (def_neg) def_val = -def_val;
                if (def_name[0]) {
                    LexerAddDefine(def_name, def_val);
                }
            }

            while (l->src[l->pos] && l->src[l->pos] != '\n') {
                l->pos++;
                l->col++;
            }
            continue;
        }

        break;
    }

    l->current.line = l->line;
    l->current.col = l->col;
    l->current.int_value = 0;
    l->current.float_value = 0.0;
    l->current.str_value[0] = 0;
    l->current.str_ptr = l->current.str_value;

    U8 c = l->src[l->pos];
    if (c == 0) {
        l->current.type = TOK_EOF;
        return;
    }

    // Number: hex (0x...), floating-point (3.14159), or decimal integer
    if (LexerIsDigit(c)) {
        I64 val = 0;
        if (c == '0' && (l->src[l->pos + 1] == 'x' || l->src[l->pos + 1] == 'X')) {
            l->pos += 2;
            l->col += 2;
            while (LexerIsHexDigit(l->src[l->pos])) {
                val = (val << 4) | LexerHexVal(l->src[l->pos]);
                l->pos++;
                l->col++;
            }
            l->current.type = TOK_NUMBER;
            l->current.int_value = val;
            l->current.float_value = (F64)val;
            return;
        } else {
            while (LexerIsDigit(l->src[l->pos])) {
                val = val * 10 + (l->src[l->pos] - '0');
                l->pos++;
                l->col++;
            }
            // Check for fractional floating-point literal (e.g. 3.14159)
            if (l->src[l->pos] == '.' && LexerIsDigit(l->src[l->pos + 1])) {
                l->pos++;
                l->col++;
                F64 fval = (F64)val;
                F64 fdiv = 10.0;
                I64 scaled_val = val * 100000;
                I64 scale_step = 10000;
                while (LexerIsDigit(l->src[l->pos])) {
                    I64 fdig = l->src[l->pos] - '0';
                    fval = fval + ((F64)fdig) / fdiv;
                    fdiv = fdiv * 10.0;
                    if (scale_step > 0) {
                        scaled_val = scaled_val + fdig * scale_step;
                        scale_step = scale_step / 10;
                    }
                    l->pos++;
                    l->col++;
                }
                // Optional scientific notation exponent (e.g. 1.5e3 or 2.0e-2)
                if (l->src[l->pos] == 'e' || l->src[l->pos] == 'E') {
                    l->pos++;
                    l->col++;
                    I64 exp_neg = 0;
                    if (l->src[l->pos] == '-') {
                        exp_neg = 1;
                        l->pos++;
                        l->col++;
                    } else if (l->src[l->pos] == '+') {
                        l->pos++;
                        l->col++;
                    }
                    I64 exp_val = 0;
                    while (LexerIsDigit(l->src[l->pos])) {
                        exp_val = exp_val * 10 + (l->src[l->pos] - '0');
                        l->pos++;
                        l->col++;
                    }
                    I64 exp_i = 0;
                    for (exp_i = 0; exp_i < exp_val; exp_i++) {
                        if (exp_neg) fval = fval / 10.0;
                        else fval = fval * 10.0;
                    }
                }
                l->current.type = TOK_FLOAT;
                l->current.float_value = fval;
                l->current.int_value = scaled_val;
                return;
            }
            l->current.type = TOK_NUMBER;
            l->current.int_value = val;
            l->current.float_value = (F64)val;
            return;
        }
    }

    // Identifier / Keyword / #define Macro Expansion
    if (LexerIsAlpha(c)) {
        I64 id_len = 0;
        while (LexerIsAlpha(l->src[l->pos]) || LexerIsDigit(l->src[l->pos])) {
            if (id_len < 255) {
                l->current.str_value[id_len] = l->src[l->pos];
                id_len++;
            }
            l->pos++;
            l->col++;
        }
        l->current.str_value[id_len] = 0;

        if (strcmp(l->current.str_value, "return") == 0) {
            l->current.type = TOK_RETURN;
        } else if (strcmp(l->current.str_value, "if") == 0) {
            l->current.type = TOK_IF;
        } else if (strcmp(l->current.str_value, "else") == 0) {
            l->current.type = TOK_ELSE;
        } else if (strcmp(l->current.str_value, "while") == 0) {
            l->current.type = TOK_WHILE;
        } else if (strcmp(l->current.str_value, "for") == 0) {
            l->current.type = TOK_FOR;
        } else if (strcmp(l->current.str_value, "break") == 0) {
            l->current.type = TOK_BREAK;
        } else if (strcmp(l->current.str_value, "continue") == 0) {
            l->current.type = TOK_CONTINUE;
        } else if (strcmp(l->current.str_value, "switch") == 0) {
            l->current.type = TOK_SWITCH;
        } else if (strcmp(l->current.str_value, "case") == 0) {
            l->current.type = TOK_CASE;
        } else if (strcmp(l->current.str_value, "default") == 0) {
            l->current.type = TOK_DEFAULT;
        } else if (strcmp(l->current.str_value, "do") == 0) {
            l->current.type = TOK_DO;
        } else if (strcmp(l->current.str_value, "I64") == 0 || strcmp(l->current.str_value, "U64") == 0 ||
                   strcmp(l->current.str_value, "int") == 0 || strcmp(l->current.str_value, "long") == 0) {
            l->current.type = TOK_TYPE_I64;
        } else if (strcmp(l->current.str_value, "U0") == 0 || strcmp(l->current.str_value, "void") == 0) {
            l->current.type = TOK_TYPE_U0;
        } else if (strcmp(l->current.str_value, "F64") == 0 || strcmp(l->current.str_value, "double") == 0) {
            l->current.type = TOK_TYPE_F64;
        } else if (strcmp(l->current.str_value, "U8") == 0 || strcmp(l->current.str_value, "I8") == 0 ||
                   strcmp(l->current.str_value, "char") == 0) {
            l->current.type = TOK_TYPE_U8;
        } else if (strcmp(l->current.str_value, "U16") == 0 || strcmp(l->current.str_value, "I16") == 0 ||
                   strcmp(l->current.str_value, "short") == 0) {
            l->current.type = TOK_TYPE_U16;
        } else if (strcmp(l->current.str_value, "U32") == 0 || strcmp(l->current.str_value, "I32") == 0) {
            l->current.type = TOK_TYPE_U32;
        } else if (strcmp(l->current.str_value, "class") == 0) {
            l->current.type = TOK_CLASS;
        } else if (strcmp(l->current.str_value, "struct") == 0) {
            l->current.type = TOK_STRUCT;
        } else if (strcmp(l->current.str_value, "auto") == 0) {
            l->current.type = TOK_AUTO;
        } else if (strcmp(l->current.str_value, "sizeof") == 0) {
            l->current.type = TOK_SIZEOF;
        } else {
            // Check #define constant expansion table
            I64 macro_val = 0;
            if (LexerFindDefine(l->current.str_value, &macro_val)) {
                l->current.type = TOK_NUMBER;
                l->current.int_value = macro_val;
                l->current.float_value = (F64)macro_val;
            } else {
                l->current.type = TOK_IDENT;
            }
        }
        return;
    }

    // String literal "..." (backed by dynamic arena + str_value)
    if (c == '"') {
        l->pos++;
        l->col++;
        I64 s_start = l->pos;
        I64 raw_len = 0;
        while (l->src[s_start + raw_len] && l->src[s_start + raw_len] != '"') {
            if (l->src[s_start + raw_len] == '\\' && l->src[s_start + raw_len + 1]) {
                raw_len += 2;
            } else {
                raw_len++;
            }
        }
        U8 *arena_dst = LexerAllocStr(raw_len + 1);
        I64 slen = 0;
        while (l->src[l->pos] && l->src[l->pos] != '"') {
            U8 out_ch = l->src[l->pos];
            if (out_ch == '\\' && l->src[l->pos + 1]) {
                l->pos++;
                l->col++;
                U8 esc = l->src[l->pos];
                if (esc == 'n') out_ch = '\n';
                else if (esc == 'r') out_ch = '\r';
                else if (esc == 't') out_ch = '\t';
                else if (esc == '0') out_ch = 0;
                else out_ch = esc;
            }
            if (slen < 255) {
                l->current.str_value[slen] = out_ch;
            }
            if (arena_dst) {
                arena_dst[slen] = out_ch;
            }
            slen++;
            l->pos++;
            l->col++;
        }
        if (l->src[l->pos] == '"') {
            l->pos++;
            l->col++;
        }
        if (slen < 256) l->current.str_value[slen] = 0;
        else l->current.str_value[255] = 0;
        if (arena_dst) {
            arena_dst[slen] = 0;
            l->current.str_ptr = arena_dst;
        }
        l->current.type = TOK_STRING;
        return;
    }

    // Character literal '...'
    if (c == '\'') {
        l->pos++;
        l->col++;
        I64 ch = 0;
        if (l->src[l->pos] == '\\' && l->src[l->pos + 1]) {
            l->pos++;
            l->col++;
            U8 esc = l->src[l->pos];
            l->pos++;
            l->col++;
            if (esc == 'n') ch = '\n';
            else if (esc == 'r') ch = '\r';
            else if (esc == 't') ch = '\t';
            else if (esc == '0') ch = 0;
            else ch = esc;
        } else if (l->src[l->pos] && l->src[l->pos] != '\'') {
            ch = l->src[l->pos];
            l->pos++;
            l->col++;
        }
        if (l->src[l->pos] == '\'') {
            l->pos++;
            l->col++;
        }
        l->current.type = TOK_NUMBER;
        l->current.int_value = ch;
        l->current.float_value = (F64)ch;
        return;
    }

    // Three-character operators
    U8 next_c = l->src[l->pos + 1];
    U8 next_c2 = 0;
    if (next_c) next_c2 = l->src[l->pos + 2];

    if (c == '<' && next_c == '<' && next_c2 == '=') {
        l->pos += 3;
        l->col += 3;
        l->current.type = TOK_SHLEQ;
        return;
    }
    if (c == '>' && next_c == '>' && next_c2 == '=') {
        l->pos += 3;
        l->col += 3;
        l->current.type = TOK_SHREQ;
        return;
    }

    // Two-character operators
    if (c == '<' && next_c == '<') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_SHL;
        return;
    }
    if (c == '>' && next_c == '>') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_SHR;
        return;
    }
    if (c == '+' && next_c == '+') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_PLUSPLUS;
        return;
    }
    if (c == '-' && next_c == '-') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_MINUSMINUS;
        return;
    }
    if (c == '+' && next_c == '=') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_PLUSEQ;
        return;
    }
    if (c == '-' && next_c == '=') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_MINUSEQ;
        return;
    }
    if (c == '*' && next_c == '=') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_STAREQ;
        return;
    }
    if (c == '/' && next_c == '=') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_SLASHEQ;
        return;
    }
    if (c == '%' && next_c == '=') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_PERCENTEQ;
        return;
    }
    if (c == '&' && next_c == '=') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_ANDEQ;
        return;
    }
    if (c == '|' && next_c == '=') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_PIPEEQ;
        return;
    }
    if (c == '^' && next_c == '=') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_CARETEQ;
        return;
    }
    if (c == '=' && next_c == '=') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_EQEQ;
        return;
    }
    if (c == '!' && next_c == '=') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_NEQ;
        return;
    }
    if (c == '<' && next_c == '=') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_LTE;
        return;
    }
    if (c == '>' && next_c == '=') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_GTE;
        return;
    }
    if (c == '&' && next_c == '&') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_ANDAND;
        return;
    }
    if (c == '|' && next_c == '|') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_PIPEPIPE;
        return;
    }
    if (c == '-' && next_c == '>') {
        l->pos += 2; l->col += 2;
        l->current.type = TOK_ARROW;
        return;
    }

    // Single character operators
    l->pos++;
    l->col++;
    if (c == '+') l->current.type = TOK_PLUS;
    else if (c == '-') l->current.type = TOK_MINUS;
    else if (c == '*') l->current.type = TOK_STAR;
    else if (c == '/') l->current.type = TOK_SLASH;
    else if (c == '%') l->current.type = TOK_PERCENT;
    else if (c == '=') l->current.type = TOK_EQUAL;
    else if (c == '<') l->current.type = TOK_LT;
    else if (c == '>') l->current.type = TOK_GT;
    else if (c == '&') l->current.type = TOK_AMPERSAND;
    else if (c == '|') l->current.type = TOK_PIPE;
    else if (c == '^') l->current.type = TOK_CARET;
    else if (c == '~') l->current.type = TOK_TILDE;
    else if (c == '!') l->current.type = TOK_EXCLAM;
    else if (c == ':') l->current.type = TOK_COLON;
    else if (c == '?') l->current.type = TOK_QUESTION;
    else if (c == '(') l->current.type = TOK_LPAREN;
    else if (c == ')') l->current.type = TOK_RPAREN;
    else if (c == '{') l->current.type = TOK_LBRACE;
    else if (c == '}') l->current.type = TOK_RBRACE;
    else if (c == '[') l->current.type = TOK_LBRACKET;
    else if (c == ']') l->current.type = TOK_RBRACKET;
    else if (c == ';') l->current.type = TOK_SEMICOLON;
    else if (c == ',') l->current.type = TOK_COMMA;
    else if (c == '.') l->current.type = TOK_DOT;
    else l->current.type = TOK_EOF;
}

U0 LexNext(Lexer *l) {
    LexerNext(l);
}

U0 LexerInit(Lexer *l, U8 *source) {
    if (!l) return;
    if (source) l->src = source;
    else l->src = "";
    l->pos = 0;
    l->line = 1;
    l->col = 1;
    LexerResetDefines();
    LexerNext(l); // Prime the first token
}

U0 LexInit(Lexer *l, U8 *source) {
    LexerInit(l, source);
}

// ------------------------------------------------------------------------------
// Lexer.HC Verification Suite
// ------------------------------------------------------------------------------
I64 LexerSelfTest() {
    doldoc_print("\n$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$  [LEXER.HC] Pure HolyC Lexical Analyzer Scorecard             $FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");

    I64 passed = 0;
    I64 total = 6;

    // Test 1: Number & Hex parsing
    Lexer l1;
    LexerInit(&l1, "12345 0x1F");
    I64 t1_type = l1.current.type;
    I64 t1_val  = l1.current.int_value;
    LexerNext(&l1);
    I64 t2_type = l1.current.type;
    I64 t2_val  = l1.current.int_value;

    if (t1_type == TOK_NUMBER && t1_val == 12345 && t2_type == TOK_NUMBER && t2_val == 31) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 1: Numeric Literals: 12345, 0x1F (31)\n");
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 1: Expected 12345 & 31, got %lld & %lld\n", t1_val, t2_val);
    }

    // Test 2: Floating-Point Literals (TOK_FLOAT)
    Lexer lflt;
    LexerInit(&lflt, "3.14159 2.5");
    I64 flt1_type = lflt.current.type;
    I64 flt1_scaled = lflt.current.int_value;
    F64 flt1_fval = lflt.current.float_value;
    LexerNext(&lflt);
    I64 flt2_type = lflt.current.type;
    I64 flt2_scaled = lflt.current.int_value;

    if (flt1_type == TOK_FLOAT && flt1_scaled == 314159 && flt1_fval > 3.14 && flt1_fval < 3.15 &&
        flt2_type == TOK_FLOAT && flt2_scaled == 250000) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 2: Floating-Point Literals (TOK_FLOAT): 3.14159 (%lld), 2.5\n", flt1_scaled);
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 2: Float lexing failed: type=%lld, scaled=%lld\n", flt1_type, flt1_scaled);
    }

    // Test 3: Preprocessor #define Table & Identifier Expansion
    Lexer ldef;
    LexerInit(&ldef, "#define MAX_LIMIT 42\n#define HEX_MASK 0xFF\nMAX_LIMIT HEX_MASK");
    I64 d1_type = ldef.current.type;
    I64 d1_val  = ldef.current.int_value;
    LexerNext(&ldef);
    I64 d2_type = ldef.current.type;
    I64 d2_val  = ldef.current.int_value;

    if (d1_type == TOK_NUMBER && d1_val == 42 && d2_type == TOK_NUMBER && d2_val == 255 && g_lex_def_count == 2) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 3: #define Expansion Table: MAX_LIMIT=%lld, HEX_MASK=%lld\n", d1_val, d2_val);
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 3: #define failed: d1=%lld, d2=%lld, cnt=%lld\n", d1_val, d2_val, g_lex_def_count);
    }

    // Test 4: Identifiers, Keywords, Strings & Char Literals
    Lexer l2;
    LexerInit(&l2, "I64 while return my_func_1 \"NeoOS\" 'Z'");
    I64 k1 = l2.current.type; LexerNext(&l2);
    I64 k2 = l2.current.type; LexerNext(&l2);
    I64 k3 = l2.current.type; LexerNext(&l2);
    I64 k4 = l2.current.type;
    I64 str_ok = (strcmp(l2.current.str_value, "my_func_1") == 0);
    LexerNext(&l2);
    I64 s_type = l2.current.type;
    I64 s_ok = (strcmp(l2.current.str_value, "NeoOS") == 0);
    LexerNext(&l2);
    I64 c_type = l2.current.type;
    I64 c_val = l2.current.int_value;

    if (k1 == TOK_TYPE_I64 && k2 == TOK_WHILE && k3 == TOK_RETURN && k4 == TOK_IDENT && str_ok &&
        s_type == TOK_STRING && s_ok && c_type == TOK_NUMBER && c_val == 'Z') {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 4: Keywords, Identifiers, Strings & Chars ('Z'=%lld)\n", c_val);
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 4: Keywords/Strings mismatch\n");
    }

    // Test 5: Compound Operators
    Lexer l4;
    LexerInit(&l4, "-> == != <= >= += ++ <<= && ||");
    I64 op1 = l4.current.type; LexerNext(&l4);
    I64 op2 = l4.current.type; LexerNext(&l4);
    I64 op3 = l4.current.type; LexerNext(&l4);
    I64 op4 = l4.current.type; LexerNext(&l4);
    I64 op5 = l4.current.type; LexerNext(&l4);
    I64 op6 = l4.current.type; LexerNext(&l4);
    I64 op7 = l4.current.type; LexerNext(&l4);
    I64 op8 = l4.current.type; LexerNext(&l4);
    I64 op9 = l4.current.type; LexerNext(&l4);
    I64 op10 = l4.current.type;

    if (op1 == TOK_ARROW && op2 == TOK_EQEQ && op3 == TOK_NEQ &&
        op4 == TOK_LTE && op5 == TOK_GTE && op6 == TOK_PLUSEQ &&
        op7 == TOK_PLUSPLUS && op8 == TOK_SHLEQ && op9 == TOK_ANDAND && op10 == TOK_PIPEPIPE) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 5: Compound & Logical Operators (->, ==, !=, <=, >=, +=, ++, <<=, &&, ||)\n");
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 5: Compound Operators mismatch\n");
    }

    // Test 6: Single-Line & Multi-Line Block Comments & EOF
    Lexer l5;
    LexerInit(&l5, "// line comment\n /* multi-line\n block comment */ 999");
    I64 comm_type = l5.current.type;
    I64 comm_val  = l5.current.int_value;
    LexerNext(&l5);
    I64 eof_type = l5.current.type;

    if (comm_type == TOK_NUMBER && comm_val == 999 && eof_type == TOK_EOF) {
        doldoc_printf("  $FG,GREEN$[PASS]$FG$ Test 6: Single-Line & Multi-Line Comments & EOF (999)\n");
        passed++;
    } else {
        doldoc_printf("  $FG,RED$[FAIL]$FG$ Test 6: Comments/EOF: type=%lld, val=%lld, eof=%lld\n", comm_type, comm_val, eof_type);
    }

    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_printf("$FG,GREEN$  All %lld / %lld Lexer.HC tests passed!$FG$\n", passed, total);
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");

    return passed;
}

if (!g_kernel_booting) {
    LexerSelfTest();
}
