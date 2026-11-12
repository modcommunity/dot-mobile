# dot-mobile

Touch controls for a first-person game: a drawn stick, drag-to-look, the game's declared buttons, optional gyro look, and opt-in aim assist and auto-fire, each bounded by replicated server cvars. It drives the game's own `DotFpsTouchSampler`; it replaces nothing in it.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to mobile.

**The distributable is `addons/dot_mobile/`.** It requires dot-core, dot-ui and dot-player-controller (symlinked and gitignored for development). It is code only: everything is drawn with `_draw`, never a texture.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | anything: who forwards touches, the server's rules, aim assist, auto-fire, gyro, wiring a game |

## Layout

| Path | What |
| --- | --- |
| `core/dot_mobile_rules.gd` | `DotMobileRules`: what the server allows; the `sv_mobile_*`, `sv_aim_assist*`, `sv_autofire*` cvars; `resolve(prefs, touch)` |
| `core/dot_mobile_prefs.gd` | `DotMobilePrefs`: what the player chose; `to_dict` / `from_dict` |
| `core/dot_mobile_aim_assist.gd` | `DotMobileAimAssist`: cone pick and a capped turn towards it, in the sampler's degrees |
| `core/dot_mobile_autofire.gd` | `DotMobileAutoFire`: when the fire button is down; `ray_target` for a game with no crosshair query |
| `runtime/dot_mobile_gyro.gd` | `DotMobileGyro`: DeviceMotion through `DotWeb`, iOS permission from a gesture |
| `runtime/dot_mobile_buttons.gd` | `DotMobileButtons`: dot-ui's `DotTouchButtons`, mirrorable |
| `runtime/dot_mobile_controls.gd` | `DotMobileControls`: the node a game adds |
| `examples/mobile_selftest.tscn` | the suite |

## Running and testing

`sudo -u gamedev /home/gamedev/bin/hv . import`, then `sudo -u gamedev /home/gamedev/bin/hv . scene res://examples/mobile_selftest.tscn`, capped with `timeout`. Read the stderr even when it exits 0. The headless viewport is 64 pixels wide: a check must not depend on the screen size.

## Rules that bite

- The overlay forwards touches itself and sets the sampler's `ignore_fn`; the game guards its own forwarding with `controls.takes(event)`. [design](docs/design.md#who-forwards-a-touch)
- Aim assist and auto-fire change only the sampler's yaw and pitch and a held button bit, never the simulation, hit registration or lag compensation. [design](docs/design.md#aim-assist)
- Auto-fire presses the same bit a finger on Fire sets, so fire modes and cooldowns stay the simulation's. The game's crosshair kind must say FRIEND for teammates and the dead. [design](docs/design.md#auto-fire)
- Everything off-default is the server's call: aim assist is OFF in the addon, auto-fire is OFF in the addon (a game may default it on). [design](docs/design.md#the-servers-rules)
- `DotWeb` callbacks are released in `DotMobileGyro.stop()`; never leave a lambda in a static list. [design](docs/design.md#gyro-look)
- `DotMobileControls` must not name its own class inside its script (it extends a script class).
