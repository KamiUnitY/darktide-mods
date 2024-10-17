-- Red Weapons at Home by KamiUnitY. Ver. 1.1.0

local mod = get_mod("red_weapons_at_home")
local modding_tools = get_mod("modding_tools")

local Items = require("scripts/utilities/items")
local MasterItems = require("scripts/backend/master_items")
local BuffTemplates = require("scripts/settings/buff/buff_templates")
local ConstantElementNotificationFeedSettings = require("scripts/ui/constant_elements/elements/notification_feed/constant_element_notification_feed_settings")

---------------
-- CONSTANTS --
---------------

local MAX_EXPERTISE_LEVEL = Items.max_expertise_level()

local COLOR = {255, 210, 30, 30}
local COLOR_DARK = {255, 120, 20, 20}

local TRAIT_BUFF_MAPPING = {
	gadget_stamina_increase           = "stamina_modifier",
	gadget_innate_toughness_increase  = "toughness_bonus",
	gadget_innate_health_increase     = "max_health_modifier",
	gadget_innate_max_wounds_increase = "extra_max_amount_of_wounds",
}

local TRAIT_MAX_VALUE = {
	gadget_stamina_increase           = 3,
	gadget_innate_toughness_increase  = 17,
	gadget_innate_health_increase     = 21,
	gadget_innate_max_wounds_increase = 1,
}

-------------------------
-- MODDING TOOLS DEBUG --
-------------------------

local debug = {
    is_enabled = function(self)
        return modding_tools and modding_tools:is_enabled()
    end,
    print = function(self, text)
        pcall(function() modding_tools:console_print(text) end)
    end,
}

---------------
-- UTILITIES --
---------------

local function _get_lerp_stepped_value(range, lerp_value)
	local min = 1
	local max = #range
	local lerped_value = math.lerp(min, max, lerp_value)
	local index = math.round(lerped_value)
	local value = range[index]
	return value
end

local function get_trait_data(id, value)
	local master = MasterItems.get_item(id)
	local trait = master.trait
	local output = 0

	local template = BuffTemplates[trait]
	if not template then
		return output
	end

	local localization_info = template.localization_info
	if not localization_info then
		return output
	end

	local buff_name = TRAIT_BUFF_MAPPING[trait]
	local template_stat_buffs = template.stat_buffs or template.lerped_stat_buffs
	if template_stat_buffs then
		local buff = template_stat_buffs[buff_name]
		if template.lerped_stat_buffs then
			local lerp_value_func = buff.lerp_value_func or math.lerp
			output = lerp_value_func(buff.min, buff.max, value)
		elseif template.class_name == "stepped_range_buff" then
			output = _get_lerp_stepped_value(buff, value)
		else
			output = buff
		end
		local show_as = localization_info[buff_name]
		if show_as and show_as == "percentage" then
			output = math.round(output * 100)
		end
	end
	return trait, output
end

local function is_sainted_item(item)
    local expertise_level_text = Items.expertise_level(item, true)
    local expertise_level = type(expertise_level_text) == "string" and tonumber(expertise_level_text)

    if item and item.rarity == 5 and expertise_level then
        if item.item_type == "GADGET" then
            local trait = item.traits[1]
            local trait_type, trait_value = get_trait_data(trait.id, trait.value)
            return expertise_level >= 400 and trait_value >= TRAIT_MAX_VALUE[trait_type]
        else
            return expertise_level == MAX_EXPERTISE_LEVEL
        end
    end

    return false
end

local function apply_sainted_theme(widget, type, item)
    local style = widget.style

    if style.rarity_tag then
        style.rarity_tag.color = table.clone(COLOR)
    end
    if style.background_gradient then
        style.background_gradient.color = table.clone(COLOR)
    end
    if style.gradient_background then
        style.gradient_background.color = table.clone(COLOR_DARK)
    end

    if item.item_type == "GADGET" then
        if type == "TOOLTIP" then
            if style.background then
                style.background.color = table.clone(COLOR)
            end
            if style.display_name then
                style.display_name.text_color = table.clone(COLOR)
            end
        end
        if style.sub_display_name then
            style.sub_display_name.text_color = table.clone(COLOR)
        end
        widget.content.sub_display_name = Localize("loc_item_weapon_rarity_6")
    else
        if style.rarity_name then
            style.rarity_name.text_color = table.clone(COLOR)
        end
        widget.content.rarity_name = Localize("loc_item_weapon_rarity_6")
    end
end

