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
				setting_id = "start_sprint_buffer",
				type            = "numeric",
				default_value   = 1.0,
				range           = { 0.0, 5.0 },
				decimals_number = 1,
			},
			{
				setting_id = "enable_dodge_on_diagonal_sprint",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "enable_keep_sprint_after_weapon_action",
				type = "checkbox",
				default_value = true,
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
