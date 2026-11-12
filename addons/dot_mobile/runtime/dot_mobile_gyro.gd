class_name DotMobileGyro
extends RefCounted

## The phone's own rotation as look input, on the web only, through dot-core's [DotWeb] (no page script, no eval).
## iOS asks the player first and only from a user gesture, so [method start] arms a one-shot listener on the next
## touch and asks inside it. Off the web, with no motion sensor or when refused, every call is a no-op.

const CHANNEL := "mobile.gyro"

enum State { OFF, UNSUPPORTED, WAITING_FOR_GESTURE, ASKING, DENIED, RUNNING }

const _CB_MOTION := "dot_mobile.gyro_motion"
const _CB_GESTURE := "dot_mobile.gyro_gesture"
const _CB_GRANTED := "dot_mobile.gyro_granted"
const _CB_REFUSED := "dot_mobile.gyro_refused"
const _CALLBACKS: Array[String] = [_CB_MOTION, _CB_GESTURE, _CB_GRANTED, _CB_REFUSED]

## A gap between two motion events longer than this (seconds) counts as this long: a backgrounded tab must not lurch.
const MAX_GAP_S := 0.1

var state: State = State.OFF

## Degrees (yaw, pitch) turned since the last [method take], before sensitivity.
var _pending: Vector2 = Vector2.ZERO
var _last_us: int = 0
var _motion_cb: Variant = null
var _gesture_cb: Variant = null


## Yaw and pitch rates (degrees per second, the sampler's signs) from DeviceMotion's rotationRate and the screen
## orientation [param angle] (0, 90, 180, 270). Not verified on every phone: a player can invert pitch in prefs.
static func map_rates(alpha: float, beta: float, gamma: float, angle: int) -> Vector2:
	var _unused := alpha
	match posmod(angle, 360):
		90:
			return Vector2(beta, -gamma)
		180:
			return Vector2(-gamma, -beta)
		270:
			return Vector2(-beta, gamma)
	return Vector2(gamma, beta)


func is_running() -> bool:
	return state == State.RUNNING


## Starts listening, asking first where the browser wants a gesture. Safe to call again; a refusal is final for the page.
func start() -> void:
	if state in [State.RUNNING, State.WAITING_FOR_GESTURE, State.ASKING, State.DENIED, State.UNSUPPORTED]:
		return
	if not DotWeb.available():
		state = State.UNSUPPORTED
		return
	var motion_event: Variant = DotWeb.get_global("DeviceMotionEvent")
	if motion_event == null:
		state = State.UNSUPPORTED
		return
	if motion_event.requestPermission == null:
		_listen()
		return
	var doc: Variant = DotWeb.get_global("document")
	_gesture_cb = DotWeb.create_callback(_CB_GESTURE, _on_gesture)
	if doc == null or _gesture_cb == null:
		state = State.UNSUPPORTED
		return
	doc.addEventListener("touchend", _gesture_cb)
	state = State.WAITING_FOR_GESTURE


## Stops listening and releases every callback; the player can start it again.
func stop() -> void:
	var win: Variant = DotWeb.get_global("window")
	var doc: Variant = DotWeb.get_global("document")
	if win != null and _motion_cb != null:
		win.removeEventListener("devicemotion", _motion_cb)
	if doc != null and _gesture_cb != null:
		doc.removeEventListener("touchend", _gesture_cb)
	for key in _CALLBACKS:
		DotWeb.release_callback(key)
	_motion_cb = null
	_gesture_cb = null
	_pending = Vector2.ZERO
	if state != State.DENIED and state != State.UNSUPPORTED:
		state = State.OFF


## Degrees (yaw, pitch) the phone turned since the last call, times [param sensitivity]; zero when not running.
func take(sensitivity: float = 1.0, invert_y: bool = false) -> Vector2:
	var out := _pending * sensitivity
	_pending = Vector2.ZERO
	if invert_y:
		out.y = -out.y
	return out


## Adds one motion sample by hand, as the browser's callback does. For a suite.
func feed(rates: Vector2, seconds: float) -> void:
	_pending += rates * clampf(seconds, 0.0, MAX_GAP_S)


func _listen() -> void:
	var win: Variant = DotWeb.get_global("window")
	_motion_cb = DotWeb.create_callback(_CB_MOTION, _on_motion)
	if win == null or _motion_cb == null:
		state = State.UNSUPPORTED
		return
	win.addEventListener("devicemotion", _motion_cb)
	_last_us = 0
	state = State.RUNNING
	DotLog.info(CHANNEL, "gyro look running")


func _on_gesture(_args: Array) -> void:
	if state != State.WAITING_FOR_GESTURE:
		return
	var doc: Variant = DotWeb.get_global("document")
	if doc != null and _gesture_cb != null:
		doc.removeEventListener("touchend", _gesture_cb)
	var motion_event: Variant = DotWeb.get_global("DeviceMotionEvent")
	if motion_event == null:
		state = State.UNSUPPORTED
		return
	state = State.ASKING
	# Called synchronously inside the touchend, which is the only place iOS accepts the request from.
	var asked: Variant = motion_event.requestPermission()
	var granted: Variant = DotWeb.create_callback(_CB_GRANTED, _on_answer)
	var refused: Variant = DotWeb.create_callback(_CB_REFUSED, _on_refused)
	if asked == null or granted == null:
		state = State.UNSUPPORTED
		return
	asked.then(granted, refused)


func _on_answer(args: Array) -> void:
	var answer := str(args[0]) if args.size() > 0 else ""
	if answer == "granted":
		_listen()
	else:
		state = State.DENIED
		DotLog.info(CHANNEL, "gyro look refused by the player", {"answer": answer})


func _on_refused(_args: Array) -> void:
	state = State.DENIED


func _on_motion(args: Array) -> void:
	if state != State.RUNNING or args.is_empty() or args[0] == null:
		return
	var now := Time.get_ticks_usec()
	var gap := 0.0 if _last_us == 0 else float(now - _last_us) / 1000000.0
	_last_us = now
	var rate: Variant = args[0].rotationRate
	if rate == null or gap <= 0.0:
		return
	var rates := map_rates(_read(rate.alpha), _read(rate.beta), _read(rate.gamma), _screen_angle())
	feed(rates, gap)


static func _read(value: Variant) -> float:
	if value is float or value is int:
		return float(value) if is_finite(float(value)) else 0.0
	return 0.0


static func _screen_angle() -> int:
	var screen: Variant = DotWeb.get_global("screen")
	if screen != null and screen.orientation != null:
		return int(_read(screen.orientation.angle))
	var win: Variant = DotWeb.get_global("window")
	return int(_read(win.orientation)) if win != null else 0


func describe() -> Dictionary:
	return {"state": State.keys()[state], "pending": _pending}
