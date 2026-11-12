# dot-mobile design

## What it is

`DotMobileControls` is one `Control` a first-person game adds over its HUD. It shows on a touch device (`DotPlatform.has_touch()`, or the player's override) when the server allows it, and then:

- forwards each touch to the game's `DotFpsTouchSampler`: left half moves (a stick planted where the thumb lands), right half looks;
- draws the stick (and a faint resting stick before the first touch) from dot-ui's theme colours;
- shows the game's declared buttons through dot-ui's `DotTouchButtons`, mirrored for a left-handed player, and holds each button's command bit on the sampler;
- adds gyro look, aim assist and auto-fire when the rules and the player's prefs allow them.

A game declares buttons and adds the node. It does not draw, track fingers or reimplement the sampler.

## Wiring a game

```gdscript
var controls := DotMobileControls.new()
controls.rules = mobile_rules                 # followed from the server, see below
controls.setup(sampler, [
	{"id": &"fire", "label": "FIRE", "offset": Vector2(86, 150), "radius": 52.0},
	{"id": &"jump", "label": "JUMP", "offset": Vector2(200, 130), "radius": 42.0, "hold": DotFpsCommand.BUTTON_JUMP},
])
controls.crosshair_fn = crosshair_kind        # () -> DotMobileAutoFire.TARGET_*
controls.targets_fn = visible_enemy_points    # () -> PackedVector3Array, for aim assist
controls.eye_fn = eye_position                # () -> Vector3
controls.live_fn = is_alive_and_playing       # () -> bool
hud.add_child(controls)
controls.button_pressed.connect(on_touch_button)   # one-shot actions (next weapon, reload)
```

Fire usually is not a sampler bit: the game reads `controls.is_held(&"fire")` where it reads its fire input, so a finger and auto-fire take one path. Buttons with a `"hold"` bit are held on the sampler for the game.

## Who forwards a touch

Both the overlay and the game's own input code see every touch. If both forwarded, a finger would be handled twice. So:

- the overlay forwards touches itself and sets the sampler's `ignore_fn` to refuse any press it did not forward;
- the game guards its own forwarding with `if not controls.takes(event): sampler.handle_event(event)`;
- a sampler `ignore_fn` the game set before `setup` (a menu button) becomes the overlay's `ignore_fn`, and is put back when the overlay leaves the tree or touch turns off.

Presses on a button never reach the sampler. A press on the move side is dropped when the server disallows the stick, and on the look side when it disallows drag.

Left-handed play swaps the sides. The sampler still decides by `x < width * move_zone`, so each finger is shifted by a fixed amount for its whole life; drag deltas stay exact.

When touch turns off or the mirror changes while fingers are down, the overlay lifts them on the sampler, so nobody is left walking.

Set `paused` while a menu, chat or console has the screen: the overlay hides, lifts its fingers and stops gyro, aim assist and auto-fire, so a tap meant for the menu never lands on a button. A game with two samplers (offline and online) calls `setup` again with the other one; the old sampler gets its fingers lifted, its bits released and its own filter back.

## The server's rules

`DotMobileRules` holds what the server allows. `bind_cvars(add)` registers the cvars on a server; `follow_cvars(source)` follows the replicated values on a client (the same pattern as dot-player's view rules). Every setter clamps; `set_cvar` refuses a value it cannot read.

| Cvar | Default | Meaning |
| --- | --- | --- |
| `sv_mobile_touch` | 1 | the overlay may show at all |
| `sv_mobile_schemes` | `stick,drag,gyro` | names or a bit mask; what a player may use |
| `sv_mobile_sens_min` / `_max` | 0.04 / 0.6 | the range a player's look sensitivity is clamped to |
| `sv_mobile_left_handed` | 1 | a player may mirror the layout |
| `sv_mobile_buttons` | empty | comma-separated ids to show; empty shows all the game declared |
| `sv_aim_assist` | 0 | 0 off, 1 allowed (player opts in), 2 forced; touch players only |
| `sv_aim_assist_strength` | 0.35 | 0..1 |
| `sv_autofire` | 0 | 0 off, 1 allowed (player may turn it off), 2 forced |
| `sv_autofire_desktop` | 0 | keyboard and mouse players get auto-fire too |

A game may change a default before `bind_cvars` (for example `rules.autofire = DotMobileRules.ALLOWED`).

`resolve(prefs, touch)` returns the player's prefs as the server allows them; the overlay keeps it in `effective` and re-resolves whenever the rules change.

## Aim assist

Client-side, applied before the command is sampled: `DotMobileAimAssist.step` turns the sampler's yaw and pitch a little towards the living enemy nearest the crosshair inside a cone (7 degrees, 80 metres by default). The simulation, the hit registration and the lag compensation see an ordinary player who aimed.

It runs only while the player is moving or looking (a finger on the stick or the look side, or the gyro turning), so it never aims for a player who is not touching the screen. The turn is capped at `strength * rate * delta` and fades towards the cone's edge, so it never snaps. The game hands in the targets; dot-mobile knows nothing about teams or visibility.

## Auto-fire

`DotMobileAutoFire` decides only when the fire button is down. The game tells it what is under the crosshair each frame (`crosshair_fn`): an enemy, a friend (a teammate, a corpse, anything that must not be shot) or nothing. It fires after a short reaction time on an enemy and releases at once otherwise. A semi-automatic weapon (`autofire.automatic = false`) gets separate presses.

The press goes through the same path as a finger on Fire, so fire modes, cooldowns and ammunition stay the simulation's. A game without a crosshair query uses `DotMobileAutoFire.ray_target` with its hitscan's eye and aim: one ray, the collider handed to the game's classifier. Both auto-fire and aim assist are well under 0.1 ms a frame.

Keyboard and mouse players are unaffected unless the server sets `sv_autofire_desktop`; the overlay then stays invisible but auto-fire still runs.

## Gyro look

`DotMobileGyro` reads DeviceMotion's `rotationRate` on the web through dot-core's `DotWeb` (no eval, no page script). iOS only grants motion from a user gesture, so `start()` arms a one-shot `touchend` listener and asks inside it. Off the web, without a sensor, or when refused, every call is a no-op and the state says why.

Rates are mapped to yaw and pitch by the screen orientation and integrated between events, with a gap capped at 0.1 s so a backgrounded tab does not lurch. The mapping is not verified on every phone; a player can invert pitch.

Every callback is released in `stop()`: dot-core keeps them in a static list, and one left there aborts at exit.

## Deliberately not here

A settings screen (the game's own menu shows `DotMobilePrefs`), textures or icons, haptics, and anything that changes the simulation.
