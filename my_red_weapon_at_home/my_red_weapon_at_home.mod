return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`my_red_weapon_at_home` encountered an error loading the Darktide Mod Framework.")

		new_mod("my_red_weapon_at_home", {
			mod_script       = "my_red_weapon_at_home/scripts/mods/my_red_weapon_at_home/my_red_weapon_at_home",
			mod_data         = "my_red_weapon_at_home/scripts/mods/my_red_weapon_at_home/my_red_weapon_at_home_data",
			mod_localization = "my_red_weapon_at_home/scripts/mods/my_red_weapon_at_home/my_red_weapon_at_home_localization",
		})
	end,
	load_after = {
		"modding_tools",
	},
	packages = {},
}
