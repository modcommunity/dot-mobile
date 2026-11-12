class_name DotMobilePrefs
extends RefCounted

## A touch player's own choices. Plain values with no rules: [method DotMobileRules.resolve] bounds them by what the server allows.
## The game stores them where it stores settings ([method to_dict] / [method from_dict]); nothing here touches a disk.

const TOUCH_AUTO := -1
const TOUCH_OFF := 0
const TOUCH_ON := 1

## [constant TOUCH_AUTO] shows the overlay on a touch device; the others force it.
var touch: int = TOUCH_AUTO
## The on-screen stick moves; the drag side looks; the phone's rotation looks.
var stick: bool = true
var drag: bool = true
var gyro: bool = false
## Degrees of view per pixel dragged.
var look_sensitivity: float = 0.16
## Multiplier on the phone's own rotation; 1 turns the view as far as the phone turned.
var gyro_sensitivity: float = 1.0
var gyro_invert_y: bool = false
## Mirrors the layout: stick on the right, look on the left, buttons on the left.
var left_handed: bool = false
var aim_assist: bool = false
var autofire: bool = true


func copy() -> DotMobilePrefs:
	var out := DotMobilePrefs.new()
	out.from_dict(to_dict())
	return out


func to_dict() -> Dictionary:
	return {
		"touch": touch, "stick": stick, "drag": drag, "gyro": gyro, "look_sensitivity": look_sensitivity,
		"gyro_sensitivity": gyro_sensitivity, "gyro_invert_y": gyro_invert_y, "left_handed": left_handed,
		"aim_assist": aim_assist, "autofire": autofire,
	}


## Reads what [method to_dict] wrote; a missing or mistyped key keeps its current value.
func from_dict(data: Dictionary) -> void:
	touch = clampi(int(_num(data, "touch", touch)), TOUCH_AUTO, TOUCH_ON)
	stick = _flag(data, "stick", stick)
	drag = _flag(data, "drag", drag)
	gyro = _flag(data, "gyro", gyro)
	look_sensitivity = clampf(_num(data, "look_sensitivity", look_sensitivity), DotMobileRules.SENS_FLOOR, DotMobileRules.SENS_CEILING)
	gyro_sensitivity = clampf(_num(data, "gyro_sensitivity", gyro_sensitivity), 0.1, 4.0)
	gyro_invert_y = _flag(data, "gyro_invert_y", gyro_invert_y)
	left_handed = _flag(data, "left_handed", left_handed)
	aim_assist = _flag(data, "aim_assist", aim_assist)
	autofire = _flag(data, "autofire", autofire)


static func _flag(data: Dictionary, key: String, fallback: bool) -> bool:
	var v: Variant = data.get(key, fallback)
	return v if v is bool else fallback


static func _num(data: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = data.get(key, fallback)
	if (v is float or v is int) and is_finite(float(v)):
		return float(v)
	return fallback


func describe() -> Dictionary:
	return to_dict()
