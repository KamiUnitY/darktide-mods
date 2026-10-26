local mod = get_mod("curve_your_hud")

local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
local UIWidget = require("scripts/managers/ui/ui_widget")

local GRID_LINE_WIDTH = 1
local GRID_DIVISIONS = 10
local grid_passes = {}
local vertical_style_ids = {}
local horizontal_style_ids = {}

local function add_grid_pass(style_id)
	grid_passes[#grid_passes + 1] = {
		pass_type = "rect",
		style_id = style_id,
		style = {
			color = { 96, 255, 0, 255 },
			offset = { 0, 0, 0 },
			size = { 0, 0 },
		},
	}
end

for i = 1, GRID_DIVISIONS + 1 do
	local style_id = "vertical_" .. i

	vertical_style_ids[i] = style_id
	add_grid_pass(style_id)
end

for i = 1, GRID_DIVISIONS + 1 do
	local style_id = "horizontal_" .. i

	horizontal_style_ids[i] = style_id
	add_grid_pass(style_id)
end

local Definitions = {
	scenegraph_definition = {
		screen = UIWorkspaceSettings.screen,
	},
	widget_definitions = {
		grid = UIWidget.create_definition(grid_passes, "screen"),
	},
}

local HudElementCurveYourHudDebugGrid = class("HudElementCurveYourHudDebugGrid", "HudElementBase")

local function ui_space_size()
	local width = 1920
	local height = 1080

	if RESOLUTION_LOOKUP and RESOLUTION_LOOKUP.width and RESOLUTION_LOOKUP.height then
		local inverse_scale = RESOLUTION_LOOKUP.inverse_scale or 1

		width = RESOLUTION_LOOKUP.width * inverse_scale
		height = RESOLUTION_LOOKUP.height * inverse_scale
	end

	return math.max(1, math.floor(width + 0.5)), math.max(1, math.floor(height + 0.5))
end

local function update_grid(self)
	local width, height = ui_space_size()

	if self._grid_width == width and self._grid_height == height then
		return
	end

	self._grid_width = width
	self._grid_height = height

	local screen = self._ui_scenegraph.screen
	local grid_style = self._widgets_by_name.grid.style
	local usable_width = math.max(0, width - GRID_LINE_WIDTH)
	local usable_height = math.max(0, height - GRID_LINE_WIDTH)

	screen.size[1] = width
	screen.size[2] = height

	for i = 0, GRID_DIVISIONS do
		local style = grid_style[vertical_style_ids[i + 1]]

		style.offset[1] = usable_width * i / GRID_DIVISIONS
		style.size[1] = GRID_LINE_WIDTH
		style.size[2] = height
	end

	for i = 0, GRID_DIVISIONS do
		local style = grid_style[horizontal_style_ids[i + 1]]

		style.offset[2] = usable_height * i / GRID_DIVISIONS
		style.size[1] = width
		style.size[2] = GRID_LINE_WIDTH
	end
end

HudElementCurveYourHudDebugGrid.init = function(self, parent, draw_layer, start_scale)
	HudElementCurveYourHudDebugGrid.super.init(self, parent, draw_layer, start_scale, Definitions)
end

HudElementCurveYourHudDebugGrid.draw = function(self, dt, t, ui_renderer, render_settings, input_service)
	if not mod.settings.debug_grid then
		return
	end

	update_grid(self)
	HudElementCurveYourHudDebugGrid.super.draw(self, dt, t, ui_renderer, render_settings, input_service)
end

return HudElementCurveYourHudDebugGrid
