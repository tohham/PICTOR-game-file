
extends StaticBody2D

# ==========================================
# 動畫設定
# ==========================================

@export var animation_sprite_path: NodePath = NodePath("AnimatedSprite2D")

@export var idle_animation: StringName = &"idle"
@export var counterattack_animation: StringName = &"反擊"

@export_group("朝向")
@export var art_faces_right_when_unflipped: bool = true

@export_group("存在時間")
@export var lifetime_seconds: float = 7.0

@export_group("地面定位")
@export var ground_clearance: float = 4.0
@export var floor_ray_start_height: float = 2000.0
@export var floor_ray_length: float = 4000.0
@export_flags_2d_physics var floor_collision_mask: int = 0xFFFFFFFF

@export_group("碰撞箱")
@export_range(0.3, 1.0, 0.05)
var collision_width_ratio: float = 0.72

@export_range(0.3, 1.0, 0.05)
var collision_height_ratio: float = 0.90

@export_group("反彈判定")
@export var projectile_reflect_radius: float = 75.0
@export var projectile_reflect_offset: Vector2 = Vector2(35.0, -40.0)

@export_range(1.0, 5.0, 0.1)
var reflected_damage_multiplier: float = 2.0


# ==========================================
# 狀態
# ==========================================

var animation_sprite: AnimatedSprite2D = null
var body_collision: CollisionShape2D = null

var guard_owner: Node2D = null
var guard_hits_remaining: int = 3

var is_counterattacking: bool = false
var remove_after_counterattack: bool = false

var lifetime_remaining: float = 0.0


# ==========================================
# 初始化
# ==========================================

func _ready() -> void:
	add_to_group("defense_elephant")

	collision_layer = 1
	collision_mask = 1

	animation_sprite = get_node_or_null(
		animation_sprite_path
	) as AnimatedSprite2D

	if animation_sprite == null:
		animation_sprite = _find_animated_sprite(self)

	if animation_sprite == null:
		push_error("Elephant：找不到 AnimatedSprite2D。")
		_setup_collision_fallback()
		return

	if animation_sprite.sprite_frames == null:
		push_error("Elephant：尚未設定 SpriteFrames。")
		_setup_collision_fallback()
		return

	var frames: SpriteFrames = animation_sprite.sprite_frames

	if not frames.has_animation(idle_animation):
		push_error("Elephant：SpriteFrames 找不到 idle 動畫。")
		_setup_collision_fallback()
		return

	if not frames.has_animation(counterattack_animation):
		push_error("Elephant：SpriteFrames 找不到反擊動畫。")
		_setup_collision_fallback()
		return

	frames.set_animation_loop(idle_animation, true)
	frames.set_animation_loop(counterattack_animation, false)

	if not animation_sprite.animation_finished.is_connected(
		_on_animation_finished
	):
		animation_sprite.animation_finished.connect(
			_on_animation_finished
		)

	_setup_body_collision()
	_setup_ground_anchor()
	_play_idle()


func _process(delta: float) -> void:
	if lifetime_remaining <= 0.0:
		return

	if is_queued_for_deletion():
		return

	lifetime_remaining -= delta

	if lifetime_remaining <= 0.0:
		lifetime_remaining = 0.0
		print("大象存在時間結束，已消失。")
		queue_free()


func _find_animated_sprite(node: Node) -> AnimatedSprite2D:
	for child: Node in node.get_children():
		if child is AnimatedSprite2D:
			return child as AnimatedSprite2D

		var found: AnimatedSprite2D = _find_animated_sprite(child)

		if found != null:
			return found

	return null


# ==========================================
# 建立及設定碰撞箱
# ==========================================

func _setup_body_collision() -> void:
	body_collision = get_node_or_null(
		"CollisionShape2D"
	) as CollisionShape2D

	if body_collision == null:
		body_collision = CollisionShape2D.new()
		body_collision.name = "CollisionShape2D"
		add_child(body_collision)

	var rectangle: RectangleShape2D = (
		body_collision.shape as RectangleShape2D
	)

	if rectangle == null:
		rectangle = RectangleShape2D.new()
		body_collision.shape = rectangle

	var frame_texture: Texture2D = (
		animation_sprite.sprite_frames.get_frame_texture(
			idle_animation,
			0
		)
	)

	var texture_width: float = 160.0
	var texture_height: float = 160.0

	if frame_texture != null:
		texture_width = float(frame_texture.get_width())
		texture_height = float(frame_texture.get_height())

	var rendered_width: float = (
		texture_width * absf(animation_sprite.scale.x)
	)

	var rendered_height: float = (
		texture_height * absf(animation_sprite.scale.y)
	)

	rectangle.size = Vector2(
		maxf(20.0, rendered_width * collision_width_ratio),
		maxf(20.0, rendered_height * collision_height_ratio)
	)

	body_collision.position = Vector2(
		0.0,
		-rendered_height * collision_height_ratio * 0.5
	)

	body_collision.disabled = false


func _setup_collision_fallback() -> void:
	body_collision = get_node_or_null(
		"CollisionShape2D"
	) as CollisionShape2D

	if body_collision == null:
		body_collision = CollisionShape2D.new()
		body_collision.name = "CollisionShape2D"
		add_child(body_collision)

	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(100.0, 100.0)

	body_collision.shape = rectangle
	body_collision.disabled = false


# ==========================================
# 圖片與地面定位
# ==========================================

