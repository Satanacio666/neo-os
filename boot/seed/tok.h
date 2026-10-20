#ifndef NEO_TOK_H
#define NEO_TOK_H

// Single source of truth for the HolyC token kinds.
//
//   * The C lexer's `token_type_t` enum (boot/seed/lexer.h) is built from this
//     list via the NEO_TOKENS X-macro.
//   * apps/Compiler.HC cannot #include a C header (different language), so it
//     keeps a matching `#define TOK_*` block. scripts/check-token-parity.py
//     verifies that block against this list and fails on any drift, so the two
//     engines' token numbering can never diverge silently.
//
// To add a token: append here, then run
//   python3 scripts/check-token-parity.py
// and update apps/Compiler.HC to match.
#define NEO_TOKENS(X)            \
    X(TOK_EOF,          0)       \
    X(TOK_NUMBER,       1)       \
    X(TOK_FLOAT,        2)       \
    X(TOK_IDENT,        3)       \
    X(TOK_STRING,       4)       \
    X(TOK_RETURN,       5)       \
    X(TOK_IF,           6)       \
    X(TOK_ELSE,         7)       \
    X(TOK_WHILE,        8)       \
    X(TOK_FOR,          9)       \
    X(TOK_BREAK,       10)       \
    X(TOK_CONTINUE,    11)       \
    X(TOK_SWITCH,      12)       \
    X(TOK_CASE,        13)       \
    X(TOK_DEFAULT,     14)       \
    X(TOK_DO,          15)       \
    X(TOK_TYPE_I64,    16)       \
    X(TOK_TYPE_U0,     17)       \
    X(TOK_TYPE_F64,    18)       \
    X(TOK_TYPE_U8,     19)       \
    X(TOK_TYPE_U16,    20)       \
    X(TOK_TYPE_U32,    21)       \
    X(TOK_PLUS,        22)       \
    X(TOK_MINUS,       23)       \
    X(TOK_STAR,        24)       \
    X(TOK_SLASH,       25)       \
    X(TOK_PERCENT,     26)       \
    X(TOK_EQUAL,       27)       \
    X(TOK_AMPERSAND,   28)       \
    X(TOK_ANDAND,      29)       \
    X(TOK_PIPE,        30)       \
    X(TOK_PIPEPIPE,    31)       \
    X(TOK_CARET,       32)       \
    X(TOK_TILDE,       33)       \
    X(TOK_EXCLAM,      34)       \
    X(TOK_EQEQ,        35)       \
    X(TOK_NEQ,         36)       \
    X(TOK_LT,          37)       \
    X(TOK_LTE,         38)       \
    X(TOK_GT,          39)       \
    X(TOK_GTE,         40)       \
    X(TOK_LPAREN,      41)       \
    X(TOK_RPAREN,      42)       \
    X(TOK_LBRACE,      43)       \
    X(TOK_RBRACE,      44)       \
    X(TOK_LBRACKET,    45)       \
    X(TOK_RBRACKET,    46)       \
    X(TOK_SEMICOLON,   47)       \
    X(TOK_COMMA,       48)       \
    X(TOK_DOT,         49)       \
    X(TOK_ARROW,       50)       \
    X(TOK_COLON,       51)       \
    X(TOK_QUESTION,    52)       \
    X(TOK_SHL,         53)       \
    X(TOK_SHR,         54)       \
    X(TOK_PLUSPLUS,    55)       \
    X(TOK_MINUSMINUS,  56)       \
    X(TOK_PLUSEQ,      57)       \
    X(TOK_MINUSEQ,     58)       \
    X(TOK_STAREQ,      59)       \
    X(TOK_SLASHEQ,     60)       \
    X(TOK_PERCENTEQ,   61)       \
    X(TOK_ANDEQ,       62)       \
    X(TOK_PIPEEQ,      63)       \
    X(TOK_CARETEQ,     64)       \
    X(TOK_SHLEQ,       65)       \
    X(TOK_SHREQ,       66)       \
    X(TOK_CLASS,       67)       \
    X(TOK_STRUCT,      68)       \
    X(TOK_AUTO,        69)       \
    X(TOK_SIZEOF,      70)

#endif // NEO_TOK_H
