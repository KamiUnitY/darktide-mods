local mod = get_mod("upside_down_name")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "angle",
				type = "numeric",
				default_value = 180,
				range = { -180, 180 },
			},
		},
	},
}
