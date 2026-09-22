#ifndef NEO_LEXER_H
#define NEO_LEXER_H

#include <uefi.h>

typedef enum {
    TOK_EOF = 0,
    TOK_NUMBER,
    TOK_FLOAT,
    TOK_IDENT,
    TOK_STRING,
    // Keywords
    TOK_RETURN,
    TOK_IF,
    TOK_ELSE,
    TOK_WHILE,
    TOK_FOR,
    TOK_BREAK,
    TOK_CONTINUE,
    TOK_SWITCH,
    TOK_CASE,
    TOK_DEFAULT,
    TOK_DO,
    TOK_TYPE_I64,
    TOK_TYPE_U0,
    TOK_TYPE_F64,
    TOK_TYPE_U8,
    TOK_TYPE_U16,
    TOK_TYPE_U32,
    // Arithmetic & Assignment
    TOK_PLUS,
    TOK_MINUS,
    TOK_STAR,
    TOK_SLASH,
    TOK_PERCENT,
    TOK_EQUAL,
    // Bitwise & Logical
    TOK_AMPERSAND,
    TOK_ANDAND,
    TOK_PIPE,
    TOK_PIPEPIPE,
    TOK_CARET,
    TOK_TILDE,
    TOK_EXCLAM,
    // Comparisons
    TOK_EQEQ,
    TOK_NEQ,
    TOK_LT,
    TOK_LTE,
    TOK_GT,
    TOK_GTE,
    // Delimiters & Punctuation
    TOK_LPAREN,
    TOK_RPAREN,
    TOK_LBRACE,
    TOK_RBRACE,
    TOK_LBRACKET,
    TOK_RBRACKET,
    TOK_SEMICOLON,
    TOK_COMMA,
    TOK_DOT,
    TOK_ARROW,
    TOK_COLON,
    TOK_QUESTION,
    TOK_SHL,
    TOK_SHR,
    TOK_PLUSPLUS,
    TOK_MINUSMINUS,
    TOK_PLUSEQ,
    TOK_MINUSEQ,
    TOK_CLASS,
    TOK_STRUCT,
    TOK_AUTO,
    TOK_SIZEOF
} token_type_t;

typedef struct {
    token_type_t type;
    int64_t      int_value;
    double       float_value;
    char         str_value[64];
} token_t;

typedef struct {
    const char *src;
    size_t     pos;
    token_t    current;
} lexer_t;

void    lexer_init(lexer_t *l, const char *source);
token_t lexer_next(lexer_t *l);
token_t lexer_peek(lexer_t *l);

#endif // NEO_LEXER_H
