#include "lua_bridge.h"
#include "lua/lua.h"
#include "lua/lauxlib.h"
#include "lua/lualib.h"
#include <string.h>

// Forward declarations for NeoOS Graphics & Benchmark APIs
extern void     gfx_clear(uint32_t color);
extern void     compositor_set_vsync(uint32_t hz);
extern uint32_t compositor_get_vsync(void);
extern int      bench_unified_start(int mode);
extern void     bench_unified_stop(void);
extern void     bench_unified_set_mode(int mode);
extern int      bench_unified_export_log(void);
extern float    bench_unified_get_fps(void);
extern float    bench_unified_get_frame_time(void);
extern void     bench_unified_set_gear_angle(float angle);
extern void     physics3d_world_explode(void);
extern void     wm_set_dirty(void);

// Forward declarations for NeoOS kernel functions
extern void* kmalloc(size_t size);
extern void* krealloc(void *ptr, size_t new_size);
extern void  kfree(void *ptr);
extern void  uart_puts(const char *s);
extern void  doldoc_print(const char *str);
extern void  doldoc_printf(const char *fmt, ...);
extern int   redsea_read_file(const char *filename, void *buffer, size_t max_bytes, size_t *out_size);
typedef enum {
    SYM_FUNC = 1,
    SYM_VAR  = 2,
    SYM_HARDWARE = 3
} symbol_type_t;

typedef struct symbol {
    char            name[64];
    void           *address;
    symbol_type_t   type;
    uint32_t        hash;
    struct symbol  *next;
} symbol_t;

extern symbol_t* symbols_lookup_entry(const char *name);
extern int       symbols_register(const char *name, void *address, symbol_type_t type);

static lua_State *g_L = NULL;

// Custom baremetal allocator using NeoOS Kernel Heap (kmalloc / krealloc / kfree)
static void *neo_lua_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    (void)ud;
    (void)osize;
    if (nsize == 0) {
        if (ptr) kfree(ptr);
        return NULL;
    }
    return krealloc(ptr, nsize);
}

// Custom Lua print() that outputs to both DolDoc GUI console and PL011 UART
static int neo_lua_print(lua_State *L) {
    int n = lua_gettop(L);
    for (int i = 1; i <= n; i++) {
        const char *s = luaL_tolstring(L, i, NULL);
        if (s) {
            doldoc_printf("%s%s", (i > 1) ? "\t" : "", s);
            uart_puts(s);
            if (i < n) uart_puts("\t");
        }
        lua_pop(L, 1);
    }
    doldoc_print("\n");
    uart_puts("\r\n");
    return 0;
}

// ─── High-Level Lua 3D & Compositor Bridge ("neo3d") ──────────────────────────

static int l_neo3d_clear(lua_State *L) {
    uint32_t col = (uint32_t)luaL_optinteger(L, 1, 0xFF14171A);
    gfx_clear(col);
    return 0;
}

static int l_neo3d_set_vsync(lua_State *L) {
    uint32_t hz = (uint32_t)luaL_checkinteger(L, 1);
    compositor_set_vsync(hz);
    return 0;
}

static int l_neo3d_get_vsync(lua_State *L) {
    lua_pushinteger(L, compositor_get_vsync());
    return 1;
}

static int l_neo3d_get_fps(lua_State *L) {
    lua_pushnumber(L, (lua_Number)bench_unified_get_fps());
    return 1;
}

static int l_neo3d_get_frame_time(lua_State *L) {
    lua_pushnumber(L, (lua_Number)bench_unified_get_frame_time());
    return 1;
}

static int l_neo3d_start(lua_State *L) {
    int mode = (int)luaL_optinteger(L, 1, 0);
    int res = bench_unified_start(mode);
    lua_pushboolean(L, res);
    return 1;
}

static int l_neo3d_stop(lua_State *L) {
    bench_unified_stop();
    return 0;
}

static int l_neo3d_set_mode(lua_State *L) {
    int mode = (int)luaL_checkinteger(L, 1);
    bench_unified_set_mode(mode);
    return 0;
}

static int l_neo3d_set_gear_angle(lua_State *L) {
    float angle = (float)luaL_checknumber(L, 1);
    bench_unified_set_gear_angle(angle);
    return 0;
}

