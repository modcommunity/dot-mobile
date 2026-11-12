class_name DotMobileRules
extends RefCounted

## What a server lets touch players (and, for auto-fire, everybody) use: replicated cvars, each clamped here.
## The server registers them with [method bind_cvars], a client follows them with [method follow_cvars] and asks
## [method resolve] what its own [DotMobilePrefs] come to. Presentation and input only: the simulation never reads these.

## Emitted when any rule changes, from a cvar or by hand.
signal changed

const CHANNEL := "mobile.rules"

const CVAR_TOUCH := "sv_mobile_touch"
const CVAR_SCHEMES := "sv_mobile_schemes"
const CVAR_SENS_MIN := "sv_mobile_sens_min"
const CVAR_SENS_MAX := "sv_mobile_sens_max"
const CVAR_LEFT_HANDED := "sv_mobile_left_handed"
const CVAR_BUTTONS := "sv_mobile_buttons"
const CVAR_AIM_ASSIST := "sv_aim_assist"
const CVAR_AIM_STRENGTH := "sv_aim_assist_strength"
const CVAR_AUTOFIRE := "sv_autofire"
const CVAR_AUTOFIRE_DESKTOP := "sv_autofire_desktop"

const ALL_CVARS: Array[String] = [
	CVAR_TOUCH, CVAR_SCHEMES, CVAR_SENS_MIN, CVAR_SENS_MAX, CVAR_LEFT_HANDED, CVAR_BUTTONS,
	CVAR_AIM_ASSIST, CVAR_AIM_STRENGTH, CVAR_AUTOFIRE, CVAR_AUTOFIRE_DESKTOP,
]

## Look schemes, as bits of [member schemes].
const SCHEME_STICK := 1
const SCHEME_DRAG := 2
const SCHEME_GYRO := 4
const SCHEME_ALL := 7
const SCHEME_NAMES := {"stick": SCHEME_STICK, "drag": SCHEME_DRAG, "gyro": SCHEME_GYRO}

## [member aim_assist] and [member autofire]: never, the player's choice, always (for touch players).
const OFF := 0
const ALLOWED := 1
const FORCED := 2

## Bounds every look sensitivity (degrees per pixel dragged) is clamped to, whatever a server asks.
const SENS_FLOOR := 0.01
const SENS_CEILING := 2.0

## Whether the touch overlay may show at all.
var touch_enabled: bool = true:
	set(value):
		if value != touch_enabled:
			touch_enabled = value
			changed.emit()

## Which of stick, drag and gyro a touch player may use, [constant SCHEME_STICK] and friends OR'ed.
var schemes: int = SCHEME_ALL:
	set(value):
		value = value & SCHEME_ALL
		if value != schemes:
			schemes = value
			changed.emit()

var sens_min: float = 0.04:
	set(value):
		value = clampf(value, SENS_FLOOR, SENS_CEILING)
		if not is_equal_approx(value, sens_min):
			sens_min = value
			changed.emit()

var sens_max: float = 0.6:
	set(value):
		value = clampf(value, SENS_FLOOR, SENS_CEILING)
		if not is_equal_approx(value, sens_max):
			sens_max = value
			changed.emit()

## Whether a player may mirror the layout (stick on the right).
var left_handed_allowed: bool = true:
	set(value):
		if value != left_handed_allowed:
			left_handed_allowed = value
			changed.emit()

## Button ids a server shows; empty shows every one the game declared.
var buttons: PackedStringArray = PackedStringArray():
	set(value):
		if value != buttons:
			buttons = value
			changed.emit()

## [constant OFF] (the default), [constant ALLOWED] or [constant FORCED].
var aim_assist: int = OFF:
	set(value):
		value = clampi(value, OFF, FORCED)
		if value != aim_assist:
			aim_assist = value
			changed.emit()

## 0 no pull to 1 the strongest; scales [DotMobileAimAssist]'s turn rate.
var aim_strength: float = 0.35:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if not is_equal_approx(value, aim_strength):
			aim_strength = value
			changed.emit()

## [constant OFF] (the default here; a game may default it on), [constant ALLOWED] or [constant FORCED].
var autofire: int = OFF:
	set(value):
		value = clampi(value, OFF, FORCED)
		if value != autofire:
			autofire = value
			changed.emit()

## Whether keyboard and mouse players get auto-fire too; off leaves them exactly as they were.
var autofire_desktop: bool = false:
	set(value):
		if value != autofire_desktop:
			autofire_desktop = value
			changed.emit()


