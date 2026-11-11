extends Node2D

# =====================================
# 場景資源
# =====================================

const BIRD_SCENE: PackedScene = preload("res://Bird.tscn")
const ELEPHANT_SCENE: PackedScene = preload("res://Elephant.tscn")
const FRAME_PATH: String = "res://ui/drawer.png"
const BIRD_COUNT: int = 5

@export var player_path: NodePath = NodePath("../ikay")


# =====================================
# 繪素設定
# =====================================

@export var max_pigment: float = 100.0
@export var summon_cost: float = 30.0
@export var elephant_cost: float = 50.0
@export var elephant_guard_hits: int = 3
@export var pigment_regen_rate: float = 8.0

var current_pigment: float = 100.0


# =====================================
# 能量條內部填充位置
# =====================================

@export_range(0.0, 0.45, 0.005)
var fill_left_ratio: float = 0.13

@export_range(0.55, 1.0, 0.005)
var fill_right_ratio: float = 0.87

@export_range(0.0, 0.45, 0.005)
var fill_top_ratio: float = 0.18

@export_range(0.55, 1.0, 0.005)
var fill_bottom_ratio: float = 0.82


# =====================================
# 繪圖判定
# =====================================

@export var min_circle_length: float = 90.0
@export var min_circle_diameter: float = 35.0

@export var min_command_length: float = 35.0
@export var max_line_deviation: float = 35.0

@export var sample_spacing: float = 3.0
@export var flight_distance_multiplier: float = 2.0

# 垂直線召喚大象
@export var elephant_line_min_height: float = 60.0
@export var elephant_line_max_deviation: float = 16.0

@export_range(0.05, 0.5, 0.01)
var elephant_line_max_slant_ratio: float = 0.16


# =====================================
# 筆畫外觀
# =====================================

@export var line_color: Color = Color(0.35, 0.85, 1.0, 1.0)

@export var drawing_stroke_width: float = 12.0
@export var drawing_outline_color: Color = Color("#090D17")
@export var drawing_outline_width: float = 2.5

@export var drawing_color_start: Color = Color("#397DE8")
@export var drawing_color_middle: Color = Color("#70D9F0")
@export var drawing_color_end: Color = Color("#C0F5DC")

@export var drawing_grain_spacing: float = 3.0
@export var drawing_grain_size_min: float = 0.7
@export var drawing_grain_size_max: float = 1.8

@export_range(0.0, 1.0, 0.01)
var drawing_grain_opacity: float = 0.22


# =====================================
# 音效設定
# =====================================

@export_group("Spell Sounds")

@export var brush_start_sfx: AudioStream
@export var bird_summon_sfx: AudioStream
@export var elephant_summon_sfx: AudioStream
@export var bird_command_sfx: AudioStream

@export var spell_sfx_volume_db: float = -6.0

var brush_audio: AudioStreamPlayer2D
var bird_summon_audio: AudioStreamPlayer2D
var elephant_summon_audio: AudioStreamPlayer2D
var bird_command_audio: AudioStreamPlayer2D


# =====================================
# 遊戲狀態
# =====================================

var player: Node2D = null
var birds: Array[SpiritBird] = []
var elephant: Node2D = null

var is_drawing: bool = false
var drawing_mode: String = ""
var visual_path: PackedVector2Array = PackedVector2Array()


# =====================================
# 繪素 UI
# =====================================

var hud_layer: CanvasLayer
var hud_root: Control

var energy_title: Label
var energy_value_label: Label
var energy_notice: Label

var bar_background: ColorRect
var bar_fill: ColorRect
var frame_rect: TextureRect
var flow_material: ShaderMaterial

var full_fill_width: float = 0.0
var energy_notice_timer: float = 0.0


func _ready() -> void:
	player = get_node_or_null(player_path) as Node2D
	current_pigment = max_pigment
	_setup_spell_audio()

	if player == null:
		push_error(
			"SpellSystem：找不到主角，請確認 Player Path 為 ../ikay。"
		)

	_create_energy_hud()
	_update_energy_hud()


# =====================================
# 建立 SpellSystem 音效
# =====================================