static int l_neo3d_export_log(lua_State *L) {
    int res = bench_unified_export_log();
    lua_pushboolean(L, res == 0);
    return 1;
}

extern uint64_t arm64_ffi_call(void *fn, const uint64_t *int_args, int int_count, const double *fp_args, int fp_count, int is_fp32, double *out_fp);

static int l_neo3d_trigger_impulse(lua_State *L) {
    (void)L;
    physics3d_world_explode();
    wm_set_dirty();
    return 0;
}

// Universal C/HolyC function invoker from Lua using native AArch64 AAPCS FFI
static int lua_call_c_symbol(lua_State *L) {
    void *fn_ptr = lua_touserdata(L, lua_upvalueindex(1));
    const char *sym_name = lua_tostring(L, lua_upvalueindex(2));
    if (!fn_ptr) {
        return luaL_error(L, "Null function pointer invoked from symbol table");
    }

    int is_fp32 = 0;
    if (sym_name) {
        if (strcmp(sym_name, "fast_sqrt_neon") == 0 ||
            strcmp(sym_name, "fast_rsqrt_neon") == 0 ||
            strcmp(sym_name, "math3d_sin") == 0 ||
            strcmp(sym_name, "math3d_cos") == 0 ||
            strcmp(sym_name, "bench_unified_get_fps") == 0 ||
            strcmp(sym_name, "bench_unified_get_frame_time") == 0 ||
            strcmp(sym_name, "bench_unified_set_gear_angle") == 0) {
            is_fp32 = 1;
        }
    }

    int nargs = lua_gettop(L);
    uint64_t int_args[8] = {0};
    double   fp_args[8]  = {0.0};
    int      int_count = 0;
    int      fp_count  = 0;

    for (int i = 0; i < nargs && (int_count < 8 || fp_count < 8); i++) {
        int idx = i + 1;
        if (lua_isinteger(L, idx)) {
            if (int_count < 8) int_args[int_count++] = (uint64_t)lua_tointeger(L, idx);
        } else if (lua_isnumber(L, idx)) {
            double d = lua_tonumber(L, idx);
            if (fp_count < 8) fp_args[fp_count++] = d;
            // Also mirror as integer for flexible hybrid C signatures
            if (int_count < 8) int_args[int_count++] = (uint64_t)(int64_t)d;
        } else if (lua_isstring(L, idx)) {
            if (int_count < 8) int_args[int_count++] = (uint64_t)lua_tostring(L, idx);
        } else if (lua_isboolean(L, idx)) {
            if (int_count < 8) int_args[int_count++] = (uint64_t)lua_toboolean(L, idx);
        } else if (lua_islightuserdata(L, idx) || lua_isuserdata(L, idx)) {
            if (int_count < 8) int_args[int_count++] = (uint64_t)lua_touserdata(L, idx);
        } else if (lua_isnil(L, idx)) {
            if (int_count < 8) int_args[int_count++] = 0;
        } else {
            if (int_count < 8) int_args[int_count++] = (uint64_t)lua_topointer(L, idx);
        }
    }

    double fp_res = 0.0;
    uint64_t res = arm64_ffi_call(fn_ptr, int_args, int_count, fp_args, fp_count, is_fp32, &fp_res);

    if (is_fp32 || (fp_count > 0 && fp_res != 0.0)) {
        lua_pushnumber(L, (lua_Number)fp_res);
    } else {
        lua_pushinteger(L, (lua_Integer)res);
    }
    return 1;
}

// Metatable __index for _G: seamlessly resolves any HolyC/C symbol into Lua
static int lua_global_index(lua_State *L) {
    const char *name = luaL_checkstring(L, 2);
    symbol_t *sym = symbols_lookup_entry(name);
    if (!sym) {
        lua_pushnil(L);
        return 1;
    }

    if (sym->type == SYM_FUNC) {
        lua_pushlightuserdata(L, sym->address);
        lua_pushstring(L, name);
        lua_pushcclosure(L, lua_call_c_symbol, 2);
        return 1;
    } else if (sym->type == SYM_VAR) {
        int64_t *slot = (int64_t*)sym->address;
        if (slot) {
            lua_pushinteger(L, (lua_Integer)*slot);
        } else {
            lua_pushnil(L);
        }
        return 1;
    }

    lua_pushnil(L);
    return 1;
}

