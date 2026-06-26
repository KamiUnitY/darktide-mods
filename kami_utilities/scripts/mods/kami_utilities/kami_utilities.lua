local mod = get_mod("kami_utilities")
local modding_tools = get_mod("modding_tools")

--------------------------
-- MOD SETTINGS CACHING --
--------------------------

mod.settings = {
    enable_benchmark_input = mod:get("enable_benchmark_input"),
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

------------
-- CHEATS --
------------

-- mod:hook_safe("PlayerUnitAbilityExtension", "use_ability_charge", function(self, ability_type, optional_num_charges)
--     if self._player.viewport_name == "player1" then
--         if ability_type == "combat_ability" then
--             local unit = Managers.player:local_player(1).player_unit
--             if unit then
--                 local ability_system = ScriptUnit.extension(unit, "ability_system")
--                 ability_system:set_ability_charges("combat_ability",3)
--             end
--         end
--     end
-- end)

