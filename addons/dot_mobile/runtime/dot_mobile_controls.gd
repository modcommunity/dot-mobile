class_name DotMobileControls
extends DotHudPiece

## The touch overlay a first-person game adds over its HUD: a drawn stick, drag-to-look, the game's declared
## buttons, gyro look, aim assist and auto-fire, each bounded by [member rules]. It drives the game's own
## [DotFpsTouchSampler] (forwarding touches, holding command bits) and replaces nothing in it.
##
## [codeblock]
## var controls := DotMobileControls.new()
## controls.rules = my_rules            # followed from the server's replicated cvars
## controls.setup(sampler, [{"id": &"fire", "label": "FIRE", "offset": Vector2(86, 150), "radius": 52.0},
##     {"id": &"jump", "label": "JUMP", "offset": Vector2(200, 130), "radius": 42.0, "hold": DotFpsCommand.BUTTON_JUMP}])
## controls.crosshair_fn = my_crosshair_kind   # () -> DotMobileAutoFire.TARGET_*
## hud.add_child(controls)
## # and in the game's own input forwarding:
## if not controls.takes(event): sampler.handle_event(event)
## [/codeblock]

## A declared button went down or up (after the server's filter). One-shot actions hang off these.
signal button_pressed(id: StringName)
signal button_released(id: StringName)

const CHANNEL := "mobile"

## The id auto-fire presses. Declare a button with this id for a visible Fire button.
const FIRE := &"fire"

## What the server allows. Replace before adding to the tree, or call [method refresh] after.
var rules: DotMobileRules = DotMobileRules.new()
## What the player chose. Call [method refresh] after changing it.
var prefs: DotMobilePrefs = DotMobilePrefs.new()

var aim_assist: DotMobileAimAssist = DotMobileAimAssist.new()
var autofire: DotMobileAutoFire = DotMobileAutoFire.new()
var gyro: DotMobileGyro = DotMobileGyro.new()

## () -> PackedVector3Array: aim points of the living enemies this player can see. Leave unset for no aim assist.
var targets_fn: Callable = Callable()
## () -> Vector3: the eye aim assist measures from.
var eye_fn: Callable = Callable()
## () -> int, a [constant DotMobileAutoFire.TARGET_NONE]-style kind from the game's own crosshair ray. Unset: no auto-fire.
var crosshair_fn: Callable = Callable()
## () -> bool: false while the player is dead, spectating or in a menu; gyro, aim assist and auto-fire pause.
var live_fn: Callable = Callable()
## (Vector2 viewport position) -> bool: true leaves that touch alone (the game's own menu button, say).
var ignore_fn: Callable = Callable()

## The dot-ui buttons, mirrored for a left-handed player.
var buttons: DotMobileButtons = null
var sampler: DotFpsSampler = null

## Whether the overlay is showing and taking touches: a touch device (or the player's override) and the server allows it.
var touch: bool = false
## [member prefs] as [member rules] allow them, from the last [method refresh].
var effective: DotMobilePrefs = DotMobilePrefs.new()

var _touch_sampler: DotFpsTouchSampler = null
var _layout: Array[Dictionary] = []
var _hold_bits: Dictionary = {}
var _forwarding: bool = false
var _game_ignore: Callable = Callable()
var _refresh_queued: bool = false
## Finger index -> pixels added to x before forwarding (the left-handed shift); a finger absent here is not ours.
var _shift: Dictionary = {}
var _move_finger: int = -1
var _move_origin: Vector2 = Vector2.ZERO
var _move_now: Vector2 = Vector2.ZERO
var _look_finger: int = -1


## Hands over the game's sampler and its buttons: dot-ui's dictionaries (id, label, offset, radius) plus an optional
## "hold": a DotFpsCommand bit the overlay holds on the sampler while the button (or auto-fire, for [constant FIRE]) is down.
func setup(p_sampler: DotFpsSampler, layout: Array[Dictionary]) -> void:
	sampler = p_sampler
	_touch_sampler = p_sampler as DotFpsTouchSampler
	# The game's own filter (a menu button, say) moves to the overlay, which now decides which touches reach the sampler.
	if _touch_sampler != null and _touch_sampler.ignore_fn != _sampler_ignores:
		_game_ignore = _touch_sampler.ignore_fn
		if not ignore_fn.is_valid():
			ignore_fn = _game_ignore
	_layout = layout.duplicate()
	_hold_bits.clear()
	for b in _layout:
		if b.has("hold"):
			_hold_bits[StringName(b["id"])] = int(b["hold"])
	if is_inside_tree():
		refresh()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if buttons == null:
		buttons = DotMobileButtons.new()
		buttons.name = "Buttons"
		buttons.only_on_touch = false
		buttons.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		buttons.button_down.connect(_on_button.bind(true))
		buttons.button_up.connect(_on_button.bind(false))
		add_child(buttons)
	if not rules.changed.is_connected(_queue_refresh):
		rules.changed.connect(_queue_refresh)
	resized.connect(_on_resized)
	refresh()