func _setup_spell_audio() -> void:
	brush_audio = _create_spell_audio_player(
		"BrushStartAudio",
		brush_start_sfx
	)
	bird_summon_audio = _create_spell_audio_player(
		"BirdSummonAudio",
		bird_summon_sfx
	)
	elephant_summon_audio = _create_spell_audio_player(
		"ElephantSummonAudio",
		elephant_summon_sfx
	)
	bird_command_audio = _create_spell_audio_player(
		"BirdCommandAudio",
		bird_command_sfx
	)


func _create_spell_audio_player(
	player_name: String,
	audio_stream: AudioStream
) -> AudioStreamPlayer2D:
	var audio := AudioStreamPlayer2D.new()
	audio.name = player_name
	audio.stream = audio_stream
	audio.volume_db = spell_sfx_volume_db
	audio.max_distance = 1200.0
	add_child(audio)
	return audio


func _play_spell_sfx(
	audio: AudioStreamPlayer2D,
	sound_position: Vector2
) -> void:
	if not is_instance_valid(audio) or audio.stream == null:
		return

	audio.global_position = sound_position
	audio.play()


func _process(delta: float) -> void:
	# 繪素自然恢復。
	if current_pigment < max_pigment:
		current_pigment = minf(
			max_pigment,
			current_pigment + pigment_regen_rate * delta
		)
		_update_energy_hud()

	# 大象被破壞後，允許再次召喚。
	if is_instance_valid(elephant) and elephant.is_queued_for_deletion():
		elephant = null

	# 自動隱藏訊息。
	if energy_notice_timer > 0.0:
		energy_notice_timer = maxf(
			0.0,
			energy_notice_timer - delta
		)

		if (
			energy_notice_timer <= 0.0
			and is_instance_valid(energy_notice)
		):
			energy_notice.visible = false


# =====================================
# 建立繪素 UI
# =====================================

