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

------------------
-- FIND SAINTED --
------------------

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

-------------------
-- APPLY SAINTED --
-------------------

mod:hook_require("scripts/utilities/items", function(Items)
    Items.original_rarity_color = Items.original_rarity_color or Items.rarity_color
    Items.rarity_color = function(item)
        local original_color, original_color_dark = Items.original_rarity_color(item)
        if mod:is_enabled() and is_sainted_item(item) then
            return COLOR, COLOR_DARK
        end
        return original_color, original_color_dark
    end

    Items.original_rarity_display_name = Items.original_rarity_display_name or Items.rarity_display_name
    Items.rarity_display_name = function(item)
        local original_rarity_name = Items.original_rarity_display_name(item)
        if mod:is_enabled() and is_sainted_item(item) then
            return Localize("loc_item_weapon_rarity_6")
        end
        return original_rarity_name
    end
end)
