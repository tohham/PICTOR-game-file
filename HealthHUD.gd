
extends CanvasLayer

# =========================================================
# HealthHUD.gd — PICTOR
# 玩家血條固定右上角；Boss 血條跟隨頭頂
# 無文字、動態顏料流動
# =========================================================

@export_group("框圖路徑")
@export var player_frame_path: String = "res://ikay/ikay_icon/ikay_icon.png"
@export var boss_frame_path: String = "res://boss/boss_icon/boss_icon.png"

@export_group("血條尺寸")
@export var player_bar_size: Vector2 = Vector2(240, 48)
@export var boss_bar_size: Vector2 = Vector2(340, 54)

# Vector4 順序：左、上、右、下
@export var player_insets: Vector4 = Vector4(28, 12, 28, 12)
@export var boss_insets: Vector4 = Vector4(36, 14, 36, 14)

@export_group("玩家右上角定位")
@export var player_screen_margin: Vector2 = Vector2(24, 24)

@export_group("Boss 頭頂定位")
@export var boss_fallback_offset: Vector2 = Vector2(0, -150)
@export var boss_head_adjust: Vector2 = Vector2(0, -8)
@export var boss_bar_gap: float = 10.0

@export_group("顏料流動效果")
@export var flow_speed: float = 0.8
@export var pigment_density: float = 9.0
@export_range(0.0, 1.0) var pigment_strength: float = 0.8

@export_group("玩家顏料顏色")
@export var player_base_color: Color = Color("20bfc9")
@export var player_glow_color: Color = Color("c4ffff")

@export_group("Boss 顏料顏色")
@export var boss_base_color: Color = Color("d92845")
@export var boss_glow_color: Color = Color("ffb4be")


# =========================================================
# 顏料流動 Shader
# =========================================================

const PIGMENT_SHADER: String = """
shader_type canvas_item;

uniform vec4 base_tint : source_color = vec4(0.12, 0.75, 0.80, 1.0);
uniform vec4 glow_tint : source_color = vec4(0.80, 1.00, 1.00, 1.0);

uniform float flow_speed = 0.8;
uniform float pigment_density = 9.0;
uniform float pigment_strength = 0.8;

float hash_vec(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise_vec(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash_vec(i);
    float b = hash_vec(i + vec2(1.0, 0.0));
    float c = hash_vec(i + vec2(0.0, 1.0));
    float d = hash_vec(i + vec2(1.0, 1.0));

    return mix(
        mix(a, b, f.x),
        mix(c, d, f.x),
        f.y
    );
}

void fragment() {
    vec2 uv = UV;
    float t = TIME * flow_speed;

    float cloud_a = noise_vec(
        uv * vec2(pigment_density * 0.55, 4.0)
        + vec2(-t * 0.45, t * 0.18)
    );

    float cloud_b = noise_vec(
        uv * vec2(pigment_density * 1.25, 6.0)
        + vec2(-t * 0.85, t * 0.35)
    );

    // 扭曲流動方向，營造流動顏料的感覺
    vec2 warped_uv = uv;
    warped_uv.x += (cloud_a - 0.5) * 0.24;
    warped_uv.y += sin(uv.x * 8.0 + t * 1.2) * 0.035;

    float detail = noise_vec(
        warped_uv * vec2(pigment_density * 1.8, 7.0)
        + vec2(-t * 1.1, t * 0.42)
    );

    float wave = 0.5 + 0.5 * sin(
        (
            warped_uv.x * 7.0
            + warped_uv.y * 2.2
            + detail * 1.7
            + cloud_b * 0.8
        ) * 6.28318
        - t * 1.4
    );

    float pigment = mix(cloud_b, wave, 0.48);
    pigment = mix(pigment, detail, 0.25);

    vec3 dark_color = base_tint.rgb * 0.58;

    vec3 normal_color = mix(
        base_tint.rgb * 0.82,
        base_tint.rgb,
        cloud_a
    );

    vec3 final_color = mix(
        dark_color,
        normal_color,
        smoothstep(0.05, 0.85, pigment)
    );

    float highlights = smoothstep(0.56, 0.91, wave);
    highlights *= mix(0.55, 1.0, cloud_a);

    final_color = mix(
        final_color,
        glow_tint.rgb,
        highlights * pigment_strength
    );

    float pigment_shadow = smoothstep(0.62, 0.95, detail);

    final_color = mix(
        final_color,
        base_tint.rgb * 0.48,
        pigment_shadow * 0.20
    );

    COLOR = vec4(final_color, base_tint.a);
}
"""


