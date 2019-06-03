local native    = require "window.native"
local window    = require "window"
local imgui     = require "imgui_wrap"
local bgfx      = require "bgfx"
local platform = require "platform"
local rhwi      = import_package "ant.render".hardware_interface
local editor    = import_package "ant.editor"
local task      = editor.task
local gui_mgr   = require "gui_mgr"
local gui_input = require "gui_input"
local font = imgui.font
local Font = platform.font
local gui_main  = {}
local attribs   = {}
local main = nil

local function Shader(shader)
    local shader_mgr = import_package "ant.render".shader_mgr
    local uniforms = {}
    shader.prog = shader_mgr.programLoad(assert(shader.vs), assert(shader.fs), uniforms)
    assert(shader.prog ~= nil)
    shader.uniforms = uniforms
    return shader
end


function gui_main.init(nwh, context, width, height)
    rhwi.init {
        nwh = nwh,
        context = context,
    --  renderer = "DIRECT3D9",
    --  renderer = "OPENGL",
        width = width,
        height = height,
    --  reset = "v",
    }

    local ocornut_imgui = Shader {
        vs = "//ant.imgui/shader/vs_ocornut_imgui",
        fs = "//ant.imgui/shader/fs_ocornut_imgui",
    }
    local imgui_image = Shader {
        vs = "//ant.imgui/shader/vs_imgui_image",
        fs = "//ant.imgui/shader/fs_imgui_image",
    }

    imgui.create(attribs.font_size)
    imgui.viewid(255);
    imgui.program(
        ocornut_imgui.prog,
        imgui_image.prog,
        ocornut_imgui.uniforms.s_tex.handle,
        imgui_image.uniforms.u_imageLodEnabled.handle
    )
    imgui.resize(width, height)
    imgui.keymap(native.keymap)

    bgfx.set_view_rect(0, 0, 0, width, height)
    bgfx.set_view_clear(0, "CD", 0x303030ff, 1, 0)

    -- bgfx.set_view_rect(1, 200, 200, width-100, height-100)
    -- bgfx.set_view_clear(1, "CD", 0xffff00ff, 1, 0)
    --bgfx.set_debug "ST"
    font.Create {
        platform.OS == "Windows"
        and { Font "黑体" ,    18, "\x20\x00\xFF\xFF\x00"}
        or  { Font "华文细黑" , 18, "\x20\x00\xFF\xFF\x00"},
    }
    if main.init then
        main.init(nwh, context, width, height)
    end
    

end

function gui_main.size(width,height,type)
    print("callback.size",width,height,type)
    imgui.resize(width,height)
    rhwi.reset(nil, width, height)
    bgfx.set_view_rect(0, 0, 0, width, height)
    if main.size then
        main.size(width,height,type)
    end
end

function gui_main.char(code)
    imgui.input_char(code)
end

function gui_main.error(err)
    print(err)
    if main.error then
        main.error(err)
    end
end

function gui_main.mouse_move(x,y)
    imgui.mouse_move(x,y)
    gui_input.mouse_move(x,y)
end

function gui_main.mouse_wheel(x,y,delta)
    imgui.mouse_wheel(x,y,delta)
    gui_input.mouse_wheel(x,y,delta)

end

function gui_main.mouse_click(x, y, what, pressed)
    -- print("mouse_click",what,pressed)
    imgui.mouse_click(x, y, what, pressed)
    gui_input.mouse_click(x, y, what, pressed)
end

function gui_main.keyboard(key, press, state)
    imgui.key_state(key, press, state)
    print("key",key,press,state)
    gui_input.keyboard(key, press, state)
end

local os = require "os"
local thread = require "thread"
local last_update = os.clock()
local FRAME_TIME = 1/60
local next_update = last_update + FRAME_TIME
function gui_main.update()
    local now = os.clock()
    local delta = now - last_update
    last_update = now
    _update(delta+0.00000001)
    local after_update = os.clock()
    local wait = next_update-after_update
    if wait >0 then
        thread.sleep(wait)
    end
    next_update = next_update + FRAME_TIME
end

function _update(delta)
    gui_mgr.update(delta)
    gui_input.clean()
    rhwi.ui_frame()
    bgfx.touch(0)
    bgfx.touch(1)
    task.update()
    --todo delete this bgfx code
    rhwi.on_update_end()
    if main.update then
        main.update()
    end
end

function gui_main.exit()
    print("Exit")
    imgui.destroy()
    rhwi.shutdown()
    if main.exit then
        main.exit()
    end
end

local function run(m,args)
    main = m
    window.register(gui_main)
    native.create(args.screen_width or 1024, 
        args.screen_width or 728, 
        args.name or "Ant")
    native.mainloop()
end

return {run = run}