func _create_energy_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "PigmentHUD"
	hud_layer.layer = 10
	add_child(hud_layer)

	hud_root = Control.new()
	hud_root.name = "PigmentUI"
	hud_root.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud_root)

	var frame_texture: Texture2D = (
		load(FRAME_PATH) as Texture2D
	)

	if frame_texture == null:
		push_error("找不到繪素框：" + FRAME_PATH)

	# 標題。
	energy_title = Label.new()
	energy_title.name = "PigmentTitle"
	energy_title.text = "繪素  PIGMENT"
	energy_title.position = Vector2(20.0, 12.0)
	energy_title.size = Vector2(260.0, 28.0)
	energy_title.add_theme_font_size_override(
		"font_size", 19
	)
	energy_title.add_theme_color_override(
		"font_color", Color("#E5C783")
	)
	energy_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(energy_title)

	# 外框尺寸。
	var frame_position := Vector2(20.0, 44.0)
	var frame_size := Vector2(280.0, 35.0)

	if frame_texture != null and frame_texture.get_width() > 0:
		frame_size.y = (
			frame_size.x
			* float(frame_texture.get_height())
			/ float(frame_texture.get_width())
		)

	# 計算能量條內部填充區域。
	var left_ratio: float = clampf(
		fill_left_ratio, 0.0, 0.45
	)

	var right_ratio: float = clampf(
		fill_right_ratio, left_ratio + 0.1, 1.0
	)

	var top_ratio: float = clampf(
		fill_top_ratio, 0.0, 0.45
	)

	var bottom_ratio: float = clampf(
		fill_bottom_ratio, top_ratio + 0.1, 1.0
	)

	var fill_position := Vector2(
		frame_position.x + frame_size.x * left_ratio,
		frame_position.y + frame_size.y * top_ratio
	)

	var fill_size := Vector2(
		frame_size.x * (right_ratio - left_ratio),
		frame_size.y * (bottom_ratio - top_ratio)
	)

	full_fill_width = fill_size.x

	# 底層：空能量槽。
	bar_background = ColorRect.new()
	bar_background.name = "PigmentBackground"
	bar_background.position = fill_position
	bar_background.size = fill_size
	bar_background.color = Color("#211B25")
	bar_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(bar_background)

	# 中層：藍金流動顏料。
	bar_fill = ColorRect.new()
	bar_fill.name = "PigmentFlow"
	bar_fill.position = fill_position
	bar_fill.size = fill_size
	bar_fill.color = Color.WHITE
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	flow_material = ShaderMaterial.new()

	var shader := Shader.new()

	shader.code = """
shader_type canvas_item;

uniform float fill_amount : hint_range(0.0, 1.0) = 1.0;
uniform float flow_speed = 1.8;
uniform float pixel_columns = 120.0;
uniform float pixel_rows = 12.0;

void fragment() {
    if (UV.x >= fill_amount) {
        discard;
    }

    float x = (
        floor(UV.x * pixel_columns) + 0.5
    ) / pixel_columns;

    float y = (
        floor(UV.y * pixel_rows) + 0.5
    ) / pixel_rows;

    float blue_wave = 0.5 + 0.5 * sin(
        x * 24.0 - TIME * flow_speed + y * 5.0
    );

    vec3 deep_blue = vec3(0.075, 0.16, 0.36);
    vec3 lapis_blue = vec3(0.12, 0.30, 0.65);
    vec3 cyan_blue = vec3(0.30, 0.66, 0.85);

    vec3 color = mix(
        deep_blue,
        lapis_blue,
        blue_wave * 0.75
    );

    float blue_pattern = sin(
        x * 38.0 - TIME * flow_speed * 0.8
        + sin(y * 15.0) * 1.8
    );

    if (blue_pattern > 0.72) {
        color = mix(color, cyan_blue, 0.32);
    }

    float phase_1 = x * 10.0 - TIME * flow_speed;

    float gold_center_1 = (
        0.32
        + 0.13 * sin(phase_1)
        + 0.04 * sin(phase_1 * 2.2)
    );

    float gold_distance_1 = abs(y - gold_center_1);

    vec3 antique_gold = vec3(0.48, 0.25, 0.055);
    vec3 rich_gold = vec3(0.86, 0.57, 0.16);
    vec3 light_gold = vec3(1.0, 0.86, 0.47);

    if (gold_distance_1 < 0.22) {
        color = antique_gold;
    }

    if (gold_distance_1 < 0.14) {
        color = rich_gold;
    }

    if (gold_distance_1 < 0.07) {
        color = light_gold;
    }

    float phase_2 = (
        x * 15.0 - TIME * flow_speed * 0.72 + 2.1
    );

    float gold_center_2 = (
        0.70 + 0.075 * sin(phase_2)
    );

    float gold_distance_2 = abs(y - gold_center_2);

    if (gold_distance_2 < 0.10) {
        color = rich_gold;
    }

    if (gold_distance_2 < 0.055) {
        color = light_gold;
    }

    float fleck_pattern = mod(
        floor(x * 95.0) + floor(y * 13.0) * 3.0,
        17.0
    );

    if (
        fleck_pattern < 1.0
        && sin(x * 30.0 - TIME * flow_speed) > 0.2
    ) {
        color = light_gold;
    }

    COLOR = vec4(color, 1.0);
}
"""

	flow_material.shader = shader
	bar_fill.material = flow_material
	hud_root.add_child(bar_fill)

	# 最上層：金框。
	if frame_texture != null:
		frame_rect = TextureRect.new()
		frame_rect.name = "PigmentFrame"
		frame_rect.texture = frame_texture
		frame_rect.position = frame_position
		frame_rect.size = frame_size
		frame_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame_rect.stretch_mode = TextureRect.STRETCH_SCALE
		frame_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		frame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_root.add_child(frame_rect)

	# 繪素數值。
	energy_value_label = Label.new()
	energy_value_label.name = "PigmentValue"
	energy_value_label.position = Vector2(
		frame_position.x + frame_size.x + 12.0,
		frame_position.y + frame_size.y * 0.25
	)
	energy_value_label.size = Vector2(120.0, 25.0)
	energy_value_label.add_theme_font_size_override(
		"font_size", 16
	)
	energy_value_label.add_theme_color_override(
		"font_color", Color("#F3E7C9")
	)
	energy_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(energy_value_label)

	# 操作提示。
	energy_notice = Label.new()
	energy_notice.name = "PigmentNotice"
	energy_notice.position = Vector2(
		frame_position.x,
		frame_position.y + frame_size.y + 8.0
	)
	energy_notice.size = Vector2(350.0, 26.0)
	energy_notice.visible = false
	energy_notice.add_theme_font_size_override(
		"font_size", 15
	)
	energy_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(energy_notice)


# =====================================
# 更新繪素
# =====================================

