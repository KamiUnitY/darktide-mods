local HudStudio = {}

local hud_studio = get_mod("hud_studio")

local Managers = Managers

local hooked_editors = setmetatable({}, { __mode = "k" })
local refresh_gameplay_hooks

function HudStudio.is_editor_active()
	return hud_studio and hud_studio.hud_studio_editor_active == true or false
end

local function refresh_on_state_change(was_active)
	if HudStudio.is_editor_active() ~= was_active then
		refresh_gameplay_hooks()
	end
end

function HudStudio.install(hud)
	local editor = hud and hud._elements and hud._elements.HudEditor

	if not editor or hooked_editors[editor] then
		return
	end

	local original_escape = editor._escape

	editor._escape = function(self, ...)
		local was_active = HudStudio.is_editor_active()
		local result = original_escape(self, ...)

		refresh_on_state_change(was_active)

		return result
	end
	hooked_editors[editor] = true
end

function HudStudio.setup(mod, refresh_hooks)
	if not hud_studio then
		return
	end

	refresh_gameplay_hooks = refresh_hooks

	mod:hook(hud_studio, "toggle_editor", function(func, self, ...)
		HudStudio.install(Managers.ui and Managers.ui._hud)

		local was_active = HudStudio.is_editor_active()
		local result = func(self, ...)

		refresh_on_state_change(was_active)

		return result
	end)
end

return HudStudio