## Whether the overlay shows for a device: the server allows it and the device has touch (or the player forced it).
func touch_active(prefs: DotMobilePrefs, has_touch: bool) -> bool:
	if not touch_enabled:
		return false
	if prefs != null and prefs.touch != DotMobilePrefs.TOUCH_AUTO:
		return prefs.touch == DotMobilePrefs.TOUCH_ON
	return has_touch


func allows_scheme(bit: int) -> bool:
	return (schemes & bit) != 0


func shows_button(id: StringName) -> bool:
	return buttons.is_empty() or buttons.has(String(id))


## Whether aim assist runs for this player. Touch players only: a mouse needs no help.
func aim_assist_on(prefs: DotMobilePrefs, touch: bool) -> bool:
	if not touch or aim_assist == OFF or aim_strength <= 0.0:
		return false
	return aim_assist == FORCED or (prefs != null and prefs.aim_assist)


## Whether auto-fire runs for this player; a keyboard player only under [member autofire_desktop].
func autofire_on(prefs: DotMobilePrefs, touch: bool) -> bool:
	if autofire == OFF or (not touch and not autofire_desktop):
		return false
	return autofire == FORCED or (prefs != null and prefs.autofire)


## [param prefs] as this server allows them, for a [param touch] player: a copy, the original is untouched.
func resolve(prefs: DotMobilePrefs, touch: bool) -> DotMobilePrefs:
	var out := prefs.copy() if prefs != null else DotMobilePrefs.new()
	out.stick = out.stick and allows_scheme(SCHEME_STICK)
	out.drag = out.drag and allows_scheme(SCHEME_DRAG)
	out.gyro = out.gyro and allows_scheme(SCHEME_GYRO)
	out.left_handed = out.left_handed and left_handed_allowed
	var low := minf(sens_min, sens_max)
	var high := maxf(sens_min, sens_max)
	out.look_sensitivity = clampf(out.look_sensitivity, low, high)
	out.aim_assist = aim_assist_on(prefs, touch)
	out.autofire = autofire_on(prefs, touch)
	return out


# Server cvars

func cvar_specs() -> Array[Dictionary]:
	return [
		{"name": CVAR_TOUCH, "value": "1" if touch_enabled else "0", "min": 0.0, "max": 1.0,
			"description": "1 shows the on-screen touch controls on touch devices, 0 never"},
		{"name": CVAR_SCHEMES, "value": schemes_text(schemes),
			"description": "Look and move schemes a touch player may use, comma separated: stick, drag, gyro"},
		{"name": CVAR_SENS_MIN, "value": str(sens_min), "min": SENS_FLOOR, "max": SENS_CEILING,
			"description": "Lowest touch look sensitivity a player may choose, degrees per pixel dragged"},
		{"name": CVAR_SENS_MAX, "value": str(sens_max), "min": SENS_FLOOR, "max": SENS_CEILING,
			"description": "Highest touch look sensitivity a player may choose, degrees per pixel dragged"},
		{"name": CVAR_LEFT_HANDED, "value": "1" if left_handed_allowed else "0", "min": 0.0, "max": 1.0,
			"description": "1 lets a touch player mirror the layout (stick on the right), 0 does not"},
		{"name": CVAR_BUTTONS, "value": ",".join(buttons),
			"description": "On-screen buttons shown, comma separated ids; empty shows every one the game declares"},
		{"name": CVAR_AIM_ASSIST, "value": str(aim_assist), "min": float(OFF), "max": float(FORCED),
			"description": "Aim assist for touch players: 0 off, 1 a player may turn it on, 2 always on"},
		{"name": CVAR_AIM_STRENGTH, "value": str(aim_strength), "min": 0.0, "max": 1.0,
			"description": "Aim assist strength, 0 no pull to 1 the strongest"},
		{"name": CVAR_AUTOFIRE, "value": str(autofire), "min": float(OFF), "max": float(FORCED),
			"description": "Auto-fire when the crosshair is on an enemy: 0 off, 1 a player may turn it off, 2 always on"},
		{"name": CVAR_AUTOFIRE_DESKTOP, "value": "1" if autofire_desktop else "0", "min": 0.0, "max": 1.0,
			"description": "1 gives keyboard and mouse players auto-fire under sv_autofire too, 0 only touch players"},
	]


