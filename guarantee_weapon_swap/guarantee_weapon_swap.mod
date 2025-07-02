return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`guarantee_weapon_swap` encountered an error loading the Darktide Mod Framework.")

		new_mod("guarantee_weapon_swap", {
			mod_script       = "guarantee_weapon_swap/scripts/mods/guarantee_weapon_swap/guarantee_weapon_swap",
			mod_data         = "guarantee_weapon_swap/scripts/mods/guarantee_weapon_swap/guarantee_weapon_swap_data",
			mod_localization = "guarantee_weapon_swap/scripts/mods/guarantee_weapon_swap/guarantee_weapon_swap_localization",
		})
	end,
	load_after = {
		-- "ChatBlock", -- Already ordered by alphabetical order
		"modding_tools",
		"MultiBind",
		"Skitarius",
	},
	packages = {},
}
