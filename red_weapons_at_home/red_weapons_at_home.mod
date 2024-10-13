return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`red_weapons_at_home` encountered an error loading the Darktide Mod Framework.")

		new_mod("red_weapons_at_home", {
			mod_script       = "red_weapons_at_home/scripts/mods/red_weapons_at_home/red_weapons_at_home",
			mod_data         = "red_weapons_at_home/scripts/mods/red_weapons_at_home/red_weapons_at_home_data",
			mod_localization = "red_weapons_at_home/scripts/mods/red_weapons_at_home/red_weapons_at_home_localization",
		})
	end,
	load_after = {
		"modding_tools",
	},
	packages = {},
}
