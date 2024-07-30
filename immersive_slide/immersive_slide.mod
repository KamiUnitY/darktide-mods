return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`immersive_slide` encountered an error loading the Darktide Mod Framework.")

		new_mod("immersive_slide", {
			mod_script       = "immersive_slide/scripts/mods/immersive_slide/immersive_slide",
			mod_data         = "immersive_slide/scripts/mods/immersive_slide/immersive_slide_data",
			mod_localization = "immersive_slide/scripts/mods/immersive_slide/immersive_slide_localization",
		})
	end,
	load_after = {
		"modding_tools",
	},
	packages = {},
}
