local mod = get_mod("my_red_weapon_at_home")
local modding_tools = get_mod("modding_tools")

local Items = require("scripts/utilities/items")
local UIFonts = require("scripts/managers/ui/ui_fonts")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UISettings = require("scripts/settings/ui/ui_settings")
local WeaponTemplate = require("scripts/utilities/weapon/weapon_template")

--------------------------
-- MOD SETTINGS CACHING --
--------------------------

mod.settings = {
    enable_debug_modding_tools = mod:get("enable_debug_modding_tools"),
}

mod.on_setting_changed = function(setting_id)
    mod.settings[setting_id] = mod:get(setting_id)
end

------------------------
-- ON ALL MODS LOADED --
------------------------

mod.on_all_mods_loaded = function()
    -- WATCHER
    -- modding_tools:watch("benchmark_input", mod, "benchmark_input")
end

-------------------------
-- MODDING TOOLS DEBUG --
-------------------------

local debug = {
    is_enabled = function(self)
        return mod.settings["enable_debug_modding_tools"] and modding_tools and modding_tools:is_enabled()
    end,
    print = function(self, text)
        pcall(function() modding_tools:console_print(text) end)
    end,
    print_mod = function(self, text)
        if self:is_enabled() then
            self:print(mod:localize("mod_name") .. ": " .. text)
        end
    end,
}

---------------
-- ITEM GRID --
---------------

mod:hook("ViewElementGrid", "_create_entry_widget_from_config", function(func, self, ...)
	local widget, alignment_widget = func(self, ...)

	if not widget or (widget.type ~= "item" and widget.type ~= "store_item") then
		return widget, alignment_widget
	end

	local item = widget.content and widget.content.element and widget.content.element.item
	if not item then
		return widget, alignment_widget
	end

	local rarity = item.__master_item.rarity
	local level = item.__master_item.baseItemLevel

	if rarity == 5 and level >= 380 then
		local bg_color = widget.style.background_gradient.color
		local tag_color = widget.style.rarity_tag.color
		local name_color = widget.style.rarity_name.text_color

		bg_color[2], bg_color[3], bg_color[4] = 220, 20, 20
		tag_color[2], tag_color[3], tag_color[4] = 220, 20, 20
		name_color[2], name_color[3], name_color[4] = 220, 20, 20

		widget.content.rarity_name = "Relic"
	end

	return widget, alignment_widget
end)

mod:hook_safe("InventoryView", "_update_blueprint_widgets", function(self, ...)
    for _, widget in pairs(self._loadout_widgets) do
		if not widget or (widget.type ~= "item_slot") then
            break
        end

        local item = widget.content and widget.content.item
        if not item then
            break
        end

        local rarity = item.__master_item.rarity
        local level = item.__master_item.baseItemLevel

        if rarity == 5 and level >= 380 then
            local bg_color = widget.style.background_gradient.color
            local tag_color = widget.style.rarity_tag.color
            local name_color = widget.style.rarity_name.text_color

            bg_color[2], bg_color[3], bg_color[4] = 220, 20, 20
            tag_color[2], tag_color[3], tag_color[4] = 220, 20, 20
            name_color[2], name_color[3], name_color[4] = 220, 20, 20

            widget.content.rarity_name = "Relic"
        end
	end
end)

mod:hook(package.loaded, "scripts/ui/view_content_blueprints/item_stats_blueprints", function(generate_blueprints_function, grid_size, optional_item)
    local blueprints = generate_blueprints_function(grid_size, optional_item)
	if not blueprints.weapon_header or not blueprints.weapon_header.init then
		return blueprints
	end

    --#region FATSHARK CODE
    local function _style_text_height(text, style, ui_renderer)
        local text_font_data = UIFonts.data_by_type(style.font_type)
        local text_font = text_font_data.path
        local text_size = style.size
        local use_max_extents = true
        local text_options = UIFonts.get_font_options_by_style(style)
        local _, text_height = UIRenderer.text_size(ui_renderer, text, style.font_type, style.font_size, text_size, text_options, use_max_extents)

        return text_height
    end

    local weapon_sub_display_name_style = table.clone(UIFontSettings.header_3)
    local weapon_display_name_style = table.clone(UIFontSettings.header_3)
    local weapon_rarity_name_style = table.clone(weapon_sub_display_name_style)
    --#endregion

    blueprints.weapon_header.init = function (parent, widget, element, callback_name, _, ui_renderer)
        --#region FATSHARK CODE
        local content = widget.content
        local style = widget.style
        content.element = element

        local item = element.item
        local sub_display_name = Items.weapon_card_sub_display_name(item)
        local rarity_name = Items.sub_display_name(item, nil, true)

        content.sub_display_name = sub_display_name
        content.rarity_name = rarity_name
        content.icon = item.hud_icon or "content/ui/materials/icons/weapons/hud/combat_blade_01"

        local rarity_name_style = style.rarity_name
        local sub_display_name_text_height = _style_text_height(sub_display_name, weapon_display_name_style, ui_renderer)

        rarity_name_style.offset[2] = rarity_name_style.offset[2] + sub_display_name_text_height

        local weapon_template = WeaponTemplate.weapon_template_from_item(item)
        local displayed_attacks = weapon_template.displayed_attacks
        local weapon_special = displayed_attacks.special

        if weapon_special then
            content.weapon_special_icon = UISettings.weapon_action_type_icons[weapon_special.type]
            content.weapon_special_text = Localize(weapon_special.display_name)
            style.weapon_special_icon.visible = true
            style.weapon_special_text.visible = true

            local rarity_name_text_height = _style_text_height(rarity_name, weapon_rarity_name_style, ui_renderer)

            style.weapon_special_icon.offset[2] = style.weapon_special_icon.offset[2] + sub_display_name_text_height + rarity_name_text_height
            style.weapon_special_text.offset[2] = style.weapon_special_text.offset[2] + sub_display_name_text_height + rarity_name_text_height
        else
            style.weapon_special_icon.visible = false
            style.weapon_special_text.visible = false
        end

        local rarity_color, rarity_color_dark = Items.rarity_color(item)

        style.gradient_background.color = table.clone(rarity_color_dark)
        style.gradient_background.material_values = {
            invert = 1,
        }
        style.background.visible = not not element.add_background
        style.rarity_name.text_color = table.clone(rarity_color)
        --#endregion

        local rarity = item.__master_item.rarity
        local level = item.__master_item.baseItemLevel

        if rarity == 5 and level >= 380 then
            local bg_color = widget.style.gradient_background.color
            local name_color = widget.style.rarity_name.text_color

            bg_color[2], bg_color[3], bg_color[4] = 120, 20, 20
            name_color[2], name_color[3], name_color[4] = 220, 20, 20

            widget.content.rarity_name = "Relic"
        end
    end

    return blueprints
end)
