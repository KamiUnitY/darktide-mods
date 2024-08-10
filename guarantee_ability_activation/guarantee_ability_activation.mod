return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`guarantee_ability_activation` encountered an error loading the Darktide Mod Framework.")

		new_mod("guarantee_ability_activation", {
			mod_script       = "guarantee_ability_activation/scripts/mods/guarantee_ability_activation/guarantee_ability_activation",
			mod_data         = "guarantee_ability_activation/scripts/mods/guarantee_ability_activation/guarantee_ability_activation_data",
			mod_localization = "guarantee_ability_activation/scripts/mods/guarantee_ability_activation/guarantee_ability_activation_localization",
		})
	end,
	load_after = {
		-- "ChatBlock", -- Already ordered by alphabetical order
		"modding_tools",
		"MultiBind",
	},
	packages = {},
}
