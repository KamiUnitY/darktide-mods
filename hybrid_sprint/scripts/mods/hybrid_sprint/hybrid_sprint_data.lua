local mod = get_mod("hybrid_sprint")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "enable_hold_to_sprint",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id  = "debug_group",
				type        = "group",
				sub_widgets = {
					{
						setting_id = "enable_debug_modding_tools",
						type = "checkbox",
						default_value = false,
					},
				}
			},
		},
	}
}
