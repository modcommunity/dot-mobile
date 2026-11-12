class_name DotMobileAutoFire
extends RefCounted

## Presses fire while the crosshair rests on an enemy. It only decides when the fire button is down; the game sends
## that through the same bit a finger on Fire sets, so fire modes, cooldowns and ammunition stay the simulation's.
## What is under the crosshair is the game's own camera ray, handed in as a [constant TARGET_NONE]-style kind.

const TARGET_NONE := 0
const TARGET_ENEMY := 1
## A teammate, a corpse or anything else that must never be shot at on purpose: it releases at once.
const TARGET_FRIEND := 2

## Seconds the crosshair must stay on an enemy before the first press, so sweeping past one does not fire.
var reaction_s: float = 0.09
## True holds the button for an automatic weapon; false pulses it, one press per shot, for a semi-automatic one.
var automatic: bool = true
## A pulse's down and up time, seconds. Longer than a tick at 30 Hz, so a sampled tick always sees each edge.
var pulse_s: float = 0.05

## Whether the button is down this frame.
var firing: bool = false

var _on_enemy_s: float = 0.0
var _pulse_left: float = 0.0


## Advances by [param delta] seconds with [param target] under the crosshair; returns [member firing].
## [param enabled] false (rules, prefs, a dead or spectating player) releases and forgets the target.
func update(delta: float, target: int, enabled: bool = true) -> bool:
	if not enabled or target != TARGET_ENEMY:
		reset()
		return false
	_on_enemy_s += maxf(0.0, delta)
	if _on_enemy_s < reaction_s:
		firing = false
		return false
	if automatic:
		firing = true
		return true
	_pulse_left -= delta
	if _pulse_left <= 0.0:
		firing = not firing
		_pulse_left = pulse_s
	return firing


## What is under a ray, for a game without its own crosshair query: one [method PhysicsDirectSpaceState3D.intersect_ray]
## from [param from] along [param dir], the collider handed to [param classify] (Object -> TARGET_*). Pass the eye and
## aim the hitscan uses, and exclude the shooter's own bodies, so auto-fire sees what a shot would hit.
static func ray_target(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, reach: float, classify: Callable,
		exclude: Array[RID] = [], mask: int = 0xFFFFFFFF) -> int:
	if space == null or not classify.is_valid() or dir.length_squared() < 0.000001:
		return TARGET_NONE
	var query := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * reach, mask, exclude)
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return TARGET_NONE
	var collider: Object = hit.get("collider")
	return int(classify.call(collider)) if collider != null else TARGET_NONE


func reset() -> void:
	firing = false
	_on_enemy_s = 0.0
	_pulse_left = 0.0


func describe() -> Dictionary:
	return {"firing": firing, "automatic": automatic, "on_enemy_s": snappedf(_on_enemy_s, 0.01)}
