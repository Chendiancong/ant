local runtime = import_package "ant.imguibase".runtime
runtime.start {
	policy = {
		"ant.animation|animation",
		"ant.animation|state_chain",
		"ant.animation|ozzmesh",
		"ant.animation|ozz_skinning",
		"ant.serialize|serialize",
		"ant.bullet|collider.capsule",
		"ant.render|render",
		"ant.render|name",
		"ant.render|directional_light",
		"ant.render|ambient_light",
	},
	system = {
		"ant.test.animation|init_loader",
		"ant.test.animation|init_gui",
	},
	pipeline = {
		"start",
		"timer",
		"widget",
		{"render", {
			"shadow_camera",
			"filter_primitive",
			"make_shadow",
			"debug_shadow",
			"cull",
			"render_commit",
			{"postprocess", {
				"bloom",
				"tonemapping",
				"combine_postprocess",
			}}
		}},
		{"ui", {
			"ui_start",
			"ui",
			"ui_end",
		}},
		"end_frame",
		"final",
	}
}
