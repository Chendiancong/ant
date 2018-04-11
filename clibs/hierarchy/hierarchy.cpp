extern "C" {
#define LUA_LIB
#include "lua.h"
#include "lauxlib.h"
}

#include <ozz/animation/offline/raw_skeleton.h>
#include <cstring>

using namespace ozz::animation::offline;

struct hierarchy_tree {
	RawSkeleton * skl;
};

struct hierarchy {
	RawSkeleton::Joint *node;
};

static int
ldelhtree(lua_State *L) {
	struct hierarchy_tree * tree = (struct hierarchy_tree *)lua_touserdata(L, 1);
	delete tree->skl;
	tree->skl = NULL;
	return 0;
}

RawSkeleton::Joint::Children *
get_children(lua_State *L, int index) {
	struct hierarchy * node = (struct hierarchy *)lua_touserdata(L, index);
	if (node->node == NULL) {
		// It's root
		if (lua_getuservalue(L, 1) != LUA_TTABLE) {
			luaL_error(L, "Missing cache");
		}
		if (lua_geti(L, -1, 0) != LUA_TUSERDATA) {
			luaL_error(L, "Missing root in the cache");
		}
		struct hierarchy_tree * tree = (struct hierarchy_tree *)lua_touserdata(L, -1);
		lua_pop(L, 2);
		return &tree->skl->roots;
	} else {
		return &node->node->children;
	}
}

static int
lhnodechildren(lua_State *L) {
	RawSkeleton::Joint::Children *children = get_children(L, 1);
	lua_pushinteger(L, children->size());
	return 1;
}

static void
change_property(lua_State *L, RawSkeleton::Joint * node, const char * p, int value_index) {
	if (strcmp(p, "name") == 0) {
		const char * v = luaL_checkstring(L, value_index);
		node->name = v;
	} else {
		luaL_error(L, "Invalid property %s", p);
	}
}

static int
get_property(lua_State *L, RawSkeleton::Joint * node, const char * p) {
	if (strcmp(p, "name") == 0) {
		lua_pushstring(L, node->name.c_str());
		return 1;
	} else {
		return luaL_error(L, "Invalid property %s", p);
	}
}

static void
set_properties(lua_State *L, RawSkeleton::Joint * node, int values) {
	luaL_checktype(L, values, LUA_TTABLE);
	lua_pushnil(L);
	while (lua_next(L, values) != 0) {
		const char * p = luaL_checkstring(L, -2);
		change_property(L, node, p, -1);
		lua_pop(L, 1);
	}
}

static void
change_addr(lua_State *L, int cache_index, RawSkeleton::Joint *old_ptr, RawSkeleton::Joint *new_ptr) {
	if (lua_rawgetp(L, cache_index, (void *)old_ptr) == LUA_TUSERDATA) {
		struct hierarchy *h = (struct hierarchy *)lua_touserdata(L, -1);
		h->node = new_ptr;
		lua_rawsetp(L, cache_index, (void *)new_ptr);
		lua_pushnil(L);
		lua_rawsetp(L, cache_index, (void *)old_ptr);
	} else {
		lua_pop(L, 1);
	}
}

static void
expand_children(lua_State *L, int index, RawSkeleton::Joint::Children *c, int n) {
	int old_size = c->size();
	if (old_size == 0) {
		c->resize(n);
		return;
	}
	RawSkeleton::Joint *old_ptr = &c->at(0);
	c->resize(n);
	RawSkeleton::Joint *new_ptr = &c->at(0);
	if (old_ptr == new_ptr) {
		return;
	}
	if (lua_getuservalue(L, index) != LUA_TTABLE) {
		luaL_error(L, "Missing cache");
	}
	int cache_index = lua_gettop(L);
	int i;
	for (i=0;i<old_size;i++) {
		change_addr(L, cache_index, old_ptr+i, new_ptr+i);
	}
	lua_pop(L, 1);
}

static void
remove_child(lua_State *L, int index, RawSkeleton::Joint::Children * c, int child) {
	if (lua_getuservalue(L, index) != LUA_TTABLE) {
		luaL_error(L, "Missing cache");
	}
	int cache_index = lua_gettop(L);
	RawSkeleton::Joint *node = &c->at(child);
	if (lua_rawgetp(L, cache_index, (void *)node) == LUA_TUSERDATA) {
		struct hierarchy *h = (struct hierarchy *)lua_touserdata(L, -1);
		h->node = NULL;
		lua_pushnil(L);
		lua_setuservalue(L, -2);
	}
	lua_pop(L, 1);
	lua_pushnil(L);
	lua_rawsetp(L, cache_index, (void *)node);

	int size = c->size();
	int i;
	for (i=child+1;i<size;i++) {
		node = &c->at(i);
		change_addr(L, cache_index, node, node-1);
	}
	c->erase(c->begin() + child);
}

