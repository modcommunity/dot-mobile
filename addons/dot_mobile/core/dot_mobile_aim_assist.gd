class_name DotMobileAimAssist
extends RefCounted

## Turns a touch player's view a little towards the nearest enemy inside a cone, while they are moving or looking.
## Client-side and before the command: it only changes the yaw and pitch the sampler sends, so the simulation, the
## hit registration and the lag compensation see an ordinary player who aimed. Angles are the sampler's degrees.

## Half-angle in degrees of the cone a target must be in to pull at all.
var cone_deg: float = 7.0
## Degrees per second the view turns at strength 1 with the target at the cone's centre line.
var rate_deg_s: float = 40.0
## Targets further than this (metres) do not pull.
var max_range: float = 80.0

## Index into the last [method step]'s targets that pulled, or -1. For a suite or a debug line.
var last_target: int = -1


## The unit forward vector of a view at [param yaw] / [param pitch] degrees (DotFpsSampler's convention).
static func direction(yaw: float, pitch: float) -> Vector3:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	return Vector3(-sin(y) * cos(p), sin(p), -cos(y) * cos(p))


## The (yaw, pitch) in degrees that look from [param from] at [param to].
static func angles_to(from: Vector3, to: Vector3) -> Vector2:
	var d := to - from
	var flat := Vector2(d.x, d.z).length()
	return Vector2(rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(atan2(d.y, flat)))


## The target in [param targets] nearest the crosshair inside the cone and range, or -1.
func pick(eye: Vector3, yaw: float, pitch: float, targets: PackedVector3Array) -> int:
	var forward := direction(yaw, pitch)
	var best := -1
	var best_cos := cos(deg_to_rad(cone_deg))
	for i in targets.size():
		var to := targets[i] - eye
		var dist := to.length()
		if dist < 0.01 or dist > max_range:
			continue
		var c := forward.dot(to / dist)
		if c > best_cos:
			best_cos = c
			best = i
	return best


## The (yaw, pitch) after [param delta] seconds of pull at [param strength] (0..1). Unchanged when nothing is in the cone.
## The pull fades towards the cone's edge, so a target leaving it lets go smoothly rather than snapping off.
func step(eye: Vector3, yaw: float, pitch: float, targets: PackedVector3Array, strength: float, delta: float) -> Vector2:
	last_target = -1
	if strength <= 0.0 or delta <= 0.0 or targets.is_empty():
		return Vector2(yaw, pitch)
	var i := pick(eye, yaw, pitch, targets)
	if i < 0:
		return Vector2(yaw, pitch)
	last_target = i
	var want := angles_to(eye, targets[i])
	var off := Vector2(wrapf(want.x - yaw, -180.0, 180.0), want.y - pitch)
	var angle := off.length()
	if angle < 0.0001:
		return Vector2(yaw, pitch)
	var fade := clampf(1.0 - angle / maxf(0.01, cone_deg), 0.0, 1.0)
	var turn := minf(angle, clampf(strength, 0.0, 1.0) * rate_deg_s * delta * (0.35 + 0.65 * fade))
	var moved := off / angle * turn
	return Vector2(wrapf(yaw + moved.x, -180.0, 180.0), pitch + moved.y)
