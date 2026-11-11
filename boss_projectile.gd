
extends Node2D

var target: Node2D = null
var direction: Vector2 = Vector2.RIGHT
var speed: float = 340.0
var damage: int = 1

var life_remaining: float = 4.0
var hit_radius: float = 28.0
var has_hit: bool = false


func setup(
	target_node: Node2D,
	move_direction: Vector2,
	move_speed: float,
	attack_damage: int
) -> void:
	target = target_node
	direction = move_direction.normalized()
	speed = move_speed
	damage = attack_damage

	if direction.length_squared() < 0.001:
		direction = Vector2.RIGHT

	queue_redraw()


func _process(delta: float) -> void:
	if has_hit:
		return

	life_remaining -= delta

	if life_remaining <= 0.0:
		queue_free()
		return

	global_position += direction * speed * delta

	if not is_instance_valid(target):
		queue_free()
		return

	if global_position.distance_to(target.global_position) <= hit_radius:
		has_hit = true

		if target.has_method("take_damage"):
			target.call("take_damage", damage)

		queue_free()
		return

	queue_redraw()


func _draw() -> void:
	# 子彈尾跡
	draw_line(
		-direction * 19.0,
		Vector2.ZERO,
		Color(1.0, 0.18, 0.22, 0.8),
		5.0,
		true
	)

	# 子彈外圈
	draw_circle(
		Vector2.ZERO,
		8.0,
		Color(1.0, 0.13, 0.22)
	)

	# 子彈核心
	draw_circle(
		Vector2.ZERO,
		3.5,
		Color(1.0, 0.8, 0.72)
	)
