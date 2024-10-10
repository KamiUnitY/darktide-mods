local mod = get_mod("my_red_weapon_at_home")
local modding_tools = get_mod("modding_tools")

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

mod:hook("ViewElementGrid", "_create_entry_widget_from_config", function(func, self, config, suffix, callback_name, secondary_callback_name, double_click_callback_name)
	local widget, alignment_widget = func(self, config, suffix, callback_name, secondary_callback_name, double_click_callback_name)

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

		bg_color[2], bg_color[3], bg_color[4] = 255, 20, 20
		tag_color[2], tag_color[3], tag_color[4] = 255, 20, 20
		name_color[2], name_color[3], name_color[4] = 255, 20, 20

		widget.content.rarity_name = "Relic"
	end

	return widget, alignment_widget
end)
