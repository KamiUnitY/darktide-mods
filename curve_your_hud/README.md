# Curve Your HUD
Applies a curved effect to the HUD, along with scanlines, noise, camera and motion sway effects.

## Features

- Curved HUD
- Adjustable scanline and noise effect
- Adjustable camera sway effect, by malevhf.
- Adjustable HUD opacity
- Adjustable screen margin

## How it works

Curve Your HUD applies its visual effects through a shader. To make this possible, the mod hide affected HUD elements and route them through two custom UI renderers, each with a different role:

- **Offscreen renderer:** Responsible for drawing the affected HUD elements onto a material offscreen instead of directly onto the screen. This is where magic happens, the material used to draw that texture is where the mod configures its shader effects, including curvature, noise, and scanlines.

- **Screen renderer:** Responsible for drawing the material texture and its shader effects onto the screen as a single bitmap. Then margin and sway settings change the bitmap's size and position before it is sent to the vanilla `to_screen`. HUD elements that should appear above the curved are then drawn here after the bitmap.

The material used by this mod is a modified version of Fatshark's `content/ui/meshes/hud_plane/hud_material`. I found this by name guessing, it was no where used in the source code. The vanilla material already contains all the shader effects used by the mod, but it also undesirably changes the HUD's color channels. AI was used to fix that color issue. The tools used to do this are included with the mod, and then the modified material is loaded into the game through our beloved Custom Assets mod.

## API: Toggle effects

Another mod can toggle the whole HUD effect through these functions:

```lua
local curve_your_hud = get_mod("curve_your_hud")

curve_your_hud:toggle()
curve_your_hud:enable()
curve_your_hud:disable()
```

- `toggle()`: Toggles the effect between enabled and disabled.
- `enable()`: Enables the effect.
- `disable()`: Disables the effect.

## API: Render mode override

Another mod can override how HUD element is rendered by adding
`curve_your_hud_render_mode_override` to its definition:

```lua
mod:register_hud_element({
    class_name = "HudElementExample",
    filename = "example/scripts/mods/example/hud_element_example",
    visibility_groups = { "alive" },
    curve_your_hud_render_mode_override = "original",
})
```

Accepted values:

- `"curved"`: The default for most gameplay HUD elements, this will make the hud get affect by every effect of the mod through custom renderer.
- `"overlay"`: This is for HUD that need to be rendered on top of the curved HUD without being affected by any of the effects. do keep in mind this still uses custom renderer.
- `"original"`: This is the best compatibility option, use this to make the mod use vanilla renderer for the hud.