func _exit_tree() -> void:
	gyro.stop()
	if buttons != null:
		buttons.release_all()
	autofire.reset()
	_release_all_holds()
	if _touch_sampler != null:
		_touch_sampler.ignore_fn = _game_ignore


## Re-reads [member rules] and [member prefs]: visibility, buttons shown, mirroring, sensitivity, gyro.
func refresh() -> void:
	_refresh_queued = false
	if rules != null and not rules.changed.is_connected(_queue_refresh):
		rules.changed.connect(_queue_refresh)
	var was_touch := touch
	var was_mirrored := effective.left_handed
	touch = rules.touch_active(prefs, DotPlatform.has_touch()) and _touch_sampler != null
	effective = rules.resolve(prefs, touch)
	visible = touch
	if buttons != null:
		buttons.visible = touch
		buttons.mirrored = effective.left_handed
		var shown: Array[Dictionary] = []
		for b in _layout:
			if rules.shows_button(StringName(b["id"])):
				shown.append(b)
		buttons.set_buttons(shown)
	if was_touch and (not touch or was_mirrored != effective.left_handed):
		_drop_fingers()
	if _touch_sampler != null:
		_touch_sampler.look_sensitivity = effective.look_sensitivity
		_touch_sampler.set_screen_width(_viewport_width())
		_touch_sampler.ignore_fn = _sampler_ignores if touch else _game_ignore
	if touch and effective.gyro:
		gyro.start()
	elif gyro.state != DotMobileGyro.State.OFF:
		gyro.stop()
	if not effective.autofire:
		_set_autofire(false)
	queue_redraw()


## True when the overlay forwards [param event] itself, so the game must not hand it to the sampler as well.
func takes(event: InputEvent) -> bool:
	return touch and (event is InputEventScreenTouch or event is InputEventScreenDrag)


## A declared button held by a finger, or [constant FIRE] held by auto-fire (touch or, if the server says so, desktop).
func is_held(id: StringName) -> bool:
	if id == FIRE and autofire.firing:
		return true
	return touch and buttons != null and buttons.is_held(id)


func _input(event: InputEvent) -> void:
	if not touch or _touch_sampler == null:
		return
	if event is InputEventScreenTouch:
		_route_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_route_drag(event as InputEventScreenDrag)


func _route_touch(event: InputEventScreenTouch) -> void:
	if not event.pressed:
		if _shift.has(event.index):
			_forward(event, float(_shift[event.index]))
			var _gone := _shift.erase(event.index)
			if event.index == _move_finger:
				_move_finger = -1
				queue_redraw()
			elif event.index == _look_finger:
				_look_finger = -1
		return
	var at := event.position
	if (buttons != null and buttons.contains_point(at)) or (ignore_fn.is_valid() and bool(ignore_fn.call(at))):
		return
	var width := _viewport_width()
	var zone := clampf(_touch_sampler.move_zone, 0.05, 0.95)
	var lefty := effective.left_handed
	var is_move := at.x >= width * (1.0 - zone) if lefty else at.x < width * zone
	if (is_move and not effective.stick) or (not is_move and not effective.drag):
		return
	# Mirrored play shifts each finger into the side the sampler expects, by a fixed amount, so drag deltas stay exact.
	var shift := 0.0
	if lefty:
		shift = -width * (1.0 - zone) if is_move else width * zone
	_shift[event.index] = shift
	if is_move and _move_finger == -1:
		_move_finger = event.index
		_move_origin = at
		_move_now = at
		queue_redraw()
	elif not is_move and _look_finger == -1:
		_look_finger = event.index
	_forward(event, shift)


func _route_drag(event: InputEventScreenDrag) -> void:
	if not _shift.has(event.index):
		return
	if event.index == _move_finger and event.position.is_finite():
		_move_now = event.position
		queue_redraw()
	_forward(event, float(_shift[event.index]))


func _forward(event: InputEvent, shift: float) -> void:
	var sent := event
	if shift != 0.0:
		sent = event.duplicate() as InputEvent
		if sent is InputEventScreenTouch:
			(sent as InputEventScreenTouch).position.x += shift
		elif sent is InputEventScreenDrag:
			(sent as InputEventScreenDrag).position.x += shift
	_forwarding = true
	_touch_sampler.handle_event(sent)
	_forwarding = false


## The sampler's own filter: a touch the game forwarded as well is refused here, so no finger is handled twice.
func _sampler_ignores(_at: Vector2) -> bool:
	return not _forwarding


