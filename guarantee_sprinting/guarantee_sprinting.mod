return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`guarantee_sprinting` encountered an error loading the Darktide Mod Framework.")

		new_mod("guarantee_sprinting", {
			mod_script       = "guarantee_sprinting/scripts/mods/guarantee_sprinting/guarantee_sprinting",
			mod_data         = "guarantee_sprinting/scripts/mods/guarantee_sprinting/guarantee_sprinting_data",
			mod_localization = "guarantee_sprinting/scripts/mods/guarantee_sprinting/guarantee_sprinting_localization",
		})
	end,
	load_after = {
		"modding_tools",
		-- "ChatBlock", -- Already ordered by alphabetical order
		"MultiBind",
	},
	packages = {},
}
