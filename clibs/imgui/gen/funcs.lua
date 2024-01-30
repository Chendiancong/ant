local AntDir, meta = ...

local w <close> = assert(io.open(AntDir.."/clibs/imgui/imgui_lua_funcs.cpp", "wb"))

local function writeln(fmt, ...)
    w:write(string.format(fmt, ...))
    w:write "\n"
end

local write_arg = {}
local write_arg_ret = {}

write_arg["const char*"] = function(type_meta, status)
    local size_meta = status.args[status.i + 1]
    if size_meta then
        if size_meta.type and size_meta.type.declaration == "size_t" then
            assert(not type_meta.default_value)
            assert(size_meta.type.declaration == "size_t")
            status.idx = status.idx + 1
            status.i = status.i + 1
            writeln("    size_t %s = 0;", size_meta.name)
            writeln("    auto %s = luaL_checklstring(L, %d, &%s);", type_meta.name, status.idx, size_meta.name)
            status.arguments[#status.arguments+1] = type_meta.name
            status.arguments[#status.arguments+1] = size_meta.name
            return
        end
        if size_meta.is_varargs then
            status.idx = status.idx + 1
            status.i = status.i + 1
            writeln("    lua_pushcfunction(L, str_format);")
            writeln("    lua_insert(L, %d);", status.idx)
            writeln("    lua_call(L, lua_gettop(L) - %d, 1);", status.idx)
            writeln("    const char* _fmtstr = lua_tostring(L, -1);")
            status.arguments[#status.arguments+1] = [["%s"]]
            status.arguments[#status.arguments+1] = "_fmtstr"
            return
        end
    end
    status.idx = status.idx + 1
    status.arguments[#status.arguments+1] = type_meta.name
    if type_meta.default_value then
        writeln("    auto %s = luaL_optstring(L, %d, %s);", type_meta.name, status.idx, type_meta.default_value)
    else
        writeln("    auto %s = luaL_checkstring(L, %d);", type_meta.name, status.idx)
    end
end

write_arg["const void*"] = function(type_meta, status)
    local size_meta = status.args[status.i + 1]
    if size_meta and size_meta.type and size_meta.type.declaration == "size_t" then
        assert(not type_meta.default_value)
        assert(not size_meta.default_value)
        status.idx = status.idx + 1
        status.i = status.i + 1
        writeln("    size_t %s = 0;", size_meta.name)
        writeln("    auto %s = luaL_checklstring(L, %d, &%s);", type_meta.name, status.idx, size_meta.name)
        status.arguments[#status.arguments+1] = type_meta.name
        status.arguments[#status.arguments+1] = size_meta.name
        return
    end
    status.idx = status.idx + 1
    writeln("    auto %s = lua_touserdata(L, %d);", type_meta.name, status.idx)
    status.arguments[#status.arguments+1] = type_meta.name
end

write_arg["ImVec2"] = function(type_meta, status)
    if type_meta.default_value == nil then
        writeln("    auto %s = ImVec2 {", type_meta.name)
        writeln("        (float)luaL_checknumber(L, %d),", status.idx + 1)
        writeln("        (float)luaL_checknumber(L, %d),", status.idx + 2)
        writeln "    };"
    else
        assert(type_meta.default_value == "ImVec2(0.0f, 0.0f)" or type_meta.default_value == "ImVec2(0, 0)", type_meta.default_value)
        writeln("    auto %s = ImVec2 {", type_meta.name)
        writeln("        (float)luaL_optnumber(L, %d, 0.f),", status.idx + 1)
        writeln("        (float)luaL_optnumber(L, %d, 0.f),", status.idx + 2)
        writeln "    };"
    end
    status.arguments[#status.arguments+1] = type_meta.name
    status.idx = status.idx + 2
end

write_arg["ImVec4"] = function(type_meta, status)
    assert(type_meta.default_value == nil)
    writeln("    auto %s = ImVec4 {", type_meta.name)
    writeln("        (float)luaL_checknumber(L, %d),", status.idx + 1)
    writeln("        (float)luaL_checknumber(L, %d),", status.idx + 2)
    writeln("        (float)luaL_checknumber(L, %d),", status.idx + 3)
    writeln("        (float)luaL_checknumber(L, %d),", status.idx + 4)
    writeln "    };"
    status.arguments[#status.arguments+1] = type_meta.name
    status.idx = status.idx + 4
end

write_arg["float"] = function(type_meta, status)
    status.idx = status.idx + 1
    if type_meta.default_value then
        writeln("    auto %s = (float)luaL_optnumber(L, %d, %s);", type_meta.name, status.idx, type_meta.default_value)
    else
        writeln("    auto %s = (float)luaL_checknumber(L, %d);", type_meta.name, status.idx)
    end
    status.arguments[#status.arguments+1] = type_meta.name
end

write_arg["bool"] = function(type_meta, status)
    status.idx = status.idx + 1
    status.arguments[#status.arguments+1] = type_meta.name
    if type_meta.default_value then
        writeln("    auto %s = lua_isnoneornil(L, %d)? %s: !!lua_toboolean(L, %d);", type_meta.name, status.idx, type_meta.default_value, status.idx)
    else
        writeln("    auto %s = !!lua_toboolean(L, %d);", type_meta.name, status.idx)
    end
end

write_arg["bool*"] = function(type_meta, status)
    status.idx = status.idx + 1
    writeln("    bool has_%s = !lua_isnil(L, %d);", type_meta.name, status.idx)
    writeln("    bool %s = true;", type_meta.name)
    status.arguments[#status.arguments+1] = string.format("(has_%s? &%s: NULL)", type_meta.name, type_meta.name)
end

write_arg_ret["bool*"] = function(type_meta)
    writeln("    lua_pushboolean(L, has_%s || %s);", type_meta.name, type_meta.name)
    return 1
end

write_arg["size_t*"] = function(type_meta, status)
    status.idx = status.idx + 1
    writeln("    bool has_%s = !lua_isnil(L, %d);", type_meta.name, status.idx)
    writeln("    size_t %s = 0;", type_meta.name)
    status.arguments[#status.arguments+1] = string.format("(has_%s? &%s: NULL)", type_meta.name, type_meta.name)
end

write_arg_ret["size_t*"] = function(type_meta)
    writeln("    has_%s? lua_pushinteger(L, %s): lua_pushnil(L);", type_meta.name, type_meta.name)
    return 1
end

for n = 1, 4 do
    write_arg["int["..n.."]"] = function(type_meta, status)
        status.idx = status.idx + 1
        writeln("    luaL_checktype(L, %d, LUA_TTABLE);", status.idx)
        writeln("    int _%s_index = %d;", type_meta.name, status.idx)
        writeln("    int %s[%d] = {", type_meta.name, n)
        for i = 1, n do
            writeln("        (int)field_tointeger(L, %d, %d),", status.idx, i)
        end
        writeln "    };"
        status.arguments[#status.arguments+1] = type_meta.name
    end
    write_arg_ret["int["..n.."]"] = function(type_meta)
        writeln "    if (_retval) {"
        for i = 1, n do
            writeln("        lua_pushinteger(L, %s[%d]);", type_meta.name, i-1)
            writeln("        lua_seti(L, _%s_index, %d);", type_meta.name, i)
        end
        writeln "    };"
        return 0
    end
end
write_arg["int*"] = write_arg["int[1]"]
write_arg_ret["int*"] = write_arg_ret["int[1]"]

for n = 1, 4 do
    write_arg["float["..n.."]"] = function(type_meta, status)
        status.idx = status.idx + 1
        writeln("    luaL_checktype(L, %d, LUA_TTABLE);", status.idx)
        writeln("    int _%s_index = %d;", type_meta.name, status.idx)
        writeln("    float %s[%d] = {", type_meta.name, n)
        for i = 1, n do
            writeln("        (float)field_tonumber(L, %d, %d),", status.idx, i)
        end
        writeln "    };"
        status.arguments[#status.arguments+1] = type_meta.name
    end
    write_arg_ret["float["..n.."]"] = function(type_meta)
        writeln "    if (_retval) {"
        for i = 1, n do
            writeln("        lua_pushnumber(L, %s[%d]);", type_meta.name, i-1)
            writeln("        lua_seti(L, _%s_index, %d);", type_meta.name, i)
        end
        writeln "    };"
        return 0
    end
end
write_arg["float*"] = write_arg["float[1]"]
write_arg_ret["float*"] = write_arg_ret["float[1]"]

local write_ret = {}

write_ret["bool"] = function()
    writeln "    lua_pushboolean(L, _retval);"
    return 1
end

write_ret["float"] = function()
    writeln "    lua_pushnumber(L, _retval);"
    return 1
end

write_ret["double"] = function()
    writeln "    lua_pushnumber(L, _retval);"
    return 1
end

write_ret["const ImGuiPayload*"] = function()
    writeln "    if (_retval != NULL) {"
    writeln "        lua_pushlstring(L, (const char*)_retval->Data, _retval->DataSize);"
    writeln "    } else {"
    writeln "        lua_pushnil(L);"
    writeln "    }"
    return 1
end

write_ret["const char*"] = function()
    writeln "    lua_pushstring(L, _retval);"
    return 1
end

write_ret["ImVec2"] = function()
    writeln "    lua_pushnumber(L, _retval.x);"
    writeln "    lua_pushnumber(L, _retval.y);"
    return 2
end

write_ret["ImVec4"] = function()
    writeln "    lua_pushnumber(L, _retval.x);"
    writeln "    lua_pushnumber(L, _retval.y);"
    writeln "    lua_pushnumber(L, _retval.z);"
    writeln "    lua_pushnumber(L, _retval.w);"
    return 4
end

for _, type_name in ipairs {"int", "size_t", "ImU32", "ImGuiID", "ImGuiKeyChord"} do
    write_arg[type_name] = function(type_meta, status)
        status.idx = status.idx + 1
        if type_meta.default_value then
            writeln("    auto %s = (%s)luaL_optinteger(L, %d, %s);", type_meta.name, type_name, status.idx, type_meta.default_value)
        else
            writeln("    auto %s = (%s)luaL_checkinteger(L, %d);", type_meta.name, type_name, status.idx)
        end
        status.arguments[#status.arguments+1] = type_meta.name
    end
    write_ret[type_name] = function()
        writeln "    lua_pushinteger(L, _retval);"
        return 1
    end
end

for _, enums in ipairs(meta.enums) do
    if enums.conditionals then
        goto continue
    end
    local realname = enums.name:match "(.-)_?$"
    local function find_name(value)
        local v = math.tointeger(value)
        for _, element in ipairs(enums.elements) do
            if element.value == v then
                return element.name
            end
        end
        assert(false)
    end
    write_arg[realname] = function(type_meta, status)
        status.idx = status.idx + 1
        if type_meta.default_value then
            writeln("    auto %s = (%s)luaL_optinteger(L, %d, lua_Integer(%s));", type_meta.name, realname, status.idx, find_name(type_meta.default_value))
        else
            writeln("    auto %s = (%s)luaL_checkinteger(L, %d);", type_meta.name, realname, status.idx)
        end
        status.arguments[#status.arguments+1] = type_meta.name
    end
    write_ret[realname] = function()
        writeln "    lua_pushinteger(L, _retval);"
        return 1
    end
    ::continue::
end

local function write_func(func_meta)
    local realname = func_meta.name:match "^ImGui_([%w]+)$"
    writeln("static int %s(lua_State* L) {", realname)
    local status = {
        i = 1,
        args = func_meta.arguments,
        idx = 0,
        arguments = {},
    }
    while status.i <= #status.args do
        local type_meta = status.args[status.i]
        local wfunc = write_arg[type_meta.type.declaration]
        if not wfunc then
            error(string.format("`%s` undefined write arg func `%s`", func_meta.name, type_meta.type.declaration))
        end
        wfunc(type_meta, status)
        status.i = status.i + 1
    end
    if func_meta.return_type.declaration == "void" then
        writeln("    %s(%s);", func_meta.original_fully_qualified_name, table.concat(status.arguments, ", "))
        writeln "    return 0;"
    else
        local rfunc = write_ret[func_meta.return_type.declaration]
        if not rfunc then
            error(string.format("`%s` undefined write ret func `%s`", func_meta.name, func_meta.return_type.declaration))
        end
        writeln("    auto _retval = %s(%s);", func_meta.original_fully_qualified_name, table.concat(status.arguments, ", "))
        local nret = 0
        nret = nret + rfunc(func_meta.return_type)
        for _, type_meta in ipairs(func_meta.arguments) do
            if type_meta.type then
                local func = write_arg_ret[type_meta.type.declaration]
                if func then
                    nret = nret + func(type_meta)
                end
            end
        end
        writeln("    return %d;", nret)
    end
    writeln "}"
    writeln ""
    return realname
end

local allow = require "allow"

local function write_func_scope()
    local funcs = {}
    allow.init()
    for _, func_meta in ipairs(meta.functions) do
        if allow.query(func_meta) then
            funcs[#funcs+1] = write_func(func_meta)
        end
    end
    return funcs
end

writeln "//"
writeln "// Automatically generated file; DO NOT EDIT."
writeln "//"
writeln "#include <imgui.h>"
writeln "#include <lua.hpp>"
writeln ""
writeln "namespace imgui_lua {"
writeln ""
writeln "lua_CFunction str_format = NULL;"
writeln ""
writeln "static void find_str_format(lua_State* L) {"
writeln "    luaopen_string(L);"
writeln "    lua_getfield(L, -1, \"format\");"
writeln "    str_format = lua_tocfunction(L, -1);"
writeln "    lua_pop(L, 2);"
writeln "}"
writeln ""
writeln "static auto field_tointeger(lua_State* L, int idx, lua_Integer i) {"
writeln "    lua_geti(L, idx, i);"
writeln "    auto v = luaL_checknumber(L, -1);"
writeln "    lua_pop(L, 1);"
writeln "    return v;"
writeln "}"
writeln ""
writeln "static auto field_tonumber(lua_State* L, int idx, lua_Integer i) {"
writeln "    lua_geti(L, idx, i);"
writeln "    auto v = luaL_checknumber(L, -1);"
writeln "    lua_pop(L, 1);"
writeln "    return v;"
writeln "}"
writeln ""
local funcs = write_func_scope()
writeln "void init(lua_State* L) {"
writeln "    luaL_Reg funcs[] = {"
for _, func in ipairs(funcs) do
    writeln("        { %q, %s },", func, func)
end
writeln "        { NULL, NULL },"
writeln "    };"
writeln "    luaL_setfuncs(L, funcs, 0);"
writeln "    find_str_format(L);"
writeln "}"
writeln "}"
