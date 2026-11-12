# dot-mobile

Touch controls for first-person Godot 4 games: a drawn virtual stick, drag-to-look, game-declared buttons, optional gyro look on the web, and server-controlled aim assist and auto-fire.

- Drives dot-player-controller's `DotFpsTouchSampler`; the game keeps its own input pipeline.
- Code only: drawn with `_draw` and dot-ui's theme colours, no textures.
- Every option is bounded by replicated server cvars (`sv_mobile_*`, `sv_aim_assist*`, `sv_autofire*`).
- Aim assist and auto-fire act on look input and the fire button before the command, so simulation, hit registration and lag compensation are untouched.

## Install

Copy `addons/dot_mobile/` into your project next to `dot_core`, `dot_ui` and `dot_player_controller`, and enable the plugin.

## Use

```gdscript
var controls := DotMobileControls.new()
controls.setup(sampler, [{"id": &"fire", "label": "FIRE", "offset": Vector2(86, 150), "radius": 52.0}])
controls.crosshair_fn = my_crosshair_kind
hud.add_child(controls)
```

See [docs/design.md](docs/design.md) for forwarding, the cvars and the rest.

## Test

Run `examples/mobile_selftest.tscn` headless.

## License

MIT
