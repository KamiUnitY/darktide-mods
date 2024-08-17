return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`hybrid_sprint` encountered an error loading the Darktide Mod Framework.")

		new_mod("hybrid_sprint", {
			mod_script       = "hybrid_sprint/scripts/mods/hybrid_sprint/hybrid_sprint",
			mod_data         = "hybrid_sprint/scripts/mods/hybrid_sprint/hybrid_sprint_data",
			mod_localization = "hybrid_sprint/scripts/mods/hybrid_sprint/hybrid_sprint_localization",
		})
	end,
	load_after = {
		-- "ChatBlock", -- Already ordered by alphabetical order
		"modding_tools",
		"MultiBind",
		"ToggleAltFire",
	},
	packages = {},
}