func _update_energy_hud() -> void:
	if not is_instance_valid(energy_value_label):
		return

	energy_value_label.text = "%d / %d" % [
		roundi(current_pigment),
		roundi(max_pigment)
	]

	var ratio: float = 0.0

	if max_pigment > 0.0:
		ratio = clampf(
			current_pigment / max_pigment,
			0.0,
			1.0
		)

	if flow_material != null:
		flow_material.set_shader_parameter(
			"fill_amount", ratio
		)


func _show_energy_notice(
	message: String,
	color: Color = Color("#E5C783")
) -> void:
	if not is_instance_valid(energy_notice):
		return

	energy_notice.text = message
	energy_notice.add_theme_color_override(
		"font_color", color
	)
	energy_notice.visible = true
	energy_notice_timer = 1.5


# =====================================
# 主角繪圖動作
# =====================================

func _play_player_drawing_action() -> void:
	if is_instance_valid(player):
		if player.has_method("play_drawing_animation"):
			player.call("play_drawing_animation")
			return

	for node: Node in get_tree().get_nodes_in_group("player"):
		if node.has_method("play_drawing_animation"):
			node.call("play_drawing_animation")
			return


# =====================================
# 滑鼠輸入
# =====================================

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton

		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return

		if mouse_event.pressed:
			_begin_drawing()
		elif is_drawing:
			_finish_drawing()
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and is_drawing:
		var mouse_position: Vector2 = get_global_mouse_position()

		if visual_path.is_empty():
			visual_path.append(mouse_position)
		elif (
			visual_path[visual_path.size() - 1]
			.distance_to(mouse_position) >= sample_spacing
		):
			visual_path.append(mouse_position)

		queue_redraw()
		get_viewport().set_input_as_handled()


func _begin_drawing() -> void:
	if not is_instance_valid(player):
		return

	_prune_birds()

	# 沒有任何靈鳥時，圓形可用來召喚一組新的五隻鳥。
	if birds.is_empty():
		drawing_mode = "summon"
	else:
		drawing_mode = "waiting"

		# 每次只挑選第一隻尚未出擊的鳥，其他鳥繼續環繞 PICTOR。
		for bird: SpiritBird in birds:
			if is_instance_valid(bird) and bird.can_aim():
				bird.begin_aim()
				drawing_mode = "command"
				break

	is_drawing = true
	visual_path.clear()
	visual_path.append(get_global_mouse_position())

	# 滑鼠開始繪圖時播放一次筆刷起始聲。
	_play_spell_sfx(brush_audio, get_global_mouse_position())

	queue_redraw()
	get_viewport().set_input_as_handled()


func _finish_drawing() -> void:
	if not is_drawing:
		return

	var mouse_position: Vector2 = get_global_mouse_position()

	if visual_path.is_empty():
		_clear_drawing()
		return

	if (
		visual_path[visual_path.size() - 1]
		.distance_to(mouse_position) > 2.0
	):
		visual_path.append(mouse_position)

	# 垂直線優先：在筆畫底端放置固定大象。
	if _is_vertical_line(visual_path):
		_cancel_all_birds()

		if is_instance_valid(elephant):
			_show_energy_notice("大象已經放置在場上。")
		else:
			_spawn_elephant_at(
				_get_elephant_placement(visual_path)
			)

	# 沒有靈鳥時，圓形召喚五隻靈鳥。
	elif drawing_mode == "summon":
		if _is_circle(visual_path):
			_spawn_birds()

	# 每條有效直線只指揮一隻尚未出擊的靈鳥。
	elif drawing_mode == "command":
		_launch_birds()

	elif drawing_mode == "waiting":
		_show_energy_notice("五隻靈鳥都已出擊，請等待牠們完成攻擊。")

	_clear_drawing()


# =====================================
# 垂直線辨識
# =====================================

func _is_vertical_line(
	points: PackedVector2Array
) -> bool:
	if points.size() < 2:
		return false

	var start_point: Vector2 = points[0]
	var end_point: Vector2 = points[points.size() - 1]

	var direction: Vector2 = end_point - start_point
	var vertical_distance: float = absf(direction.y)
	var horizontal_distance: float = absf(direction.x)
	var line_length: float = direction.length()

	if vertical_distance < elephant_line_min_height:
		return false

	if line_length < 0.001:
		return false

	if (
		horizontal_distance
		> vertical_distance * elephant_line_max_slant_ratio
	):
		return false

	for point: Vector2 in points:
		var cross_value: float = (
			direction.x * (start_point.y - point.y)
			- (start_point.x - point.x) * direction.y
		)

		var deviation: float = absf(cross_value) / line_length

		if deviation > elephant_line_max_deviation:
			return false

	return true