// Metatable __newindex for _G: registering a number in Lua makes it available to HolyC
static int lua_global_newindex(lua_State *L) {
    const char *name = luaL_checkstring(L, 2);
    if (lua_isinteger(L, 3)) {
        int64_t val = (int64_t)lua_tointeger(L, 3);
        symbol_t *sym = symbols_lookup_entry(name);
        if (sym && sym->type == SYM_VAR && sym->address) {
            *(int64_t*)sym->address = val;
        } else {
            int64_t *slot = (int64_t*)kmalloc(sizeof(int64_t));
            if (slot) {
                *slot = val;
                symbols_register(name, slot, SYM_VAR);
            }
        }
    }
    lua_rawset(L, 1);
    return 0;
}

void neo_lua_init(void) {
    if (g_L) return;

    // Allocate master state using high-performance kernel heap
    g_L = lua_newstate(neo_lua_alloc, NULL);
    if (!g_L) {
        doldoc_print("$FG,RED$[LUA] Error: Could not allocate Lua master state!$FG$\n");
        printf("[LUA] Error: Could not allocate Lua state\n");
        return;
    }

    // Load pure algorithmic and safe standard libraries (freestanding baremetal)
    luaL_requiref(g_L, LUA_GNAME, luaopen_base, 1);
    lua_pop(g_L, 1);
    luaL_requiref(g_L, LUA_COLIBNAME, luaopen_coroutine, 1);
    lua_pop(g_L, 1);
    luaL_requiref(g_L, LUA_TABLIBNAME, luaopen_table, 1);
    lua_pop(g_L, 1);
    luaL_requiref(g_L, LUA_STRLIBNAME, luaopen_string, 1);
    lua_pop(g_L, 1);
    luaL_requiref(g_L, LUA_MATHLIBNAME, luaopen_math, 1);
    lua_pop(g_L, 1);
    luaL_requiref(g_L, LUA_UTF8LIBNAME, luaopen_utf8, 1);
    lua_pop(g_L, 1);
    luaL_requiref(g_L, LUA_DBLIBNAME, luaopen_debug, 1);
    lua_pop(g_L, 1);

    // Override global print()
    lua_pushcfunction(g_L, neo_lua_print);
    lua_setglobal(g_L, "print");

    // Set metatable on _G for seamless HolyC/NeoOS symbol table reflection
    lua_pushglobaltable(g_L); // push _G
    lua_newtable(g_L);        // metatable
    lua_pushcfunction(g_L, lua_global_index);
    lua_setfield(g_L, -2, "__index");
    lua_pushcfunction(g_L, lua_global_newindex);
    lua_setfield(g_L, -2, "__newindex");
    lua_setmetatable(g_L, -2); // setmetatable(_G, mt)
    lua_pop(g_L, 1);           // pop _G

    // Register high-level neo3d module table
    lua_newtable(g_L);
    lua_pushcfunction(g_L, l_neo3d_clear);          lua_setfield(g_L, -2, "clear");
    lua_pushcfunction(g_L, l_neo3d_set_vsync);      lua_setfield(g_L, -2, "set_vsync");
    lua_pushcfunction(g_L, l_neo3d_get_vsync);      lua_setfield(g_L, -2, "get_vsync");
    lua_pushcfunction(g_L, l_neo3d_get_fps);        lua_setfield(g_L, -2, "get_fps");
    lua_pushcfunction(g_L, l_neo3d_get_frame_time); lua_setfield(g_L, -2, "get_frame_time");
    lua_pushcfunction(g_L, l_neo3d_start);          lua_setfield(g_L, -2, "start");
    lua_pushcfunction(g_L, l_neo3d_stop);           lua_setfield(g_L, -2, "stop");
    lua_pushcfunction(g_L, l_neo3d_set_mode);       lua_setfield(g_L, -2, "set_mode");
    lua_pushcfunction(g_L, l_neo3d_set_gear_angle); lua_setfield(g_L, -2, "set_gear_angle");
    lua_pushcfunction(g_L, l_neo3d_export_log);     lua_setfield(g_L, -2, "export_log");
    lua_pushcfunction(g_L, l_neo3d_trigger_impulse); lua_setfield(g_L, -2, "trigger_impulse");
    lua_setglobal(g_L, "neo3d");

    // Register Lua bridge functions in the NeoOS global Symbol Table
    symbols_register("lua_eval", (void*)neo_lua_eval, SYM_FUNC);
    symbols_register("lua_dostring", (void*)neo_lua_dostring, SYM_FUNC);
    symbols_register("lua_dofile", (void*)neo_lua_dofile, SYM_FUNC);

    doldoc_print("$FG,CYAN$[LUA]$FG$ Lua 5.4.7 unified with HolyC Symbol Table (SASOS Active)\n");
    uart_puts("[LUA] Lua 5.4.7 unified with HolyC Symbol Table\r\n");
    printf("[LUA] Lua 5.4.7 initialized with HolyC Symbol Table reflection.\n");
}

