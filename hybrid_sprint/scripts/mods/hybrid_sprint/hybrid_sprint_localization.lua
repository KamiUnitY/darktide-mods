-- ru localization by xsSplatter
-- zh-cn localization by deluxghost

return {
	mod_name = {
		en = "Hybrid Sprint",
		ru = "Гибридный бег",
		["zh-cn"] = "混合式疾跑",
	},
	mod_description = {
		en = "Provide better sprinting experience by combining Toggle and Hold sprinting mechanic together. Sprint can be canceled by releasing forward key and pressing weapon action.",
		ru = "Предлагает улучшенное управление бегом, объединяя механики бега «Переключить» и «Удерживать». Бег можно отменить, отпустив клавишу «Вперёд» и нажав любую кнопку действия оружия.",
		["zh-cn"] = "结合切换疾跑和长按疾跑机制，提供体验更好的混合式疾跑。松开前进键和按下武器操作可以打断疾跑。",
	},
	enable_hold_to_sprint = {
		en = "Hold to Sprint",
		ru = "Удерживать бег",
		["zh-cn"] = "长按疾跑",
	},
	start_sprint_buffer = {
		en = "Starting Sprint Buffer",
		ru = "Буфер запуска спринта",
		["zh-cn"] = "启动冲刺缓冲",
	},
	start_sprint_buffer_description = {
		en = "The duration in seconds for allowing sprint after pressing sprint, prior to pressing forward.",
		ru = "Длительность в секундах, позволяющая спринт после нажатия кнопки спринта, перед нажатием вперед.",
		["zh-cn"] = "按下冲刺键后，按下前进键之前允许冲刺的持续时间（以秒为单位）。",
	},
	enable_hold_to_sprint_description = {
		en = "Only Sprint while holding the button, Basically disable this mod.",
		ru = "Бежать только удерживая кнопку. Проще тогда отключить этот мод.",
		["zh-cn"] = "仅在长按时疾跑，相当于禁用此模组。",
	},
	enable_dodge_on_diagonal_sprint = {
		en = "Dodge on Diagonal Sprint",
		ru = "Уклонение при диагональном беге",
		["zh-cn"] = "在斜跑时进行闪避",
	},
	enable_dodge_on_diagonal_sprint_description = {
		en = "Perform dodge instead of jump on diagonal sprint",
		ru = "Выполняйте уклонение вместо прыжка при диагональном беге",
		["zh-cn"] = "在斜跑时执行闪避而不是跳跃",
	},
	experimental_group = {
		en = "Experimental",
		ru = "Экспериментальное",
		["zh-cn"] = "实验性",
	},
	enable_keep_sprint_after_weapon_action = {
		en = "Keep Sprint after Weapon Action",
		ru = "Продолжать бежать после использования оружия",
		["zh-cn"] = "武器操作后继续疾跑",
	},
	enable_keep_sprint_after_weapon_action_description = {
		en = "Sprint will be continued after weapon action is finished, given that you still holding forward key.",
		ru = "Бег будет продолжен после завершения действия оружия, будто вы всё ещё удерживаете клавишу «Вперёд».",
		["zh-cn"] = "只要你仍然按住前进键，武器操作结束后就会继续疾跑。",
	},
	debug_group = {
		en = "Debug",
		ru = "Отладка",
		["zh-cn"] = "调试",
	},
	enable_debug_modding_tools = {
		en = "Modding Tools",
		ru = "Инструменты модификации",
		["zh-cn"] = "模组开发者工具",
	},
}