var ui_root: Control

var player_data: Dictionary = {}
var boss_data: Dictionary = {}

# 這兩個參照可能指向已被 queue_free() 的物件，
# 所以每次使用前都要確認有效性。
var player_target: Node2D = null
var boss_target: Node2D = null

var target_scan_timer: float = 0.0


# =========================================================
# 初始化
# =========================================================

func _ready() -> void:
	# HUD 顯示在一般遊戲背景之上。
	layer = 1

	ui_root = Control.new()
	ui_root.name = "HealthHUDRoot"
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui_root)

	player_data = _create_bar(
		"IKAY",
		player_bar_size,
		player_insets,
		player_frame_path,
		player_base_color,
		player_glow_color
	)

	boss_data = _create_bar(
		"BOSS",
		boss_bar_size,
		boss_insets,
		boss_frame_path,
		boss_base_color,
		boss_glow_color
	)

	_resolve_targets()


func _process(delta: float) -> void:
	target_scan_timer -= delta

	if target_scan_timer <= 0.0:
		target_scan_timer = 0.5
		_resolve_targets()

	# 關鍵修正：在呼叫有 Node2D 型別參數的函式前，
	# 先將已被刪除的節點參照設成 null。
	if not is_instance_valid(player_target):
		player_target = null

	if not is_instance_valid(boss_target):
		boss_target = null

	# 玩家血條固定在螢幕右上角
	_update_player_corner_bar(
		player_target,
		player_data
	)

	# Boss 血條跟隨 Boss 頭頂
	_update_boss_bar(
		boss_target,
		boss_data
	)


# =========================================================
# 建立血條：不建立 Label，所以不會出現文字
# =========================================================

func _create_bar(
	bar_name: String,
	bar_size: Vector2,
	insets: Vector4,
	frame_path: String,
	base_color: Color,
	glow_color: Color
) -> Dictionary:

	var bar := Control.new()
	bar.name = bar_name + "_HealthBar"
	bar.size = bar_size
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(bar)

	var inner_size := Vector2(
		maxf(1.0, bar_size.x - insets.x - insets.z),
		maxf(1.0, bar_size.y - insets.y - insets.w)
	)

	# 暗色底槽
	var track := ColorRect.new()
	track.name = "Track"
	track.position = Vector2(insets.x, insets.y)
	track.size = inner_size
	track.color = Color("171923")
	track.clip_contents = true
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(track)

	# 動態顏料內條
	var fill := ColorRect.new()
	fill.name = "PigmentFlowFill"
	fill.size = inner_size
	fill.color = Color.WHITE
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := Shader.new()
	shader.code = PIGMENT_SHADER

	var material := ShaderMaterial.new()
	material.shader = shader

	material.set_shader_parameter("base_tint", base_color)
	material.set_shader_parameter("glow_tint", glow_color)
	material.set_shader_parameter("flow_speed", flow_speed)
	material.set_shader_parameter("pigment_density", pigment_density)
	material.set_shader_parameter("pigment_strength", pigment_strength)

	fill.material = material
	track.add_child(fill)

	# 框圖在顏料之上
	var frame := TextureRect.new()
	frame.name = "Frame"
	frame.position = Vector2.ZERO
	frame.size = bar_size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE

	if ResourceLoader.exists(frame_path):
		frame.texture = load(frame_path) as Texture2D
	else:
		push_warning("找不到血條框圖：" + frame_path)

	bar.add_child(frame)

	return {
		"root": bar,
		"track": track,
		"fill": fill
	}


