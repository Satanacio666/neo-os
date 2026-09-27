#include <uefi.h>

extern uint64_t timer_get_ticks(void);

// 1. Clock & Errno
uint64_t clock(void) {
    return timer_get_ticks() * 10000;
}

static int s_lua_errno = 0;
int* __errno_location(void) {
    return &s_lua_errno;
}

// 2. Localeconv
struct lconv {
    char *decimal_point;
    char *thousands_sep;
    char *grouping;
    char *int_curr_symbol;
    char *currency_symbol;
    char *mon_decimal_point;
    char *mon_thousands_sep;
    char *mon_grouping;
    char *positive_sign;
    char *negative_sign;
    char int_frac_digits;
    char frac_digits;
    char p_cs_precedes;
    char p_sep_by_space;
    char n_cs_precedes;
    char n_sep_by_space;
    char p_sign_posn;
    char n_sign_posn;
};

static struct lconv s_lconv = {
    .decimal_point = ".",
    .thousands_sep = "",
    .grouping = ""
};

struct lconv* localeconv(void) {
    return &s_lconv;
}

// 3. String & Ctype helpers
int strcoll(const char *s1, const char *s2) {
    return strcmp(s1, s2);
}

char* strerror(int errnum) {
    (void)errnum;
    return "Operation failed";
}

char* strpbrk(const char *s, const char *accept) {
    while (*s) {
        const char *a = accept;
        while (*a) {
            if (*s == *a) return (char*)s;
            a++;
        }
        s++;
    }
    return NULL;
}

size_t strspn(const char *s, const char *accept) {
    size_t count = 0;
    while (*s) {
        const char *a = accept;
        int found = 0;
        while (*a) {
            if (*s == *a) { found = 1; break; }
            a++;
        }
        if (!found) break;
        count++;
        s++;
    }
    return count;
}

double strtod(const char *nptr, char **endptr) {
    while (*nptr == ' ' || *nptr == '\t' || *nptr == '\n' || *nptr == '\r') nptr++;
    double sign = 1.0;
    if (*nptr == '-') { sign = -1.0; nptr++; }
    else if (*nptr == '+') { nptr++; }

    double val = 0.0;
    while (*nptr >= '0' && *nptr <= '9') {
        val = val * 10.0 + (*nptr - '0');
        nptr++;
    }
    if (*nptr == '.') {
        nptr++;
        double frac = 0.1;
        while (*nptr >= '0' && *nptr <= '9') {
            val += (*nptr - '0') * frac;
            frac *= 0.1;
            nptr++;
        }
    }
    if (*nptr == 'e' || *nptr == 'E') {
        nptr++;
        int exp_sign = 1;
        if (*nptr == '-') { exp_sign = -1; nptr++; }
        else if (*nptr == '+') { nptr++; }
        int exp_val = 0;
        while (*nptr >= '0' && *nptr <= '9') {
            exp_val = exp_val * 10 + (*nptr - '0');
            nptr++;
        }
        double p = 1.0;
        while (exp_val-- > 0) p *= 10.0;
        if (exp_sign < 0) val /= p;
        else val *= p;
    }
    if (endptr) *endptr = (char*)nptr;
    return val * sign;
}

static const unsigned short s_ctype_table[384] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    // [128]: Standard 0..127 ASCII classes
    0, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
    0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
    0x01, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10,
    0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10,
    0x10, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04,
    0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x10, 0x10, 0x10, 0x10, 0x10,
    0x10, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,
    0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x10, 0x10, 0x10, 0x10, 0x20
};

const unsigned short** __ctype_b_loc(void) {
    static const unsigned short *p = &s_ctype_table[128];
    return &p;
}

static const int32_t s_tolower_table[384] = {0};
const int32_t** __ctype_tolower_loc(void) {
    static const int32_t *p = &s_tolower_table[128];
    return &p;
}

static const int32_t s_toupper_table[384] = {0};
const int32_t** __ctype_toupper_loc(void) {
    static const int32_t *p = &s_toupper_table[128];
    return &p;
}

// 4. Stdio stubs (file loading in NeoOS is handled via RedSea filesystem)
void* fopen64(const char *path, const char *mode) { (void)path; (void)mode; return NULL; }
void* freopen64(const char *path, const char *mode, void *f) { (void)path; (void)mode; (void)f; return NULL; }
int   ferror(void *f) { (void)f; return 0; }
char* fgets(char *s, int size, void *f) { (void)s; (void)size; (void)f; return NULL; }
int   getc(void *f) { (void)f; return -1; }

// 5. Hardware-Accelerated Floating Point Math (AArch64 NEON/FP VFPv4)
double fabs(double x) {
    return __builtin_fabs(x);
}

double sqrt(double x) {
    return __builtin_sqrt(x);
}



double fmod(double x, double y) {
    return __builtin_fmod(x, y);
}

// Taylor Series / Polynomial Approximations for Transcendental Math
#define PI 3.14159265358979323846

double sin(double x) {
    while (x > PI) x -= 2.0 * PI;
    while (x < -PI) x += 2.0 * PI;
    double x2 = x * x;
    return x * (1.0 - x2 * (1.0 / 6.0 - x2 * (1.0 / 120.0 - x2 * (1.0 / 5040.0 - x2 / 362880.0))));
}

