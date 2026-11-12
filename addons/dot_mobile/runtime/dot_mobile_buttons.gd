class_name DotMobileButtons
extends DotTouchButtons

## dot-ui's [DotTouchButtons], mirrorable for a left-handed player: the same offsets measured from the bottom-left.
## Drawing, hit testing and finger tracking are dot-ui's; only where a button's centre lands changes here.

## Buttons in the bottom-left corner instead of the bottom-right.
var mirrored: bool = false:
	set(value):
		if value != mirrored:
			mirrored = value
			queue_redraw()


func _centre(b: Dictionary) -> Vector2:
	var right := super._centre(b)
	return Vector2(size.x - right.x, right.y) if mirrored else right