# =========================================================
# 尋找角色；先清除失效參照，避免使用已刪除的物件
# =========================================================

func _resolve_targets() -> void:
	if not is_instance_valid(player_target):
		player_target = null

		var player_node := get_tree().get_first_node_in_group("player")

		if player_node is Node2D:
			player_target = player_node as Node2D
		else:
			var named_player := _find_named_node(
				get_tree().root,
                "ikay"
			)

			if named_player is Node2D:
				player_target = named_player as Node2D

	if not is_instance_valid(boss_target):
		boss_target = null

		var boss_node := get_tree().get_first_node_in_group("boss")

		if boss_node is Node2D:
			boss_target = boss_node as Node2D
		else:
			var named_boss := _find_named_node(
				get_tree().root,
                "boss"
			)

			if named_boss is Node2D:
				boss_target = named_boss as Node2D


func _find_named_node(root_node: Node, wanted_name: String) -> Node:
	if str(root_node.name).to_lower() == wanted_name.to_lower():
		return root_node

	for child in root_node.get_children():
		var found := _find_named_node(child, wanted_name)

		if found != null:
			return found

	return null


# =========================================================
# 玩家血條：固定在螢幕右上角
# =========================================================

func _update_player_corner_bar(
	target: Node2D,
	data: Dictionary
) -> void:

	if data.is_empty():
		return

	var bar: Control = data["root"]

	if not is_instance_valid(target):
		bar.visible = false
		return

	bar.visible = true

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	bar.position = Vector2(
		viewport_size.x - bar.size.x - player_screen_margin.x,
		player_screen_margin.y
	)

	var current_value := _read_numeric_property(
		target,
		[
			"current_health",
			"health",
			"current_hp",
			"hp",
			"life",
			"player_hp",
			"currentHealth",
            "currentHP"
		]
	)

	var maximum_value := _read_numeric_property(
		target,
		[
			"max_health",
			"max_hp",
			"maximum_health",
			"max_life",
			"maxHealth",
            "maxHP"
		]
	)

	_update_fill(data, current_value, maximum_value)


# =========================================================
# Boss 血條：跟隨 Boss 頭頂
# =========================================================

func _update_boss_bar(
	target: Node2D,
	data: Dictionary
) -> void:

	if data.is_empty():
		return

	var bar: Control = data["root"]

	if not is_instance_valid(target):
		bar.visible = false
		return

	var world_head := _get_head_world_position(
		target,
		boss_fallback_offset,
		boss_head_adjust
	)

	var canvas_transform := get_viewport().get_canvas_transform()
	var screen_head: Vector2 = canvas_transform * world_head
	var screen_target: Vector2 = canvas_transform * target.global_position
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	# Boss 離開畫面時隱藏血條
	if (
		screen_target.x < -100.0
		or screen_target.x > viewport_size.x + 100.0
		or screen_target.y < -100.0
		or screen_target.y > viewport_size.y + 100.0
	):
		bar.visible = false
		return

	bar.visible = true

	var desired_position := Vector2(
		screen_head.x - bar.size.x * 0.5,
		screen_head.y - bar.size.y - boss_bar_gap
	)

	var max_x := maxf(4.0, viewport_size.x - bar.size.x - 4.0)
	var max_y := maxf(4.0, viewport_size.y - bar.size.y - 4.0)

	bar.position = Vector2(
		clampf(desired_position.x, 4.0, max_x),
		clampf(desired_position.y, 4.0, max_y)
	)

	var current_value := _read_numeric_property(
		target,
		[
			"current_health",
			"health",
			"current_hp",
			"hp",
			"boss_health",
			"currentHealth",
            "currentHP"
		]
	)

	var maximum_value := _read_numeric_property(
		target,
		[
			"max_health",
			"max_hp",
			"maximum_health",
			"maxHealth",
            "maxHP"
		]
	)

	_update_fill(data, current_value, maximum_value)


