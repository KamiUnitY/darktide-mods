local mod = get_mod("red_weapons_at_home")
local modding_tools = get_mod("modding_tools")

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

require("scripts/ui/view_content_blueprints/item_stats_blueprints")
mod:hook(package.loaded, "scripts/ui/view_content_blueprints/item_stats_blueprints", function(func, ...)
    local blueprints = func(...)

    if not blueprints.weapon_header or not blueprints.weapon_header.init or not blueprints.extended_weapon_stats_header.init then
        return blueprints
    end

    local _weapon_header_init = blueprints.weapon_header.init
    blueprints.weapon_header.init = function (parent, widget, element, callback_name, _, ui_renderer)
        _weapon_header_init(parent, widget, element, callback_name, _, ui_renderer)

        local item = element.item
        local rarity = item.__master_item.rarity
        local level = item.__master_item.baseItemLevel

        if rarity == 5 and level >= 380 then
            local bg_color = widget.style.gradient_background.color
            local name_color = widget.style.rarity_name.text_color

            bg_color[2], bg_color[3], bg_color[4] = 130, 20, 20
            name_color[2], name_color[3], name_color[4] = 220, 20, 20

            widget.content.rarity_name = "Relic"
        end
    end

    local _extended_weapon_stats_header_init = blueprints.extended_weapon_stats_header.init
    blueprints.extended_weapon_stats_header.init = function (parent, widget, element, callback_name)
        _extended_weapon_stats_header_init(parent, widget, element, callback_name)

        local item = element.item
        local rarity = item.__master_item.rarity
        local level = item.__master_item.baseItemLevel

        if rarity == 5 and level >= 380 then
            local name_color = widget.style.rarity_name.text_color

            name_color[2], name_color[3], name_color[4] = 220, 20, 20

            widget.content.rarity_name = "Relic"
        end
    end

    return blueprints
end)

mod:hook_require("scripts/ui/views/inventory_view/inventory_view_content_blueprints", function(instance)

    local _item_slot_init = instance.item_slot.init
    instance.item_slot.init = function (parent, widget, element, callback_name)
        _item_slot_init(parent, widget, element, callback_name)

		local item = parent:equipped_item_in_slot(element.slot.name)
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

    local _item_slot_update = instance.item_slot.update
    instance.item_slot.update = function (parent, widget, input_service, dt, t, ui_renderer)
        _item_slot_update(parent, widget, input_service, dt, t, ui_renderer)

		local item = parent:equipped_item_in_slot(widget.content.element.slot.name)
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