func _get_elephant_placement(
	points: PackedVector2Array
) -> Vector2:
	if points.is_empty():
		return get_global_mouse_position()

	var bottom_point: Vector2 = points[0]

	for point: Vector2 in points:
		if point.y > bottom_point.y:
			bottom_point = point

	return bottom_point


# =====================================
# 召喚固定大象
# =====================================

func _spawn_elephant_at(
	spawn_position: Vector2
) -> void:
	if not is_instance_valid(player):
		return

	if is_instance_valid(elephant):
		_show_energy_notice("大象已經放置在場上。")
		return

	if current_pigment < elephant_cost:
		_show_energy_notice(
			"繪素不足！召喚大象需要 %d 繪素。"
			% roundi(elephant_cost),
			Color("#FF7185")
		)
		return

	var parent_node: Node = get_parent()

	if parent_node == null:
		push_error("SpellSystem 沒有有效的父節點。")
		return

	var new_elephant: Node2D = (
		ELEPHANT_SCENE.instantiate() as Node2D
	)

	if new_elephant == null:
		push_error("無法建立 Elephant.tscn。請確認場景根節點是 Node2D。")
		return

	new_elephant.name = "DefenseElephant"
	parent_node.add_child(new_elephant)

	# 大象使用固定的筆畫底端座標。
	new_elephant.call(
		"setup_guard",
		player,
		spawn_position,
		elephant_guard_hits
	)

	elephant = new_elephant

	elephant.tree_exiting.connect(
		_on_elephant_tree_exiting
	)

	current_pigment = maxf(
		0.0,
		current_pigment - elephant_cost
	)

	_update_energy_hud()

	_show_energy_notice(
		"大象已放置！耐久：%d" % elephant_guard_hits
	)

	_play_spell_sfx(elephant_summon_audio, spawn_position)
	_play_player_drawing_action()


func _on_elephant_tree_exiting() -> void:
	elephant = null


# =====================================
# 圓形辨識：召喚靈鳥
# =====================================

func _is_circle(points: PackedVector2Array) -> bool:
	if points.size() < 8:
		return false

	if _get_path_length(points) < min_circle_length:
		return false

	var bounds: Rect2 = _get_path_bounds(points)

	var width: float = bounds.size.x
	var height: float = bounds.size.y

	if width < min_circle_diameter or height < min_circle_diameter:
		return false

	var aspect_ratio: float = minf(width, height) / maxf(width, height)

	if aspect_ratio < 0.55:
		return false

	var start_point: Vector2 = points[0]
	var end_point: Vector2 = points[points.size() - 1]

	var closure_limit: float = maxf(
		25.0,
		maxf(width, height) * 0.30
	)

	if start_point.distance_to(end_point) > closure_limit:
		return false

	return _calculate_circularity(points) >= 0.45


func _calculate_circularity(
	points: PackedVector2Array
) -> float:
	if points.size() < 3:
		return 0.0

	var twice_area: float = 0.0
	var perimeter: float = 0.0

	for i: int in range(points.size()):
		var current: Vector2 = points[i]
		var next: Vector2 = points[(i + 1) % points.size()]

		twice_area += (
			current.x * next.y - next.x * current.y
		)

		perimeter += current.distance_to(next)

	if perimeter <= 0.001:
		return 0.0

	var area: float = absf(twice_area) * 0.5

	return 4.0 * PI * area / (perimeter * perimeter)


# =====================================
# 召喚五隻靈鳥
# =====================================