int neo_lua_dostring(const char *code) {
    if (!g_L) neo_lua_init();
    if (!g_L || !code) return -1;

    int status = luaL_dostring(g_L, code);
    if (status != LUA_OK) {
        const char *err_msg = lua_tostring(g_L, -1);
        doldoc_printf("$FG,RED$[LUA ERROR] %s$FG$\n", err_msg ? err_msg : "Unknown error");
        uart_puts("[LUA ERROR] ");
        if (err_msg) uart_puts(err_msg);
        uart_puts("\r\n");
        lua_pop(g_L, 1);
        return -1;
    }
    return 0;
}

long long neo_lua_eval(const char *code) {
    if (!g_L) neo_lua_init();
    if (!g_L || !code) return 0;

    // First try evaluating as "return (<expr>);"
    char expr_buf[512];
    snprintf(expr_buf, sizeof(expr_buf), "return (%s);", code);

    int status = luaL_dostring(g_L, expr_buf);
    if (status != LUA_OK) {
        lua_pop(g_L, 1); // pop error
        status = luaL_dostring(g_L, code);
    }

    if (status != LUA_OK) {
        const char *err_msg = lua_tostring(g_L, -1);
        doldoc_printf("$FG,RED$[LUA ERROR] %s$FG$\n", err_msg ? err_msg : "Evaluation failed");
        lua_pop(g_L, 1);
        return 0;
    }

    long long result = 0;
    if (lua_gettop(g_L) > 0) {
        if (lua_isinteger(g_L, -1)) {
            result = (long long)lua_tointeger(g_L, -1);
        } else if (lua_isnumber(g_L, -1)) {
            result = (long long)lua_tonumber(g_L, -1);
        } else if (lua_isboolean(g_L, -1)) {
            result = (long long)lua_toboolean(g_L, -1);
        }
        lua_pop(g_L, 1);
    }

    return result;
}

int neo_lua_dofile(const char *path) {
    if (!g_L) neo_lua_init();
    if (!g_L || !path) return -1;

    size_t fsize = 0;
    uint8_t *fbuf = (uint8_t*)kmalloc(65536);
    if (!fbuf) return -1;

    if (redsea_read_file(path, fbuf, 65535, &fsize) != 0) {
        kfree(fbuf);
        doldoc_printf("$FG,RED$[LUA] Error: Could not read file '%s'$FG$\n", path);
        return -1;
    }
    fbuf[fsize] = '\0';

    doldoc_printf("$FG,CYAN$[LUA]$FG$ Executing '%s' (%llu bytes)...\n", path, (unsigned long long)fsize);
    int status = luaL_dostring(g_L, (const char*)fbuf);
    kfree(fbuf);

    if (status != LUA_OK) {
        const char *err_msg = lua_tostring(g_L, -1);
        doldoc_printf("$FG,RED$[LUA ERROR in %s] %s$FG$\n", path, err_msg ? err_msg : "Execution failed");
        lua_pop(g_L, 1);
        return -1;
    }
    return 0;
}

void* neo_lua_get_state(void) {
    return (void*)g_L;
}
