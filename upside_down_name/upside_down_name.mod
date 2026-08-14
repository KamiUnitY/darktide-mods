return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`upside_down_name` encountered an error loading the Darktide Mod Framework.")

		new_mod("upside_down_name", {
			mod_script = "upside_down_name/scripts/mods/upside_down_name/upside_down_name",
			mod_data = "upside_down_name/scripts/mods/upside_down_name/upside_down_name_data",
			mod_localization = "upside_down_name/scripts/mods/upside_down_name/upside_down_name_localization",
		})
	end,
	packages = {},
}
