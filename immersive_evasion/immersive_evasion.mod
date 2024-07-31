return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`immersive_evasion` encountered an error loading the Darktide Mod Framework.")

		new_mod("immersive_evasion", {
			mod_script       = "immersive_evasion/scripts/mods/immersive_evasion/immersive_evasion",
			mod_data         = "immersive_evasion/scripts/mods/immersive_evasion/immersive_evasion_data",
			mod_localization = "immersive_evasion/scripts/mods/immersive_evasion/immersive_evasion_localization",
		})
	end,
	load_after = {
		"modding_tools",
	},
	packages = {},
}
