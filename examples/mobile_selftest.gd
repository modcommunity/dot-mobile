extends Node

## Exercises dot-mobile with no phone, no browser and no server: the rules' clamping and cvars, the prefs a player
## saves, aim-assist math, auto-fire gating and the overlay driving a real DotFpsTouchSampler with synthetic touches.
##
## [codeblock]
## godot --headless --path . res://examples/mobile_selftest.tscn
## [/codeblock]

## A script error aborts one section, not the run; the totals catch that.
const SECTIONS := 9
const CHECKS := 120

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	_line("dot-mobile self-test")
	_test_rules_clamping()
	_test_rules_cvars()
	_test_prefs()
	_test_resolve()
	_test_aim_math()
	_test_autofire()
	_test_gyro()
	await _test_controls()
	await _test_left_handed()
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])
	DotPlatform.touch_override = -1
	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return
	if _passed + _failed != CHECKS:
		_line("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _test_rules_clamping() -> void:
	_section("rules clamp what a server may set")
	var r := DotMobileRules.new()
	_check(r.touch_enabled and r.schemes == DotMobileRules.SCHEME_ALL, "touch and every scheme are on by default")
	_check(r.aim_assist == DotMobileRules.OFF, "aim assist is off by default")
	_check(r.autofire == DotMobileRules.OFF, "auto-fire is off by default in the addon")
	r.sens_min = -5.0
	_check(is_equal_approx(r.sens_min, DotMobileRules.SENS_FLOOR), "sens_min clamps to the floor")
	r.sens_max = 99.0
	_check(is_equal_approx(r.sens_max, DotMobileRules.SENS_CEILING), "sens_max clamps to the ceiling")
	r.aim_strength = 3.0
	_check(is_equal_approx(r.aim_strength, 1.0), "aim strength clamps to 1")
	r.aim_strength = -1.0
	_check(is_equal_approx(r.aim_strength, 0.0), "aim strength clamps to 0")
	r.aim_assist = 9
	_check(r.aim_assist == DotMobileRules.FORCED, "aim assist clamps to FORCED")
	r.autofire = -3
	_check(r.autofire == DotMobileRules.OFF, "auto-fire clamps to OFF")
	r.schemes = 0xFF
	_check(r.schemes == DotMobileRules.SCHEME_ALL, "schemes keep only known bits")
	var fired: Array[int] = [0]
	r.changed.connect(func() -> void: fired[0] += 1)
	r.schemes = DotMobileRules.SCHEME_ALL
	_check(fired[0] == 0, "setting the same value emits nothing")
	r.left_handed_allowed = false
	_check(fired[0] == 1, "a real change emits changed once")
	_check(r.shows_button(&"fire"), "an empty button list shows every button")
	r.buttons = PackedStringArray(["fire", "jump"])
	_check(r.shows_button(&"jump") and not r.shows_button(&"crouch"), "a button list hides the rest")


func _test_rules_cvars() -> void:
	_section("server cvars")
	var r := DotMobileRules.new()
	_check(r.set_cvar(DotMobileRules.CVAR_SCHEMES, "stick, drag"), "schemes by name are accepted")
	_check(r.schemes == DotMobileRules.SCHEME_STICK | DotMobileRules.SCHEME_DRAG, "stick and drag set, gyro cleared")
	_check(not r.set_cvar(DotMobileRules.CVAR_SCHEMES, "stick,teleport"), "an unknown scheme is refused")
	_check(r.schemes == 3, "a refused value changes nothing")
	_check(r.set_cvar(DotMobileRules.CVAR_SCHEMES, "4") and r.schemes == 4, "a bit mask is accepted")
	_check(DotMobileRules.parse_schemes("") == 0, "an empty scheme list is no scheme")
	_check(DotMobileRules.schemes_text(3) == "stick,drag", "schemes print back by name")
	_check(r.set_cvar(DotMobileRules.CVAR_SENS_MAX, "7") and is_equal_approx(r.sens_max, DotMobileRules.SENS_CEILING),
			"a numeric cvar clamps")
	_check(not r.set_cvar(DotMobileRules.CVAR_SENS_MIN, "fast"), "a non-number is refused")
	_check(not r.set_cvar(DotMobileRules.CVAR_SENS_MIN, "nan"), "NaN is refused")
	_check(r.set_cvar(DotMobileRules.CVAR_AIM_ASSIST, "2") and r.aim_assist == DotMobileRules.FORCED, "aim assist forced")
	_check(r.set_cvar(DotMobileRules.CVAR_AUTOFIRE, "5") and r.autofire == DotMobileRules.FORCED, "auto-fire clamps")
	_check(not r.set_cvar(DotMobileRules.CVAR_AUTOFIRE, "yes"), "auto-fire refuses words")
	_check(r.set_cvar(DotMobileRules.CVAR_TOUCH, "0") and not r.touch_enabled, "touch can be turned off")
	_check(r.set_cvar(DotMobileRules.CVAR_BUTTONS, " fire , ,jump") and r.buttons.size() == 2, "buttons split and trim")
	_check(r.set_cvar(DotMobileRules.CVAR_BUTTONS, "") and r.buttons.is_empty(), "an empty list shows all again")
	_check(not r.set_cvar("sv_gravity", "1"), "a foreign cvar is refused")
	var specs := r.cvar_specs()
	var names: Array[String] = []
	for s in specs:
		names.append(str(s["name"]))
	_check(names.size() == DotMobileRules.ALL_CVARS.size(), "one spec per cvar")
	var every := true
	for n in DotMobileRules.ALL_CVARS:
		every = every and names.has(n)
	_check(every, "every cvar has a spec")
	var added: Array[String] = []
	var _bound := r.bind_cvars(func(n: String, _v: Variant, _d: String, _f: int) -> Variant:
		added.append(n)
		return null)
	_check(added.size() == DotMobileRules.ALL_CVARS.size(), "bind_cvars registers every cvar")


func _test_prefs() -> void:
	_section("player prefs")
	var p := DotMobilePrefs.new()
	_check(p.touch == DotMobilePrefs.TOUCH_AUTO, "touch follows the device by default")
	_check(not p.gyro and not p.aim_assist and p.autofire, "gyro and aim assist off, auto-fire on")
	p.left_handed = true
	p.look_sensitivity = 0.3
	var q := DotMobilePrefs.new()
	q.from_dict(p.to_dict())
	_check(q.left_handed and is_equal_approx(q.look_sensitivity, 0.3), "prefs round-trip through a dictionary")
	q.from_dict({"look_sensitivity": 50.0, "gyro_sensitivity": -2, "stick": "no", "touch": 7})
	_check(is_equal_approx(q.look_sensitivity, DotMobileRules.SENS_CEILING), "a saved sensitivity clamps")
	_check(is_equal_approx(q.gyro_sensitivity, 0.1), "a saved gyro sensitivity clamps")
	_check(q.stick, "a mistyped flag keeps its value")
	_check(q.touch == DotMobilePrefs.TOUCH_ON, "touch clamps to ON")
	q.from_dict({"look_sensitivity": INF})
	_check(is_equal_approx(q.look_sensitivity, DotMobileRules.SENS_CEILING), "inf is ignored")
	var c := p.copy()
	c.left_handed = false
	_check(p.left_handed, "copy is independent")


func _test_resolve() -> void:
	_section("server restricts the client")
	var r := DotMobileRules.new()
	var p := DotMobilePrefs.new()
	p.gyro = true
	p.left_handed = true
	p.look_sensitivity = 1.5
	p.aim_assist = true
	_check(r.touch_active(p, true) and not r.touch_active(p, false), "AUTO follows the device")
	p.touch = DotMobilePrefs.TOUCH_ON
	_check(r.touch_active(p, false), "a player can force the overlay on")
	r.touch_enabled = false
	_check(not r.touch_active(p, true), "the server can switch it off for everyone")
	r.touch_enabled = true
	r.schemes = DotMobileRules.SCHEME_STICK | DotMobileRules.SCHEME_DRAG
	r.left_handed_allowed = false
	var e := r.resolve(p, true)
	_check(not e.gyro and e.stick and e.drag, "a disallowed scheme is off")
	_check(not e.left_handed, "a disallowed mirror is off")
	_check(is_equal_approx(e.look_sensitivity, r.sens_max), "sensitivity clamps to the server's range")
	_check(p.gyro and p.left_handed, "resolve leaves the player's own prefs alone")
	_check(not e.aim_assist, "aim assist stays off while the server has it OFF")
	r.aim_assist = DotMobileRules.ALLOWED
	_check(r.resolve(p, true).aim_assist, "ALLOWED plus the player's opt-in turns it on")
	p.aim_assist = false
	_check(not r.resolve(p, true).aim_assist, "ALLOWED without the opt-in stays off")
	r.aim_assist = DotMobileRules.FORCED
	_check(r.resolve(p, true).aim_assist, "FORCED overrides the player")
	_check(not r.resolve(p, false).aim_assist, "a mouse player never gets aim assist")
	r.aim_strength = 0.0
	_check(not r.resolve(p, true).aim_assist, "strength 0 is off")
	r.autofire = DotMobileRules.ALLOWED
	_check(r.resolve(p, true).autofire, "auto-fire on for a touch player who keeps the default")
	_check(not r.resolve(p, false).autofire, "keyboard players are unaffected")
	r.autofire_desktop = true
	_check(r.resolve(p, false).autofire, "unless the server includes them")
	p.autofire = false
	_check(not r.resolve(p, true).autofire, "a player may turn ALLOWED auto-fire off")
	r.autofire = DotMobileRules.FORCED
	_check(r.resolve(p, true).autofire, "FORCED overrides that")
	r.autofire = DotMobileRules.OFF
	_check(not r.resolve(p, true).autofire, "OFF turns it off for everyone")
	r.sens_min = 0.5
	r.sens_max = 0.2
	p.look_sensitivity = 0.9
	_check(is_equal_approx(r.resolve(p, true).look_sensitivity, 0.5), "a crossed range still clamps")


func _test_aim_math() -> void:
	_section("aim-assist math")
	_check(DotMobileAimAssist.direction(0, 0).is_equal_approx(Vector3(0, 0, -1)), "yaw 0 looks down -Z")
	_check(DotMobileAimAssist.direction(90, 0).is_equal_approx(Vector3(-1, 0, 0)), "yaw 90 looks down -X")
	_check(DotMobileAimAssist.direction(0, 90).is_equal_approx(Vector3(0, 1, 0)), "pitch 90 looks up")
	var a := DotMobileAimAssist.angles_to(Vector3.ZERO, Vector3(-5, 0, 0))
	_check(is_equal_approx(a.x, 90.0) and is_equal_approx(a.y, 0.0), "angles_to inverts direction")
	var b := DotMobileAimAssist.angles_to(Vector3(1, 2, 3), Vector3(1, 2, 3) + DotMobileAimAssist.direction(-37, 21) * 4)
	_check(absf(b.x + 37.0) < 0.001 and absf(b.y - 21.0) < 0.001, "angles_to round-trips direction")
	var aim := DotMobileAimAssist.new()
	var eye := Vector3.ZERO
	var ahead := Vector3(0, 0, -10)
	var near := ahead + Vector3(-0.5, 0, 0)
	var targets := PackedVector3Array([Vector3(0, 0, 10), near])
	_check(aim.pick(eye, 0, 0, targets) == 1, "picks the target in front, not the one behind")
	_check(aim.pick(eye, 0, 0, PackedVector3Array([Vector3(-10, 0, -10)])) == -1, "45 degrees off is outside the cone")
	_check(aim.pick(eye, 0, 0, PackedVector3Array([Vector3(0, 0, -200)])) == -1, "out of range is ignored")
	var after := aim.step(eye, 0, 0, targets, 1.0, 0.1)
	var want := DotMobileAimAssist.angles_to(eye, near).x
	_check(after.x > 0.0 and after.x <= want + 0.0001, "the pull turns towards the target without passing it")
	_check(absf(after.x) <= aim.rate_deg_s * 0.1 + 0.0001, "the pull is capped by rate times delta")
	var weak := aim.step(eye, 0, 0, targets, 0.25, 0.1)
	_check(weak.x < after.x, "lower strength turns less")
	_check(aim.step(eye, 0, 0, targets, 0.0, 0.1) == Vector2.ZERO, "strength 0 never turns")
	_check(aim.step(eye, 0, 0, PackedVector3Array(), 1.0, 0.1) == Vector2.ZERO, "no targets never turns")
	var settled := Vector2.ZERO
	for i in 200:
		settled = aim.step(eye, settled.x, settled.y, targets, 1.0, 0.05)
	_check(absf(settled.x - want) < 0.01, "repeated steps settle on the target, not past it")
	var wrap := aim.step(eye, 179.0, 0.0, PackedVector3Array([Vector3(0.3, 0, 10)]), 1.0, 0.1)
	_check(wrap.x <= 180.0 and wrap.x >= -180.0 and absf(wrapf(wrap.x - 179.0, -180, 180)) > 0.0,
			"a target across the yaw seam pulls the short way and stays wrapped")
	_check(aim.last_target == 0, "last_target names the target")
	var t0 := Time.get_ticks_usec()
	var many := PackedVector3Array()
	for i in 32:
		many.append(Vector3(i - 16, 0, -20))
	for i in 1000:
		var _s := aim.step(eye, 0, 0, many, 0.5, 0.016)
	var per_frame_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 1000.0
	_check(per_frame_ms < 0.1, "32 targets cost under 0.1 ms a frame (%.4f ms)" % per_frame_ms)


func _test_autofire() -> void:
	_section("auto-fire gating")
	var af := DotMobileAutoFire.new()
	_check(not af.update(0.05, DotMobileAutoFire.TARGET_ENEMY), "no shot before the reaction time")
	_check(af.update(0.05, DotMobileAutoFire.TARGET_ENEMY), "fires once the crosshair stays on an enemy")
	_check(not af.update(0.016, DotMobileAutoFire.TARGET_FRIEND), "a teammate releases at once")
	_check(not af.update(0.05, DotMobileAutoFire.TARGET_ENEMY), "and the reaction time starts over")
	_check(not af.update(0.5, DotMobileAutoFire.TARGET_NONE), "nothing under the crosshair never fires")
	_check(not af.update(0.5, DotMobileAutoFire.TARGET_ENEMY, false), "disabled never fires")
	_check(not af.firing, "disabled releases the button")
	af.automatic = false
	var downs := 0
	var was := false
	for i in 60:
		var now := af.update(1.0 / 60.0, DotMobileAutoFire.TARGET_ENEMY)
		if now and not was:
			downs += 1
		was = now
	_check(downs >= 7 and downs <= 10, "a semi-automatic weapon gets separate presses (%d in a second)" % downs)
	af.reset()
	_check(not af.firing, "reset releases")
	var space := get_viewport().world_3d.direct_space_state if get_viewport().world_3d != null else null
	_check(DotMobileAutoFire.ray_target(space, Vector3.ZERO, Vector3.ZERO, 50.0, func(_o: Object) -> int: return 1)
			== DotMobileAutoFire.TARGET_NONE, "a zero aim direction sees nothing")
	_check(DotMobileAutoFire.ray_target(null, Vector3.ZERO, Vector3.FORWARD, 50.0, Callable())
			== DotMobileAutoFire.TARGET_NONE, "no space sees nothing")


func _test_gyro() -> void:
	_section("gyro look off the web")
	var g := DotMobileGyro.new()
	g.start()
	_check(g.state == DotMobileGyro.State.UNSUPPORTED, "off the web gyro is unsupported, not an error")
	_check(not g.is_running(), "and does not run")
	_check(g.take() == Vector2.ZERO, "and turns nothing")
	g.stop()
	_check(g.state == DotMobileGyro.State.UNSUPPORTED, "stop keeps the reason")
	_check(DotMobileGyro.map_rates(0, 10, 20, 0) == Vector2(20, 10), "portrait: gamma yaws, beta pitches")
	_check(DotMobileGyro.map_rates(0, 10, 20, 90) == Vector2(10, -20), "landscape 90")
	_check(DotMobileGyro.map_rates(0, 10, 20, -90) == DotMobileGyro.map_rates(0, 10, 20, 270), "-90 is 270")
	g.feed(Vector2(100, 50), 0.05)
	g.feed(Vector2(100, 50), 5.0)
	_check(g.take(2.0).is_equal_approx(Vector2(30, 15)), "rates integrate, a long gap is capped, sensitivity scales")
	g.feed(Vector2(0, 10), 0.1)
	_check(g.take(1.0, true).is_equal_approx(Vector2(0, -1)), "invert flips pitch")


func _test_controls() -> void:
	_section("overlay drives the sampler")
	DotPlatform.touch_override = 0
	var tun := DotFpsTunables.new()
	var sampler := DotFpsTouchSampler.new(tun)
	var rules := DotMobileRules.new()
	rules.autofire = DotMobileRules.ALLOWED
	var c := DotMobileControls.new()
	c.rules = rules
	var layout: Array[Dictionary] = [
		{"id": &"fire", "label": "FIRE", "offset": Vector2(86, 150), "radius": 52.0},
		{"id": &"jump", "label": "JUMP", "offset": Vector2(200, 130), "radius": 42.0, "hold": DotFpsCommand.BUTTON_JUMP},
	]
	c.setup(sampler, layout)
	var kind: Array[int] = [DotMobileAutoFire.TARGET_NONE]
	c.crosshair_fn = func() -> int: return kind[0]
	c.autofire.reaction_s = 0.0
	add_child(c)
	await get_tree().process_frame
	_check(not c.touch and not c.visible, "no touch device: hidden")
	_check(not c.takes(_touch(0, Vector2(10, 10), true)), "and the game keeps its own input")
	c.prefs.touch = DotMobilePrefs.TOUCH_ON
	c.refresh()
	_check(c.touch and c.visible, "the player can force it on")
	DotPlatform.touch_override = 1
	c.prefs.touch = DotMobilePrefs.TOUCH_AUTO
	c.refresh()
	_check(c.touch, "a touch device shows it")
	_check(c.takes(_touch(0, Vector2(10, 10), true)), "the overlay takes touch events")
	var w := c.get_viewport().get_visible_rect().size.x
	var h := c.get_viewport().get_visible_rect().size.y
	sampler.handle_event(_touch(5, Vector2(w * 0.2, h * 0.5), true))
	_check(int(sampler.describe()["move_finger"]) == -1, "a touch the game forwards on its own is refused")
	c._input(_touch(1, Vector2(w * 0.2, h * 0.5), true))
	c._input(_drag(1, Vector2(w * 0.2, h * 0.5 - 90)))
	_check(sampler.sample(0.016).move.y > 0.9, "a stick push up walks forward")
	c._input(_touch(1, Vector2(w * 0.2, h * 0.5 - 90), false))
	_check(sampler.sample(0.016).move == Vector2.ZERO, "lifting stops")
	var yaw0 := sampler.yaw
	c._input(_touch(2, Vector2(w * 0.8, h * 0.4), true))
	c._input(_drag(2, Vector2(w * 0.8 + 40, h * 0.4)))
	var _cmd := sampler.sample(0.016)
	_check(sampler.yaw < yaw0, "dragging right turns right")
	c._input(_touch(2, Vector2(w * 0.8 + 40, h * 0.4), false))
	c.buttons._input(_touch(3, c.buttons.centre_of(&"jump"), true))
	_check(c.is_held(&"jump") and sampler.sample(0.016).buttons & DotFpsCommand.BUTTON_JUMP != 0,
			"a declared button holds its command bit")
	c.buttons._input(_touch(3, c.buttons.centre_of(&"jump"), false))
	_check(sampler.sample(0.016).buttons & DotFpsCommand.BUTTON_JUMP == 0, "and releases it")
	kind[0] = DotMobileAutoFire.TARGET_ENEMY
	await get_tree().process_frame
	_check(c.is_held(&"fire"), "auto-fire holds fire on an enemy")
	kind[0] = DotMobileAutoFire.TARGET_FRIEND
	await get_tree().process_frame
	_check(not c.is_held(&"fire"), "and lets go on a teammate")
	rules.schemes = DotMobileRules.SCHEME_DRAG
	await get_tree().process_frame
	c._input(_touch(4, Vector2(w * 0.2, h * 0.5), true))
	_check(int(sampler.describe()["move_finger"]) == -1, "a disallowed stick takes no finger")
	rules.buttons = PackedStringArray(["fire"])
	await get_tree().process_frame
	_check(c.buttons.radius_of(&"jump") <= 0.0 and c.buttons.radius_of(&"fire") > 0.0, "the server hides buttons")
	rules.touch_enabled = false
	await get_tree().process_frame
	_check(not c.touch and not c.visible, "the server can switch the overlay off live")
	c.queue_free()
	await get_tree().process_frame


func _test_left_handed() -> void:
	_section("left-handed layout")
	DotPlatform.touch_override = 1
	var sampler := DotFpsTouchSampler.new(DotFpsTunables.new())
	var c := DotMobileControls.new()
	c.prefs.left_handed = true
	var layout: Array[Dictionary] = [{"id": &"fire", "label": "FIRE", "offset": Vector2(86, 150), "radius": 52.0}]
	c.setup(sampler, layout)
	add_child(c)
	await get_tree().process_frame
	var w := c.get_viewport().get_visible_rect().size.x
	var h := c.get_viewport().get_visible_rect().size.y
	var left := c.buttons.centre_of(&"fire")
	c.buttons.mirrored = false
	var right := c.buttons.centre_of(&"fire")
	c.buttons.mirrored = true
	_check(is_equal_approx(left.x, c.buttons.size.x - right.x) and left.y == right.y, "buttons mirror to the left")
	c._input(_touch(1, Vector2(w * 0.8, h * 0.5), true))
	c._input(_drag(1, Vector2(w * 0.8 + 90, h * 0.5)))
	_check(sampler.sample(0.016).move.x > 0.9, "the stick is on the right")
	var yaw0 := sampler.yaw
	c._input(_touch(2, Vector2(w * 0.2, h * 0.5), true))
	c._input(_drag(2, Vector2(w * 0.2 - 40, h * 0.5)))
	var _cmd := sampler.sample(0.016)
	_check(sampler.yaw > yaw0, "and look is on the left")
	c.rules.left_handed_allowed = false
	await get_tree().process_frame
	_check(not c.buttons.mirrored and int(sampler.describe()["move_finger"]) == -1,
			"a server ban un-mirrors and lifts the fingers")
	c.queue_free()
	await get_tree().process_frame


func _touch(index: int, at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = pressed
	return e


func _drag(index: int, at: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	return e


func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("[%s]" % title)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		_line("  ok   " + what)
	else:
		_failed += 1
		_line("  FAIL " + what)


func _line(text: String) -> void:
	print(text)