func _setup_ground_anchor() -> void:
	if not is_instance_valid(animation_sprite):
		return

	if animation_sprite.sprite_frames == null:
		return

	var frame_texture: Texture2D = (
		animation_sprite.sprite_frames.get_frame_texture(
			idle_animation,
			0
		)
	)

	if frame_texture == null:
		return

	var rendered_height: float = (
		float(frame_texture.get_height())
		* absf(animation_sprite.scale.y)
	)

	animation_sprite.position.y = -rendered_height * 0.5


# ==========================================
# 尋找地板
# ==========================================

func _find_floor_position(spawn_position: Vector2) -> Vector2:
	var space_state := get_world_2d().direct_space_state

	var ray_start: Vector2 = (
		spawn_position
		- Vector2(0.0, floor_ray_start_height)
	)

	var ray_end: Vector2 = (
		spawn_position
		+ Vector2(0.0, floor_ray_length)
	)

	var query := PhysicsRayQueryParameters2D.create(
		ray_start,
		ray_end
	)

	query.collision_mask = floor_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var exclude_rids: Array[RID] = []

	exclude_rids.append(get_rid())

	if is_instance_valid(guard_owner):
		if guard_owner is CollisionObject2D:
			exclude_rids.append(
				(guard_owner as CollisionObject2D).get_rid()
			)

	query.exclude = exclude_rids

	var result: Dictionary = space_state.intersect_ray(query)

	if result.is_empty():
		push_warning(
			"大象：射線沒有找到地板。召喚位置：%s" % spawn_position
		)

		return spawn_position - Vector2(
			0.0,
			ground_clearance
		)

	var floor_position: Vector2 = result["position"]

	print(
		"大象找到地板：",
		result["collider"],
		" 地板座標：",
		floor_position
	)

	return floor_position - Vector2(
		0.0,
		ground_clearance
	)


# ==========================================
# SpellSystem 呼叫的初始化介面
# ==========================================

func setup_guard(
	owner: Node2D,
	spawn_position: Vector2,
	hits: int
) -> void:
	guard_owner = owner

	global_position = _find_floor_position(spawn_position)

	guard_hits_remaining = maxi(1, hits)

	is_counterattacking = false
	remove_after_counterattack = false

	# 從放置完成時開始倒數。
	lifetime_remaining = maxf(0.1, lifetime_seconds)

	_play_idle()


# ==========================================
# Idle 動畫
# ==========================================

func _play_idle() -> void:
	if not is_instance_valid(animation_sprite):
		return

	if animation_sprite.sprite_frames == null:
		return

	if not animation_sprite.sprite_frames.has_animation(idle_animation):
		return

	if (
		animation_sprite.animation != idle_animation
		or not animation_sprite.is_playing()
	):
		animation_sprite.play(idle_animation)


# ==========================================
# 象鼻反擊動畫
# ==========================================

func _play_counterattack(
	incoming_direction: Vector2
) -> void:
	if not is_instance_valid(animation_sprite):
		return

	if animation_sprite.sprite_frames == null:
		return

	if not animation_sprite.sprite_frames.has_animation(
		counterattack_animation
	):
		return

	var source_direction: Vector2 = -incoming_direction

	if absf(source_direction.x) > 0.01:
		var should_face_right: bool = source_direction.x > 0.0

		animation_sprite.flip_h = (
			art_faces_right_when_unflipped != should_face_right
		)

	if is_counterattacking:
		return

	is_counterattacking = true
	animation_sprite.play(counterattack_animation)


func _on_animation_finished() -> void:
	if not is_instance_valid(animation_sprite):
		return

	if animation_sprite.animation != counterattack_animation:
		return

	is_counterattacking = false

	if remove_after_counterattack:
		queue_free()
		return

	_play_idle()


# ==========================================
# 飛盤反彈
# ==========================================

func try_reflect_projectile(
	projectile: Node2D,
	start_global: Vector2,
	end_global: Vector2
) -> bool:
	if guard_hits_remaining <= 0:
		return false

	if not is_instance_valid(projectile):
		return false

	if not projectile.has_method("reflect_from_elephant"):
		return false

	if projectile.is_in_group("reflected_projectile"):
		return false

	var incoming_direction: Vector2 = (
		end_global - start_global
	).normalized()

	if incoming_direction.length_squared() < 0.001:
		return false

	var reflect_center: Vector2 = (
		global_position + projectile_reflect_offset
	)

	var closest_point: Vector2 = _closest_point_on_segment(
		reflect_center,
		start_global,
		end_global
	)

	if closest_point.distance_to(reflect_center) > projectile_reflect_radius:
		return false

	var reflected: bool = bool(
		projectile.call(
			"reflect_from_elephant",
			closest_point,
			reflected_damage_multiplier
		)
	)

	if not reflected:
		return false

	guard_hits_remaining -= 1

	_play_counterattack(incoming_direction)

	print(
		"大象成功反彈飛盤！剩餘耐久：",
		guard_hits_remaining
	)

	if guard_hits_remaining <= 0:
		remove_after_counterattack = true

		if (
			not is_instance_valid(animation_sprite)
			or not animation_sprite.is_playing()
		):
			queue_free()

	return true


# ==========================================
# 線段最近點
# ==========================================

func _closest_point_on_segment(
	point: Vector2,
	segment_start: Vector2,
	segment_end: Vector2
) -> Vector2:
	var segment: Vector2 = segment_end - segment_start
	var length_squared: float = segment.length_squared()

	if length_squared <= 0.001:
		return segment_start

	var t: float = clampf(
		(point - segment_start).dot(segment) / length_squared,
		0.0,
		1.0
	)

	return segment_start + segment * t
