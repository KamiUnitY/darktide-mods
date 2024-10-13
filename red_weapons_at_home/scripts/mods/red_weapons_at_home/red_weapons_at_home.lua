-- Red Weapons at Home by KamiUnitY. Ver. 1.0.0

local mod = get_mod("red_weapons_at_home")
local modding_tools = get_mod("modding_tools")

local Items = require("scripts/utilities/items")

---------------
-- CONSTANTS --
---------------

local MAX_EXPERTISE_LEVEL = tostring(Items.max_expertise_level())

local COLOR = {255, 210, 30, 30}
local COLOR_DARK = {255, 120, 20, 20}

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

local function apply_sainted_theme(widget)
    local style = widget.style

    if style.rarity_tag then
        style.rarity_tag.color = table.clone(COLOR)
    end
    if style.rarity_name then
        style.rarity_name.text_color = table.clone(COLOR)
    end
    if style.background_gradient then
        style.background_gradient.color = table.clone(COLOR)
    end
    if style.gradient_background then
        style.gradient_background.color = table.clone(COLOR_DARK)
    end

    widget.content.rarity_name = Localize("loc_item_weapon_rarity_6")
end


local function is_sainted_item(item)
    return item and item.rarity == 5 and Items.expertise_level(item, true) == MAX_EXPERTISE_LEVEL
end

---------------
-- ITEM GRID --
---------------

mod:hook("ViewElementGrid", "_create_entry_widget_from_config", function(func, self, ...)
    local widget, alignment_widget = func(self, ...)

    if widget and (widget.type == "item" or widget.type == "store_item") then
        local item = widget.content and widget.content.element and widget.content.element.item
        if is_sainted_item(item) then
            apply_sainted_theme(widget)
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
            apply_sainted_theme(widget)
        end
    end

    local _extended_weapon_stats_header_init = blueprints.extended_weapon_stats_header.init
    blueprints.extended_weapon_stats_header.init = function(parent, widget, element, callback_name)
        _extended_weapon_stats_header_init(parent, widget, element, callback_name)

        local item = element.item
        if is_sainted_item(item) then
            apply_sainted_theme(widget)
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
            apply_sainted_theme(widget)
        end
    end

    local _item_slot_update = instance.item_slot.update
    instance.item_slot.update = function(parent, widget, input_service, dt, t, ui_renderer)
        _item_slot_update(parent, widget, input_service, dt, t, ui_renderer)

        local item = parent:equipped_item_in_slot(widget.content.element.slot.name)
        if is_sainted_item(item) then
            apply_sainted_theme(widget)
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
			background_rarity_color[1] = background_rarity_color[1] * 0.75

            notification.color = background_rarity_color
            notification.line_color = rarity_color
            notification.texts[1].color = rarity_color
            notification.texts[2].color = rarity_color
            notification.texts[2].display_name = Localize("loc_item_weapon_rarity_6")
        end
    end
    return notification
end)