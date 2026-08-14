return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`curved_hud` encountered an error loading the Darktide Mod Framework.")

		new_mod("curved_hud", {
			mod_script = "curved_hud/scripts/mods/curved_hud/curved_hud",
			mod_data = "curved_hud/scripts/mods/curved_hud/curved_hud_data",
			mod_localization = "curved_hud/scripts/mods/curved_hud/curved_hud_localization",
		})
	end,
	packages = {},
}
