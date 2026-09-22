#include "lexer.h"

static int is_digit(char c) {
    return c >= '0' && c <= '9';
}

static int is_hex_digit(char c) {
    return (c >= '0' && c <= '9') ||
           (c >= 'a' && c <= 'f') ||
           (c >= 'A' && c <= 'F');
}

static int hex_val(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return 0;
}

static int is_alpha(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

void lexer_init(lexer_t *l, const char *source) {
    l->src = source ? source : "";
    l->pos = 0;
    lexer_next(l); // Prime the first token
}

token_t lexer_peek(lexer_t *l) {
    return l->current;
}

token_t lexer_next(lexer_t *l) {
    token_t tok = {0};

    // Skip whitespace
    while (l->src[l->pos] && (l->src[l->pos] == ' ' || l->src[l->pos] == '\t' ||
           l->src[l->pos] == '\n' || l->src[l->pos] == '\r')) {
        l->pos++;
    }

    char c = l->src[l->pos];
    if (c == '\0') {
        tok.type = TOK_EOF;
        l->current = tok;
        return tok;
    }

    // Skip single-line comments // ...
    if (c == '/' && l->src[l->pos + 1] == '/') {
        l->pos += 2;
        while (l->src[l->pos] && l->src[l->pos] != '\n') {
            l->pos++;
        }
        return lexer_next(l);
    }

    // Number (decimal or hex 0x...)
    // Number (decimal, hex 0x..., or float 3.14)
    if (is_digit(c)) {
        int64_t val = 0;
        if (c == '0' && (l->src[l->pos + 1] == 'x' || l->src[l->pos + 1] == 'X')) {
            l->pos += 2;
            while (is_hex_digit(l->src[l->pos])) {
                val = (val << 4) | hex_val(l->src[l->pos]);
                l->pos++;
            }
            tok.type = TOK_NUMBER;
            tok.int_value = val;
            tok.float_value = (double)val;
        } else {
            while (is_digit(l->src[l->pos])) {
                val = val * 10 + (l->src[l->pos] - '0');
                l->pos++;
            }
            if (l->src[l->pos] == '.' && is_digit(l->src[l->pos + 1])) {
                l->pos++; // skip '.'
                double fval = (double)val;
                double div = 10.0;
                while (is_digit(l->src[l->pos])) {
                    fval += (l->src[l->pos] - '0') / div;
                    div *= 10.0;
                    l->pos++;
                }
                tok.type = TOK_FLOAT;
                tok.float_value = fval;
                tok.int_value = (int64_t)fval;
            } else {
                tok.type = TOK_NUMBER;
                tok.int_value = val;
                tok.float_value = (double)val;
            }
        }
        l->current = tok;
        return tok;
    }

    // Identifier / Keyword
    if (is_alpha(c)) {
        size_t len = 0;
        while (is_alpha(l->src[l->pos]) || is_digit(l->src[l->pos])) {
            if (len < sizeof(tok.str_value) - 1) {
                tok.str_value[len++] = l->src[l->pos];
            }
            l->pos++;
        }
        tok.str_value[len] = '\0';

        if (strcmp(tok.str_value, "return") == 0) {
            tok.type = TOK_RETURN;
        } else if (strcmp(tok.str_value, "if") == 0) {
            tok.type = TOK_IF;
        } else if (strcmp(tok.str_value, "else") == 0) {
            tok.type = TOK_ELSE;
        } else if (strcmp(tok.str_value, "while") == 0) {
            tok.type = TOK_WHILE;
        } else if (strcmp(tok.str_value, "for") == 0) {
            tok.type = TOK_FOR;
        } else if (strcmp(tok.str_value, "break") == 0) {
            tok.type = TOK_BREAK;
        } else if (strcmp(tok.str_value, "continue") == 0) {
            tok.type = TOK_CONTINUE;
        } else if (strcmp(tok.str_value, "switch") == 0) {
            tok.type = TOK_SWITCH;
        } else if (strcmp(tok.str_value, "case") == 0) {
            tok.type = TOK_CASE;
        } else if (strcmp(tok.str_value, "default") == 0) {
            tok.type = TOK_DEFAULT;
        } else if (strcmp(tok.str_value, "do") == 0) {
            tok.type = TOK_DO;
        } else if (strcmp(tok.str_value, "I64") == 0 || strcmp(tok.str_value, "U64") == 0 ||
                   strcmp(tok.str_value, "int") == 0 || strcmp(tok.str_value, "long") == 0) {
            tok.type = TOK_TYPE_I64;
        } else if (strcmp(tok.str_value, "U0") == 0 || strcmp(tok.str_value, "void") == 0) {
            tok.type = TOK_TYPE_U0;
        } else if (strcmp(tok.str_value, "F64") == 0 || strcmp(tok.str_value, "double") == 0 ||
                   strcmp(tok.str_value, "float") == 0) {
            tok.type = TOK_TYPE_F64;
        } else if (strcmp(tok.str_value, "U8") == 0 || strcmp(tok.str_value, "I8") == 0 ||
                   strcmp(tok.str_value, "char") == 0 || strcmp(tok.str_value, "uint8_t") == 0) {
            tok.type = TOK_TYPE_U8;
        } else if (strcmp(tok.str_value, "U16") == 0 || strcmp(tok.str_value, "I16") == 0 ||
                   strcmp(tok.str_value, "short") == 0 || strcmp(tok.str_value, "uint16_t") == 0) {
            tok.type = TOK_TYPE_U16;
        } else if (strcmp(tok.str_value, "U32") == 0 || strcmp(tok.str_value, "I32") == 0 ||
                   strcmp(tok.str_value, "uint32_t") == 0) {
            tok.type = TOK_TYPE_U32;
        } else if (strcmp(tok.str_value, "class") == 0) {
            tok.type = TOK_CLASS;
        } else if (strcmp(tok.str_value, "struct") == 0) {
            tok.type = TOK_STRUCT;
        } else if (strcmp(tok.str_value, "auto") == 0) {
            tok.type = TOK_AUTO;
        } else if (strcmp(tok.str_value, "sizeof") == 0) {
            tok.type = TOK_SIZEOF;
        } else {
            tok.type = TOK_IDENT;
        }
        l->current = tok;
        return tok;
    }

    // String literal "..."
    if (c == '"') {
        l->pos++; // skip opening quote
        size_t len = 0;
        while (l->src[l->pos] && l->src[l->pos] != '"') {
            if (l->src[l->pos] == '\\' && l->src[l->pos + 1]) {
                l->pos++;
                char esc = l->src[l->pos];
                if (esc == 'n') esc = '\n';
                else if (esc == 'r') esc = '\r';
                else if (esc == 't') esc = '\t';
                else if (esc == '0') esc = '\0';
                if (len < sizeof(tok.str_value) - 1) tok.str_value[len++] = esc;
            } else {
                if (len < sizeof(tok.str_value) - 1) {
                    tok.str_value[len++] = l->src[l->pos];
                }
            }
            l->pos++;
        }
        if (l->src[l->pos] == '"') l->pos++; // skip closing quote
        tok.str_value[len] = '\0';
        tok.type = TOK_STRING;
        l->current = tok;
        return tok;
    }

    // Character literal '...'
    if (c == '\'') {
        l->pos++; // skip opening single quote
        int64_t ch = 0;
        if (l->src[l->pos] == '\\' && l->src[l->pos + 1]) {
            l->pos++;
            char esc = l->src[l->pos++];
            if (esc == 'n') ch = '\n';
            else if (esc == 'r') ch = '\r';
            else if (esc == 't') ch = '\t';
            else if (esc == '0') ch = '\0';
            else ch = esc;
        } else if (l->src[l->pos] && l->src[l->pos] != '\'') {
            ch = (unsigned char)l->src[l->pos++];
        }
        if (l->src[l->pos] == '\'') l->pos++; // skip closing single quote
        tok.type = TOK_NUMBER;
        tok.int_value = ch;
        tok.float_value = (double)ch;
        l->current = tok;
        return tok;
    }

    // Two-character operators
    char next_c = l->src[l->pos + 1];
    if (c == '<' && next_c == '<') {
        l->pos += 2;
        tok.type = TOK_SHL;
        l->current = tok;
        return tok;
    }
    if (c == '>' && next_c == '>') {
        l->pos += 2;
        tok.type = TOK_SHR;
        l->current = tok;
        return tok;
    }
    if (c == '+' && next_c == '+') {
        l->pos += 2;
        tok.type = TOK_PLUSPLUS;
        l->current = tok;
        return tok;
    }
    if (c == '-' && next_c == '-') {
        l->pos += 2;
        tok.type = TOK_MINUSMINUS;
        l->current = tok;
        return tok;
    }
    if (c == '+' && next_c == '=') {
        l->pos += 2;
        tok.type = TOK_PLUSEQ;
        l->current = tok;
        return tok;
    }
    if (c == '-' && next_c == '=') {
        l->pos += 2;
        tok.type = TOK_MINUSEQ;
        l->current = tok;
        return tok;
    }
    if (c == '=' && next_c == '=') {
        l->pos += 2;
        tok.type = TOK_EQEQ;
        l->current = tok;
        return tok;
    }
    if (c == '!' && next_c == '=') {
        l->pos += 2;
        tok.type = TOK_NEQ;
        l->current = tok;
        return tok;
    }
    if (c == '<' && next_c == '=') {
        l->pos += 2;
        tok.type = TOK_LTE;
        l->current = tok;
        return tok;
    }
    if (c == '>' && next_c == '=') {
        l->pos += 2;
        tok.type = TOK_GTE;
        l->current = tok;
        return tok;
    }
    if (c == '&' && next_c == '&') {
        l->pos += 2;
        tok.type = TOK_ANDAND;
        l->current = tok;
        return tok;
    }
    if (c == '|' && next_c == '|') {
        l->pos += 2;
        tok.type = TOK_PIPEPIPE;
        l->current = tok;
        return tok;
    }
    if (c == '-' && next_c == '>') {
        l->pos += 2;
        tok.type = TOK_ARROW;
        l->current = tok;
        return tok;
    }

    // Single character operators
    l->pos++;
    switch (c) {
        case '+': tok.type = TOK_PLUS; break;
        case '-': tok.type = TOK_MINUS; break;
        case '*': tok.type = TOK_STAR; break;
        case '/': tok.type = TOK_SLASH; break;
        case '%': tok.type = TOK_PERCENT; break;
        case '=': tok.type = TOK_EQUAL; break;
        case '<': tok.type = TOK_LT; break;
        case '>': tok.type = TOK_GT; break;
        case '&': tok.type = TOK_AMPERSAND; break;
        case '|': tok.type = TOK_PIPE; break;
        case '^': tok.type = TOK_CARET; break;
        case '~': tok.type = TOK_TILDE; break;
        case '!': tok.type = TOK_EXCLAM; break;
        case ':': tok.type = TOK_COLON; break;
        case '?': tok.type = TOK_QUESTION; break;
        case '(': tok.type = TOK_LPAREN; break;
        case ')': tok.type = TOK_RPAREN; break;
        case '{': tok.type = TOK_LBRACE; break;
        case '}': tok.type = TOK_RBRACE; break;
        case '[': tok.type = TOK_LBRACKET; break;
        case ']': tok.type = TOK_RBRACKET; break;
        case ';': tok.type = TOK_SEMICOLON; break;
        case ',': tok.type = TOK_COMMA; break;
        case '.': tok.type = TOK_DOT; break;
        default:  tok.type = TOK_EOF; break;
    }

    l->current = tok;
    return tok;
}
