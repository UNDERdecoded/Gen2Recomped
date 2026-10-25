/* Public Lua 5.1 C API boundary probe: no engine/mod/ROM inputs. */
#include <stdio.h>
#include <stdlib.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
static int capacity;
static int captured_sum(lua_State *L) {
  lua_Number sum = 0;
  int i;
  for (i = 1; i <= capacity; ++i) sum += lua_tonumber(L, lua_upvalueindex(i));
  lua_pushnumber(L, sum);
  return 1;
}
int main(int argc, char **argv) {
  lua_State *L = luaL_newstate();
  int i, round;
  capacity = argc > 1 ? atoi(argv[1]) : 60;
  if (!L || capacity < 1 || capacity > 120) return 2;
  luaL_openlibs(L);
  if (!lua_checkstack(L, capacity + 4)) return 3;
  for (i = 1; i <= capacity; ++i) lua_pushnumber(L, i);
  lua_pushcclosure(L, captured_sum, capacity);
  lua_setglobal(L, "captured_sum");
  for (round = 0; round < 10000; ++round) {
    lua_getglobal(L, "captured_sum");
    if (lua_pcall(L, 0, 1, 0)) return 4;
    if (lua_tonumber(L, -1) != capacity * (capacity + 1) / 2) return 5;
    lua_pop(L, 1);
    if (round % 251 == 0) lua_gc(L, LUA_GCCOLLECT, 0);
  }
  lua_close(L);
  printf("C_API_UPVALUES %d PASS\n", capacity);
  return 0;
}