## Registers the cvars through [param add] (a server module's `add_cvar`, shaped `(name, default, description,
## flags) -> cvar`) and keeps these rules in step. Pass FLAG_REPLICATED. Duck-typed: dot-server is not a dependency.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []
	for spec in cvar_specs():
		var cvar_name: String = spec["name"]
		var made_cvar: Variant = add.call(cvar_name, String(spec["value"]), String(spec["description"]), flags)
		if not (made_cvar is Object) or made_cvar == null:
			continue
		var cv := made_cvar as Object
		if spec.has("min") and cv.has_method(&"with_range"):
			cv.call(&"with_range", float(spec["min"]), float(spec["max"]))
		if cv.has_signal(&"changed"):
			var on_change := _on_cvar_changed.bind(cvar_name)
			if not cv.is_connected(&"changed", on_change):
				cv.connect(&"changed", on_change)
		if cv.has_method(&"get_string"):
			var _applied := set_cvar(cvar_name, String(cv.call(&"get_string")))
		made.append(cv)
	return made


## Follows a server's values through [param source] (anything with `replicated_cvar(name, fallback)` and a
## `replicated_cvar_changed(name, value)` signal). False when it cannot; the rules keep their own.
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false
	for cv in ALL_CVARS:
		var held := String(source.call(&"replicated_cvar", cv, ""))
		if held != "" or cv == CVAR_BUTTONS:
			var _applied := set_cvar(cv, held)
	if not source.is_connected(&"replicated_cvar_changed", _on_replicated_cvar):
		source.connect(&"replicated_cvar_changed", _on_replicated_cvar)
	return true


## Applies one cvar by name. False for another name or a value it cannot read; numbers are clamped, not refused.
func set_cvar(cvar_name: String, value: String) -> bool:
	var text := value.strip_edges()
	match cvar_name:
		CVAR_SCHEMES:
			var bits := parse_schemes(text)
			if bits < 0:
				return false
			schemes = bits
			return true
		CVAR_BUTTONS:
			var ids := PackedStringArray()
			for part in text.split(",", false):
				var id := part.strip_edges()
				if id != "":
					ids.append(id)
			buttons = ids
			return true
		CVAR_SENS_MIN, CVAR_SENS_MAX, CVAR_AIM_STRENGTH:
			if not text.is_valid_float() or not is_finite(text.to_float()):
				return false
			if cvar_name == CVAR_SENS_MIN:
				sens_min = text.to_float()
			elif cvar_name == CVAR_SENS_MAX:
				sens_max = text.to_float()
			else:
				aim_strength = text.to_float()
			return true
		CVAR_TOUCH, CVAR_LEFT_HANDED, CVAR_AIM_ASSIST, CVAR_AUTOFIRE, CVAR_AUTOFIRE_DESKTOP:
			if not text.is_valid_int():
				DotLog.debug(CHANNEL, "refused a value", {"cvar": cvar_name, "value": value})
				return false
			var n := text.to_int()
			if cvar_name == CVAR_TOUCH:
				touch_enabled = n != 0
			elif cvar_name == CVAR_LEFT_HANDED:
				left_handed_allowed = n != 0
			elif cvar_name == CVAR_AUTOFIRE_DESKTOP:
				autofire_desktop = n != 0
			elif cvar_name == CVAR_AIM_ASSIST:
				aim_assist = n
			else:
				autofire = n
			return true
	return false


## "stick,drag" or a bit mask ("3") to bits; -1 for an unknown name. Empty is no scheme at all.
static func parse_schemes(text: String) -> int:
	if text.is_valid_int():
		return text.to_int() & SCHEME_ALL
	var bits := 0
	for part in text.to_lower().split(",", false):
		var key := part.strip_edges()
		if key == "":
			continue
		if not SCHEME_NAMES.has(key):
			return -1
		bits |= int(SCHEME_NAMES[key])
	return bits


static func schemes_text(bits: int) -> String:
	var names := PackedStringArray()
	for key: String in SCHEME_NAMES:
		if bits & int(SCHEME_NAMES[key]):
			names.append(key)
	return ",".join(names)


func _on_cvar_changed(_old: Variant, new_value: Variant, cvar_name: String) -> void:
	var _applied := set_cvar(cvar_name, str(new_value))


func _on_replicated_cvar(cvar_name: String, value: String) -> void:
	if cvar_name in ALL_CVARS:
		var _applied := set_cvar(cvar_name, value)


func describe() -> Dictionary:
	return {
		"touch": touch_enabled, "schemes": schemes_text(schemes), "sens": "%.2f..%.2f" % [sens_min, sens_max],
		"left_handed": left_handed_allowed, "buttons": ",".join(buttons), "aim_assist": aim_assist,
		"aim_strength": aim_strength, "autofire": autofire, "autofire_desktop": autofire_desktop,
	}
