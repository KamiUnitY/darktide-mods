return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`better_toggle_sprint` encountered an error loading the Darktide Mod Framework.")

		new_mod("better_toggle_sprint", {
			mod_script       = "better_toggle_sprint/scripts/mods/better_toggle_sprint/better_toggle_sprint",
			mod_data         = "better_toggle_sprint/scripts/mods/better_toggle_sprint/better_toggle_sprint_data",
			mod_localization = "better_toggle_sprint/scripts/mods/better_toggle_sprint/better_toggle_sprint_localization",
		})
	end,
	load_before = {
		"guarantee_weapon_swap",
		"guarantee_ability_activation",
	},
	load_after = {
		-- "ChatBlock", -- Already ordered by alphabetical order
		"modding_tools",
		"MultiBind",
	},
	packages = {},
}