double cos(double x) {
    return sin(x + PI * 0.5);
}

double tan(double x) {
    double c = cos(x);
    if (__builtin_fabs(c) < 1e-12) return (sin(x) > 0) ? 1e12 : -1e12;
    return sin(x) / c;
}

double asin(double x) {
    if (x < -1.0) x = -1.0;
    if (x > 1.0) x = 1.0;
    double x3 = x * x * x;
    return x + (1.0 / 6.0) * x3 + (3.0 / 40.0) * (x3 * x * x);
}

double acos(double x) {
    return PI * 0.5 - asin(x);
}

double atan2(double y, double x) {
    if (x > 0.0) {
        double r = y / x;
        return r / (1.0 + 0.28 * r * r);
    } else if (x < 0.0) {
        double r = y / x;
        double at = r / (1.0 + 0.28 * r * r);
        return (y >= 0.0) ? at + PI : at - PI;
    }
    return (y > 0.0) ? (PI * 0.5) : ((y < 0.0) ? -(PI * 0.5) : 0.0);
}

double exp(double x) {
    if (x > 700.0) x = 700.0;
    if (x < -700.0) return 0.0;
    double sum = 1.0, term = 1.0;
    for (int i = 1; i <= 24; i++) {
        term = term * x / i;
        sum += term;
    }
    return sum;
}

double log(double x) {
    if (x <= 0.0) return -1e12;
    int k = 0;
    while (x > 2.0) { x *= 0.5; k++; }
    while (x < 1.0) { x *= 2.0; k--; }
    double y = (x - 1.0) / (x + 1.0);
    double y2 = y * y;
    double sum = y * (2.0 + y2 * (2.0 / 3.0 + y2 * (2.0 / 5.0 + y2 * (2.0 / 7.0))));
    return sum + k * 0.6931471805599453;
}

double log10(double x) {
    return log(x) * 0.4342944819032518;
}

double log2(double x) {
    return log(x) * 1.4426950408889634;
}

double pow(double base, double exponent) {
    if (exponent == 0.0) return 1.0;
    int64_t exp_int = (int64_t)exponent;
    if ((double)exp_int == exponent) {
        double result = 1.0;
        double b = base;
        int64_t p = (exp_int < 0) ? -exp_int : exp_int;
        while (p > 0) {
            if (p & 1) result *= b;
            b *= b;
            p >>= 1;
        }
        return (exp_int < 0) ? (1.0 / result) : result;
    }
    if (base <= 0.0) return 0.0;
    return exp(exponent * log(base));
}

double ldexp(double x, int exp) {
    double factor = 1.0;
    if (exp > 0) {
        while (exp--) factor *= 2.0;
        return x * factor;
    } else if (exp < 0) {
        while (exp++) factor *= 0.5;
        return x * factor;
    }
    return x;
}

double frexp(double x, int *exp) {
    if (x == 0.0) { *exp = 0; return 0.0; }
    int e = 0;
    double sign = 1.0;
    if (x < 0.0) { sign = -1.0; x = -x; }
    while (x >= 1.0) { x *= 0.5; e++; }
    while (x < 0.5) { x *= 2.0; e--; }
    *exp = e;
    return x * sign;
}

#undef stdin
#undef stdout
#undef stderr
#undef abs

FILE* stdin = NULL;
FILE* stdout = NULL;
FILE* stderr = NULL;

int abs(int x) {
    return (x < 0) ? -x : x;
}

int __printf_chk(int flag, const char *fmt, ...) {
    (void)flag;
    __builtin_va_list ap;
    __builtin_va_start(ap, fmt);
    int ret = vprintf(fmt, ap);
    __builtin_va_end(ap);
    return ret;
}

int __snprintf_chk(char *s, size_t maxlen, int flag, size_t slen, const char *format, ...) {
    (void)flag;
    (void)slen;
    __builtin_va_list ap;
    __builtin_va_start(ap, format);
    int ret = vsnprintf(s, maxlen, format, ap);
    __builtin_va_end(ap);
    return ret;
}

int neo_lua_number2str(char *s, size_t sz, double n) {
    if (!s || sz == 0) return 0;
    if (n != n) {
        strncpy(s, "nan", sz - 1);
        s[sz - 1] = '\0';
        return 3;
    }
    if (n > 1e300) {
        strncpy(s, "inf", sz - 1);
        s[sz - 1] = '\0';
        return 3;
    }
    if (n < -1e300) {
        strncpy(s, "-inf", sz - 1);
        s[sz - 1] = '\0';
        return 4;
    }
    int64_t i = (int64_t)n;
    if ((double)i == n) {
        return snprintf(s, sz, "%lld", (long long)i);
    }
    int sign = (n < 0);
    double abs_n = sign ? -n : n;
    int64_t ipart = (int64_t)abs_n;
    int64_t fpart = (int64_t)((abs_n - (double)ipart) * 1000000.0);
    return snprintf(s, sz, "%s%lld.%06lld", sign ? "-" : "", (long long)ipart, (long long)fpart);
}
