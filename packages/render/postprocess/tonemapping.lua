local ecs = ...
local world = ecs.world

local setting		= import_package "ant.settings".setting

local viewidmgr = require "viewid_mgr"
local fbmgr     = require "framebuffer_mgr"
local tm_sys    = ecs.system "tonemapping_system"

local ipp       = world:interface "ant.render|postprocess"

function tm_sys:post_init()
    local sd = setting:data()
    local hdrsetting = sd.graphic.hdr
    if hdrsetting.enable then
        local main_fbidx = fbmgr.get_fb_idx(viewidmgr.get "main_view")

        local w, h = ipp.main_rb_size(main_fbidx)
        ipp.add_technique {
                name = "tonemapping",
                passes = {
                    ipp.create_pass(
                        "/pkg/ant.resources/materials/postprocess/tonemapping.material",
                    {
                        view_rect = {x=0, y=0, w=w, h=h},
                        clear_state = {clear=""},
                        fb_idx = main_fbidx,
                    },
                    ipp.get_rbhandle(main_fbidx, 1),
                    "tonemapping_main")
                }
            }
    end
end