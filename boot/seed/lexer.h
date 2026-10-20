#ifndef NEO_LEXER_H
#define NEO_LEXER_H

#include <uefi.h>
#include "tok.h"

// The token kinds are defined once in tok.h (NEO_TOKENS). This enum derives from
// that single list; scripts/check-token-parity.py keeps apps/Compiler.HC's
// matching #define block in sync.
typedef enum {
#define NEO_TOK_ENUM(name, val) name = val,
    NEO_TOKENS(NEO_TOK_ENUM)
#undef NEO_TOK_ENUM
} token_type_t;

typedef struct {
    token_type_t type;
    int64_t      int_value;
    double       float_value;
    char         str_value[2048];
    int          line;
    int          col;
} token_t;

typedef struct {
    const char *src;
    size_t     pos;
    int        line;
    int        col;
    token_t    current;
} lexer_t;

void    lexer_init(lexer_t *l, const char *source);
token_t lexer_next(lexer_t *l);
token_t lexer_peek(lexer_t *l);

#endif // NEO_LEXER_H