# =========================================================
# 根據生命值更新內條
# =========================================================

func _update_fill(
	data: Dictionary,
	current_value: float,
	maximum_value: float
) -> void:

	var track: ColorRect = data["track"]
	var fill: ColorRect = data["fill"]

	var ratio: float = 1.0

	if current_value >= 0.0 and maximum_value > 0.0:
		ratio = clampf(current_value / maximum_value, 0.0, 1.0)

	fill.size = Vector2(
		track.size.x * ratio,
		track.size.y
	)

	fill.visible = ratio > 0.001

	var material := fill.material as ShaderMaterial

	if material != null:
		material.set_shader_parameter("flow_speed", flow_speed)
		material.set_shader_parameter("pigment_density", pigment_density)
		material.set_shader_parameter("pigment_strength", pigment_strength)


# =========================================================
# 找到角色圖片並估算圖片上緣
# =========================================================

func _find_visual_node(target: Node) -> Node2D:
	var animated := _find_visual_type_recursive(target, true)

	if animated != null:
		return animated

	return _find_visual_type_recursive(target, false)


func _find_visual_type_recursive(
	root_node: Node,
	want_animated: bool
) -> Node2D:

	for child in root_node.get_children():
		if want_animated and child is AnimatedSprite2D:
			return child as Node2D

		if not want_animated and child is Sprite2D:
			return child as Node2D

	for child in root_node.get_children():
		var found := _find_visual_type_recursive(
			child,
			want_animated
		)

		if found != null:
			return found

	return null


func _get_sprite_size_and_offset(visual: Node2D) -> Dictionary:
	var texture_size := Vector2.ZERO
	var sprite_offset := Vector2.ZERO

	if visual is AnimatedSprite2D:
		var animated := visual as AnimatedSprite2D
		sprite_offset = animated.offset

		if animated.sprite_frames != null:
			var animation_name := animated.animation

			if animated.sprite_frames.has_animation(animation_name):
				var texture := animated.sprite_frames.get_frame_texture(
					animation_name,
					animated.frame
				)

				if texture != null:
					texture_size = texture.get_size()

	elif visual is Sprite2D:
		var sprite := visual as Sprite2D
		sprite_offset = sprite.offset

		if sprite.texture != null:
			texture_size = sprite.texture.get_size()

	return {
		"size": texture_size,
		"offset": sprite_offset
	}


func _get_head_world_position(
	target: Node2D,
	fallback_offset: Vector2,
	head_adjust: Vector2
) -> Vector2:

	var visual := _find_visual_node(target)

	if visual != null:
		var visual_data := _get_sprite_size_and_offset(visual)
		var texture_size: Vector2 = visual_data["size"]
		var sprite_offset: Vector2 = visual_data["offset"]

		if texture_size.y > 0.0:
			var scale_value: Vector2 = visual.global_scale

			var visual_center := visual.global_position + Vector2(
				sprite_offset.x * scale_value.x,
				sprite_offset.y * scale_value.y
			)

			var top_y := (
				visual_center.y
				- texture_size.y * absf(scale_value.y) * 0.5
			)

			return Vector2(visual_center.x, top_y) + head_adjust

	return target.global_position + fallback_offset


# =========================================================
# 安全讀取生命值變數
# =========================================================

func _read_numeric_property(
	target: Object,
	candidate_names: Array
) -> float:

	for property_info in target.get_property_list():
		var property_name := str(property_info.get("name", ""))

		if candidate_names.has(property_name):
			var value = target.get(property_name)

			if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
				return float(value)

	return -1.0
