return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`guarantee_better_sprinting` encountered an error loading the Darktide Mod Framework.")

		new_mod("guarantee_better_sprinting", {
			mod_script       = "guarantee_better_sprinting/scripts/mods/guarantee_better_sprinting/guarantee_better_sprinting",
			mod_data         = "guarantee_better_sprinting/scripts/mods/guarantee_better_sprinting/guarantee_better_sprinting_data",
			mod_localization = "guarantee_better_sprinting/scripts/mods/guarantee_better_sprinting/guarantee_better_sprinting_localization",
		})
	end,
	load_after = {
		"modding_tools",
		-- "ChatBlock", -- Already ordered by alphabetical order
		"MultiBind",
	},
	packages = {},
}