func _process(delta: float) -> void:
	super._process(delta)
	if sampler == null:
		return
	var live := not live_fn.is_valid() or bool(live_fn.call())
	var turned := Vector2.ZERO
	if touch and gyro.is_running():
		turned = gyro.take(effective.gyro_sensitivity, effective.gyro_invert_y)
		if live and turned != Vector2.ZERO:
			_turn(turned.x, turned.y)
	var steering := _move_finger != -1 or _look_finger != -1 or turned != Vector2.ZERO
	if effective.aim_assist and live and steering and targets_fn.is_valid() and eye_fn.is_valid():
		var targets: PackedVector3Array = targets_fn.call()
		var eye: Vector3 = eye_fn.call()
		var aimed := aim_assist.step(eye, sampler.yaw, sampler.pitch, targets, rules.aim_strength, delta)
		_turn(aimed.x - sampler.yaw, aimed.y - sampler.pitch)
	var kind := DotMobileAutoFire.TARGET_NONE
	var armed := effective.autofire and live and crosshair_fn.is_valid()
	if armed:
		kind = int(crosshair_fn.call())
	var was := autofire.firing
	var _now := autofire.update(delta, kind, armed)
	if autofire.firing != was:
		_sync_hold(FIRE)
		if touch:
			queue_redraw()


func _turn(yaw_by: float, pitch_by: float) -> void:
	sampler.yaw = wrapf(sampler.yaw + yaw_by, -180.0, 180.0)
	sampler.pitch = clampf(sampler.pitch + pitch_by, sampler.tunables.pitch_min, sampler.tunables.pitch_max)


func _on_button(id: StringName, down: bool) -> void:
	_sync_hold(id)
	if down:
		button_pressed.emit(id)
	else:
		button_released.emit(id)


func _sync_hold(id: StringName) -> void:
	if _touch_sampler != null and _hold_bits.has(id):
		_touch_sampler.hold(int(_hold_bits[id]), is_held(id))


func _set_autofire(on: bool) -> void:
	if autofire.firing and not on:
		autofire.reset()
		_sync_hold(FIRE)


func _release_all_holds() -> void:
	if _touch_sampler == null:
		return
	for id: StringName in _hold_bits:
		_touch_sampler.hold(int(_hold_bits[id]), false)


## Lifts every finger the overlay forwarded, so a sampler switched away from touch is not left walking.
func _drop_fingers() -> void:
	for index: int in _shift.keys():
		var up := InputEventScreenTouch.new()
		up.index = index
		up.pressed = false
		_forward(up, 0.0)
	_shift.clear()
	_move_finger = -1
	_look_finger = -1
	if buttons != null:
		buttons.release_all()


func _queue_refresh() -> void:
	if not _refresh_queued and is_inside_tree():
		_refresh_queued = true
		refresh.call_deferred()


func _on_resized() -> void:
	if _touch_sampler != null:
		_touch_sampler.set_screen_width(_viewport_width())
	queue_redraw()


func _viewport_width() -> float:
	return get_viewport().get_visible_rect().size.x if is_inside_tree() else 1152.0


func _to_local(at: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * at


func _draw() -> void:
	if not touch or _touch_sampler == null:
		return
	if effective.stick:
		_draw_stick()
	if effective.autofire and buttons != null and rules.shows_button(FIRE):
		var r := buttons.radius_of(FIRE)
		if r > 0.0:
			var ring := colour(&"highlight") if autofire.firing else Color(colour(&"dim"), 0.45)
			draw_arc(buttons.centre_of(FIRE), r + 6.0, 0.0, TAU, 48, ring, 3.0 if autofire.firing else 2.0, true)


func _draw_stick() -> void:
	var scale_x := maxf(0.01, get_global_transform_with_canvas().get_scale().x)
	var radius := _touch_sampler.stick_radius / scale_x
	var plate := colour(&"plate")
	var edge := colour(&"plate_edge")
	if _move_finger == -1:
		# A faint stick where a thumb usually lands, so a new player sees that the side moves.
		var x := size.x * _touch_sampler.move_zone * 0.45
		var rest := Vector2(size.x - x if effective.left_handed else x, size.y - radius - 48.0)
		draw_circle(rest, radius, Color(plate, plate.a * 0.35))
		draw_arc(rest, radius, 0.0, TAU, 48, Color(edge, edge.a * 0.8), 2.0, true)
		draw_circle(rest, radius * 0.42, Color(plate, plate.a * 0.5))
		return
	var origin := _to_local(_move_origin)
	var knob := origin + (_to_local(_move_now) - origin).limit_length(radius)
	draw_circle(origin, radius, Color(plate, plate.a * 0.6))
	draw_arc(origin, radius, 0.0, TAU, 48, edge, 2.0, true)
	draw_circle(knob, radius * 0.42, Color(plate, minf(1.0, plate.a + 0.2)))
	draw_arc(knob, radius * 0.42, 0.0, TAU, 32, colour(&"text"), 2.0, true)


func describe() -> Dictionary:
	var out := super()
	out.merge({
		"touch": touch, "effective": effective.describe(), "rules": rules.describe(), "gyro": gyro.describe(),
		"autofire": autofire.describe(), "move_finger": _move_finger, "look_finger": _look_finger,
		"aim_target": aim_assist.last_target,
	})
	return out