---------------
-- ITEM GRID --
---------------

mod:hook("ViewElementGrid", "_create_entry_widget_from_config", function(func, self, ...)
    local widget, alignment_widget = func(self, ...)

    if widget and (widget.type == "item" or widget.type == "store_item") then
        local item = widget.content and widget.content.element and widget.content.element.item
        if is_sainted_item(item) then
            apply_sainted_theme(widget, "GRID", item)
        end
    end

    return widget, alignment_widget
end)

------------------
-- ITEM TOOLTIP --
------------------

require("scripts/ui/view_content_blueprints/item_stats_blueprints")
mod:hook(package.loaded, "scripts/ui/view_content_blueprints/item_stats_blueprints", function(func, ...)
    local blueprints = func(...)

    local _weapon_header_init = blueprints.weapon_header.init
    blueprints.weapon_header.init = function(parent, widget, element, callback_name, _, ui_renderer)
        _weapon_header_init(parent, widget, element, callback_name, _, ui_renderer)

        local item = element.item
        if is_sainted_item(item) then
            apply_sainted_theme(widget, "TOOLTIP", item)
        end
    end

    local _extended_weapon_stats_header_init = blueprints.extended_weapon_stats_header.init
    blueprints.extended_weapon_stats_header.init = function(parent, widget, element, callback_name)
        _extended_weapon_stats_header_init(parent, widget, element, callback_name)

        local item = element.item
        if is_sainted_item(item) then
            apply_sainted_theme(widget, "TOOLTIP", item)
        end
    end

    local _gadget_header_init = blueprints.gadget_header.init
    blueprints.gadget_header.init = function(parent, widget, element, callback_name, _, ui_renderer)
        _gadget_header_init(parent, widget, element, callback_name, _, ui_renderer)

        local item = element.item
        if is_sainted_item(item) then
            apply_sainted_theme(widget, "TOOLTIP", item)
        end
    end

    return blueprints
end)

---------------
-- ITEM SLOT --
---------------

mod:hook_require("scripts/ui/views/inventory_view/inventory_view_content_blueprints", function(instance)
    local _item_slot_init = instance.item_slot.init
    instance.item_slot.init = function(parent, widget, element, callback_name)
        _item_slot_init(parent, widget, element, callback_name)

        local item = parent:equipped_item_in_slot(element.slot.name)
        if is_sainted_item(item) then
            apply_sainted_theme(widget, "SLOT", item)
        end
    end

    local _item_slot_update = instance.item_slot.update
    instance.item_slot.update = function(parent, widget, input_service, dt, t, ui_renderer)
        _item_slot_update(parent, widget, input_service, dt, t, ui_renderer)

        local item = parent:equipped_item_in_slot(widget.content.element.slot.name)
        if is_sainted_item(item) then
            apply_sainted_theme(widget, "SLOT", item)
        end
    end

    local _gadget_item_slot_init = instance.gadget_item_slot.init
    instance.gadget_item_slot.init = function(parent, widget, element, callback_name)
        _gadget_item_slot_init(parent, widget, element, callback_name)

        local item = parent:equipped_item_in_slot(element.slot.name)
        if is_sainted_item(item) then
            apply_sainted_theme(widget, "SLOT", item)
        end
    end

    local _gadget_item_slot_update = instance.gadget_item_slot.update
    instance.gadget_item_slot.update = function(parent, widget, input_service, dt, t, ui_renderer)
        _gadget_item_slot_update(parent, widget, input_service, dt, t, ui_renderer)

        local item = parent:equipped_item_in_slot(widget.content.element.slot.name)
        if is_sainted_item(item) then
            apply_sainted_theme(widget, "SLOT", item)
        end
    end
end)

-----------------------
-- ITEM NOTIFICATION --
-----------------------

mod:hook("ConstantElementNotificationFeed", "_generate_notification_data", function(func, self, message_type, data)
    local notification = func(self, message_type, data)
    if message_type == "item_granted" then
        if is_sainted_item(notification.item) then
            local rarity_color = table.clone(COLOR)
            local background_rarity_color = table.clone(COLOR_DARK)
			background_rarity_color[1] = background_rarity_color[1] * ConstantElementNotificationFeedSettings.default_alpha_value

            notification.color = background_rarity_color
            notification.line_color = rarity_color
            notification.texts[1].color = rarity_color
            notification.texts[2].color = rarity_color
            notification.texts[2].display_name = Localize("loc_item_weapon_rarity_6")
        end
    end
    return notification
end)