func _spawn_birds() -> void:
	_prune_birds()

	if not birds.is_empty():
		return

	if not is_instance_valid(player):
		return

	if current_pigment < summon_cost:
		_show_energy_notice(
			"繪素不足！需要 %d 繪素才能召喚。"
			% roundi(summon_cost),
			Color("#FF7185")
		)
		return

	var parent_node: Node = get_parent()

	if parent_node == null:
		push_error("SpellSystem 沒有有效的父節點。")
		return

	var new_birds: Array[SpiritBird] = []

	for i: int in range(BIRD_COUNT):
		var instance: Node = BIRD_SCENE.instantiate()
		var new_bird: SpiritBird = instance as SpiritBird

		if new_bird == null:
			instance.free()

			for created_bird: SpiritBird in new_birds:
				created_bird.free()

			push_error("Bird.tscn 根節點必須掛載 Bird.gd。")
			return

		new_birds.append(new_bird)

	for i: int in range(new_birds.size()):
		var new_bird: SpiritBird = new_birds[i]

		parent_node.add_child(new_bird)

		new_bird.global_position = (
			player.global_position + Vector2(45.0, -25.0)
		)

		new_bird.set_follow_target(
			player,
			i,
			BIRD_COUNT
		)

		birds.append(new_bird)

		new_bird.tree_exiting.connect(
			_on_bird_tree_exiting.bind(new_bird)
		)

	current_pigment = maxf(
		0.0,
		current_pigment - summon_cost
	)

	_update_energy_hud()

	_show_energy_notice(
		"已創造五隻靈鳥！繪素 -%d" % roundi(summon_cost)
	)

	_play_spell_sfx(bird_summon_audio, player.global_position)
	_play_player_drawing_action()


func _on_bird_tree_exiting(
	exiting_bird: SpiritBird
) -> void:
	birds.erase(exiting_bird)


func _prune_birds() -> void:
	for i: int in range(birds.size() - 1, -1, -1):
		if not is_instance_valid(birds[i]):
			birds.remove_at(i)


# =====================================
# 每條直線指揮一隻靈鳥
# =====================================

func _launch_birds() -> void:
	_prune_birds()

	if birds.is_empty():
		return

	if visual_path.size() < 2:
		_cancel_all_birds()
		return

	# 找到本次畫線開始時被選中的那一隻鳥。
	var selected_bird: SpiritBird = null

	for bird: SpiritBird in birds:
		if is_instance_valid(bird) and bird.is_aiming():
			selected_bird = bird
			break

	if selected_bird == null:
		_show_energy_notice("目前沒有可出擊的靈鳥。")
		return

	var start_point: Vector2 = visual_path[0]
	var end_point: Vector2 = visual_path[visual_path.size() - 1]

	var direction: Vector2 = end_point - start_point
	var drawn_distance: float = direction.length()

	if drawn_distance < min_command_length:
		_cancel_all_birds()
		return

	if not _is_straight_line(visual_path):
		_cancel_all_birds()
		return

	var flight_distance: float = (
		drawn_distance * flight_distance_multiplier
	)

	_play_spell_sfx(bird_command_audio, player.global_position)
	_play_player_drawing_action()

	# 一條有效直線只會發射這一隻鳥。
	selected_bird.launch(direction, flight_distance)


func _cancel_all_birds() -> void:
	for bird: SpiritBird in birds:
		if is_instance_valid(bird):
			bird.cancel_aim()


func _is_straight_line(
	points: PackedVector2Array
) -> bool:
	if points.size() < 2:
		return false

	var start_point: Vector2 = points[0]
	var end_point: Vector2 = points[points.size() - 1]

	var direction: Vector2 = end_point - start_point
	var line_length: float = direction.length()

	if line_length < 0.001:
		return false

	for point: Vector2 in points:
		var cross_value: float = (
			direction.x * (start_point.y - point.y)
			- (start_point.x - point.x) * direction.y
		)

		var deviation: float = absf(cross_value) / line_length

		if deviation > max_line_deviation:
			return false

	return true


# =====================================
# 清除繪圖
# =====================================

func _clear_drawing() -> void:
	is_drawing = false
	drawing_mode = ""
	visual_path.clear()
	queue_redraw()


# =====================================
# 筆畫：黑色邊框、漸層、細微顆粒
# =====================================

