return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`guarantee_tactical_action` encountered an error loading the Darktide Mod Framework.")

		new_mod("guarantee_tactical_action", {
			mod_script       = "guarantee_tactical_action/scripts/mods/guarantee_tactical_action/guarantee_tactical_action",
			mod_data         = "guarantee_tactical_action/scripts/mods/guarantee_tactical_action/guarantee_tactical_action_data",
			mod_localization = "guarantee_tactical_action/scripts/mods/guarantee_tactical_action/guarantee_tactical_action_localization",
		})
	end,
	load_after = {
		-- "ChatBlock", -- Already ordered by alphabetical order
		"modding_tools",
		"MultiBind",
	},
	packages = {},
}