static int
lhnodeset(lua_State *L) {
	int key = lua_type(L, 2);
	if (key == LUA_TNUMBER) {
		// new child or change child
		int n = (int)lua_tointeger(L, 2);
		if (n <= 0) {
			return luaL_error(L, "Invalid children index %f", lua_tonumber(L, 2));
		}
		RawSkeleton::Joint::Children * c = get_children(L, 1);
		int size = c->size();
		if (n > size) {
			if (n == size + 1) {
				// new child
				expand_children(L, 1, c, n);
			} else {
				return luaL_error(L, "Out of range %d/%d", n, size);
			}
		}
		if (lua_isnil(L, 3)) {
			// remove child
			remove_child(L, 1, c, n-1);
		} else {
			RawSkeleton::Joint *node = &c->at(n-1);
			set_properties(L, node, 3);
		}
	} else if (key == LUA_TSTRING) {
		// change name or transform
		struct hierarchy * h = (struct hierarchy *)lua_touserdata(L,1);
		const char * property = lua_tostring(L, 2);
		RawSkeleton::Joint * node = h->node;
		if (node == NULL) {
			return luaL_error(L, "Root has no property");
		}
		change_property(L, node, property, 3);
	} else {
		return luaL_error(L, "Invalid key type %s", lua_typename(L, key));
	}
	return 0;	
}

static int
lhnodeget(lua_State *L) {
	struct hierarchy * h = (struct hierarchy *)lua_touserdata(L,1);
	RawSkeleton::Joint * node = h->node;
	int keytype = lua_type(L, 2);
	if (keytype == LUA_TSTRING) {
		if (node == NULL) {
			return luaL_error(L, "Invalid node");
		}
		const char * p = luaL_checkstring(L, 2);
		return get_property(L, node, p);
	} else if (keytype == LUA_TNUMBER) {
		int n = (int)lua_tointeger(L, 2);
		if (n <= 0) {
			return luaL_error(L, "Invalid children index %f", lua_tonumber(L, 2));
		}
		RawSkeleton::Joint::Children * c = get_children(L, 1);
		int size = c->size();
		if (n > size) {
			return 0;
		}
		RawSkeleton::Joint *node = &c->at(n-1);
		if (lua_getuservalue(L, 1) != LUA_TTABLE) {
			return luaL_error(L, "Missing cache");
		}
		if (lua_rawgetp(L, -1, (void *)node) == LUA_TUSERDATA) {
			return 1;
		}
		lua_pop(L, 1);
		struct hierarchy * h = (struct hierarchy *)lua_newuserdata(L, sizeof(*node));
		h->node = node;
		luaL_getmetatable(L, "HIERARCHY_NODE");
		lua_setmetatable(L, -2);
		lua_pushvalue(L, -1);
		// HIERARCHY_CACHE, HIERARCHY_NODE, HIERARCHY_NODE
		lua_rawsetp(L, -3, (void *)node);
		return 1;
	} else {
		return luaL_error(L, "Invalid key type %s", lua_typename(L, keytype));
	}
}

static int
lnewhierarchy(lua_State *L) {
	struct hierarchy * node = (struct hierarchy *)lua_newuserdata(L, sizeof(*node));
	node->node = NULL;
	luaL_getmetatable(L, "HIERARCHY_NODE");
	lua_setmetatable(L, -2);

	// stack: HIERARCHY_NODE

	struct hierarchy_tree * tree = (struct hierarchy_tree *)lua_newuserdata(L, sizeof(*tree));
	tree->skl = new RawSkeleton;
	if (luaL_newmetatable(L, "HIERARCHY_TREE")) {
		lua_pushcfunction(L, ldelhtree);
		lua_setfield(L, -2, "__gc");
	}
	lua_setmetatable(L, -2);

	// stack: HIERARCHY_NODE HIERARCHY_TREE

	lua_newtable(L);
	if (luaL_newmetatable(L, "HIERARCHY_CACHE")) {
		lua_pushstring(L, "kv");
		lua_setfield(L, -2, "__mode");
	}
	lua_setmetatable(L, -2);

	// stack: HIERARCHY_NODE HIERARCHY_TREE HIERARCHY_CACHE

	lua_pushvalue(L, -2);
	lua_seti(L, -2, 0);	// ref tree object

	lua_pushvalue(L, -1);
	lua_setuservalue(L, -3);	// HIERARCHY_CACHE -> uv of HIERARCHY_TREE
	lua_setuservalue(L, -3);	// HIERARCHY_CACHE -> uv of HIERARCHY_NODE

	// stack: HIERARCHY_NODE HIERARCHY_TREE

	lua_pop(L, 1);
	
	// return HIERARCHY_NODE
	return 1;
}

extern "C" {

LUAMOD_API int
luaopen_hierarchy(lua_State *L) {
	luaL_checkversion(L);
	luaL_newmetatable(L, "HIERARCHY_NODE");
	lua_pushcfunction(L, lhnodeset);
	lua_setfield(L, -2, "__newindex");
	lua_pushcfunction(L, lhnodeget);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, lhnodechildren);
	lua_setfield(L, -2, "__len");
	
	luaL_Reg l[] = {
		{ "new", lnewhierarchy },
		{ NULL, NULL },
	};
	luaL_newlib(L, l);
	return 1;
}

}