func _draw() -> void:
	if visual_path.size() < 2:
		return

	var local_points: PackedVector2Array = PackedVector2Array()

	for point: Vector2 in visual_path:
		local_points.append(to_local(point))

	var stroke_width: float = maxf(4.0, drawing_stroke_width)
	var outline_width: float = maxf(0.0, drawing_outline_width)
	var total_length: float = _get_path_length(local_points)

	if total_length <= 0.001:
		return

	# 黑色外框。
	draw_polyline(
		local_points,
		drawing_outline_color,
		stroke_width + outline_width * 2.0,
		true
	)

	# 彩色主筆畫。
	draw_polyline(
		local_points,
		line_color,
		stroke_width,
		true
	)

	var travelled: float = 0.0

	for i: int in range(1, local_points.size()):
		var a: Vector2 = local_points[i - 1]
		var b: Vector2 = local_points[i]

		var segment_length: float = a.distance_to(b)

		if segment_length <= 0.001:
			continue

		var t: float = clampf(
			(travelled + segment_length * 0.5) / total_length,
			0.0,
			1.0
		)

		var segment_color: Color = _get_stroke_gradient_color(t)

		# 內部漸層色帶。
		draw_line(
			a,
			b,
			segment_color,
			maxf(2.0, stroke_width * 0.78),
			true
		)

		# 顆粒分布。
		var direction: Vector2 = (b - a) / segment_length
		var normal: Vector2 = Vector2(-direction.y, direction.x)

		var grain_spacing: float = maxf(2.0, drawing_grain_spacing)

		var grain_count: int = maxi(
			1,
			ceili(segment_length / grain_spacing)
		)

		for grain_index: int in range(grain_count):
			var grain_t: float = (
				(float(grain_index) + 0.5)
				/ float(grain_count)
			)

			var grain_position: Vector2 = a.lerp(b, grain_t)

			var distance_t: float = clampf(
				(travelled + segment_length * grain_t) / total_length,
				0.0,
				1.0
			)

			var grain_base_color: Color = _get_stroke_gradient_color(
				distance_t
			)

			var grain_seed: float = float(
				i * 977 + grain_index * 131 + 17
			)

			for speckle_index: int in range(2):
				var grain_seed_value: float = (
					grain_seed + float(speckle_index) * 53.0
				)

				var random_side: float = (
					_grain_noise(grain_seed_value + 1.0) * 2.0 - 1.0
				)

				var random_along: float = (
					_grain_noise(grain_seed_value + 2.0) - 0.5
				) * grain_spacing

				var grain_size: float = lerpf(
					drawing_grain_size_min,
					drawing_grain_size_max,
					_grain_noise(grain_seed_value + 3.0)
				)

				var max_offset: float = maxf(
					0.0,
					stroke_width * 0.34 - grain_size
				)

				var grain_offset: float = random_side * max_offset

				var speckle_position: Vector2 = (
					grain_position
					+ direction * random_along
					+ normal * grain_offset
				)

				var speckle_color: Color = grain_base_color

				if _grain_noise(grain_seed_value + 4.0) < 0.5:
					speckle_color = speckle_color.darkened(0.32)
				else:
					speckle_color = speckle_color.lightened(0.28)

				speckle_color.a = drawing_grain_opacity

				draw_rect(
					Rect2(
						speckle_position
						- Vector2.ONE * grain_size * 0.5,
						Vector2.ONE * grain_size
					),
					speckle_color,
					true
				)

		travelled += segment_length


func _get_stroke_gradient_color(amount: float) -> Color:
	var t: float = clampf(amount, 0.0, 1.0)

	if t < 0.5:
		return drawing_color_start.lerp(
			drawing_color_middle,
			t * 2.0
		)

	return drawing_color_middle.lerp(
		drawing_color_end,
		(t - 0.5) * 2.0
	)


func _grain_noise(seed_value: float) -> float:
	return fposmod(
		sin(seed_value * 12.9898) * 43758.5453,
		1.0
	)


# =====================================
# 路徑工具
# =====================================

func _get_path_length(
	points: PackedVector2Array
) -> float:
	var total_length: float = 0.0

	for i: int in range(1, points.size()):
		total_length += points[i - 1].distance_to(points[i])

	return total_length


func _get_path_bounds(
	points: PackedVector2Array
) -> Rect2:
	if points.is_empty():
		return Rect2()

	var min_x: float = points[0].x
	var max_x: float = points[0].x
	var min_y: float = points[0].y
	var max_y: float = points[0].y

	for point: Vector2 in points:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)

	return Rect2(
		Vector2(min_x, min_y),
		Vector2(max_x - min_x, max_y - min_y)
	)
