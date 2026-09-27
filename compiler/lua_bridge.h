#ifndef NEO_LUA_BRIDGE_H
#define NEO_LUA_BRIDGE_H

void      neo_lua_init(void);
long long neo_lua_eval(const char *code);
int       neo_lua_dostring(const char *code);
int       neo_lua_dofile(const char *path);
void*     neo_lua_get_state(void);

#endif // NEO_LUA_BRIDGE_H
