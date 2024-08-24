return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`guarantee_special_action` encountered an error loading the Darktide Mod Framework.")

		new_mod("guarantee_special_action", {
			mod_script       = "guarantee_special_action/scripts/mods/guarantee_special_action/guarantee_special_action",
			mod_data         = "guarantee_special_action/scripts/mods/guarantee_special_action/guarantee_special_action_data",
			mod_localization = "guarantee_special_action/scripts/mods/guarantee_special_action/guarantee_special_action_localization",
		})
	end,
	load_before = {
		-- "ChatBlock", -- Already ordered by alphabetical order
	},
	load_after = {
		-- "ChatBlock", -- Already ordered by alphabetical order
		"modding_tools",
		"MultiBind",
		"ToggleAltFire",
		"weapon_customization",
		"weapon_customization_syn_edits",
		"weapon_customization_mt_stuff",
	},
	packages = {},
}
