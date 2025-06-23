local mod = get_mod("red_weapons_at_home")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id  = "gadget_settings",
				type        = "group",
				sub_widgets = {
					{
						setting_id = "gadget_wound_required_expertise",
						type = "numeric",
						default_value = 400,
						range = { 0, 430 }
					},
				}
			},
			{
				setting_id  = "rarity_color_6",
				type        = "group",
				sub_widgets = {
					{
						setting_id = "rarity_color_6_red",
						type = "numeric",
						default_value = 210,
						range = {0, 255}
					},
					{
						setting_id = "rarity_color_6_green",
						type = "numeric",
						default_value = 30,
						range = {0, 255}
					},
					{
						setting_id = "rarity_color_6_blue",
						type = "numeric",
						default_value = 40,
						range = {0, 255}
					}
				}
			},
		}
	}
}
