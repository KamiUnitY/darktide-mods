return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`kami_utilities` encountered an error loading the Darktide Mod Framework.")

		new_mod("kami_utilities", {
			mod_script       = "kami_utilities/scripts/mods/kami_utilities/kami_utilities",
			mod_data         = "kami_utilities/scripts/mods/kami_utilities/kami_utilities_data",
			mod_localization = "kami_utilities/scripts/mods/kami_utilities/kami_utilities_localization",
		})
	end,
	packages = {},
}
