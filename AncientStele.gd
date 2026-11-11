
extends Node2D

# =====================================
# 石碑與互動節點
# =====================================

@onready var stele_sprite: Sprite2D = $石碑
@onready var interaction_area: Area2D = $InteractionArea
@onready var prompt: Sprite2D = $Prompt

# =====================================
# UI 節點
# =====================================

@onready var dialogue_ui: Control = $CanvasLayer2/DialogueUI
@onready var dialogue_panel: Control = $CanvasLayer2/DialogueUI/DialoguePanel

@onready var frame: TextureRect = $CanvasLayer2/DialogueUI/DialoguePanel/Frame

@onready var title_tab: TextureRect = $CanvasLayer2/DialogueUI/DialoguePanel/TitleTab
@onready var title_label: Label = $CanvasLayer2/DialogueUI/DialoguePanel/TitleTab/TitleLabel

@onready var corner_ornament: TextureRect = $CanvasLayer2/DialogueUI/DialoguePanel/CornerOrnament

@onready var dialogue_text: RichTextLabel = $CanvasLayer2/DialogueUI/DialoguePanel/DialogueText

@onready var key_prompt: TextureRect = $CanvasLayer2/DialogueUI/DialoguePanel/KeyPrompt

var key_prompt_label: Label

# =====================================
# 狀態
# =====================================

var player_near: bool = false
var reading: bool = false

# 石碑上方提示圖片最大寬度
const WORLD_PROMPT_WIDTH: float = 120.0

# 提示圖片與石碑頂端的間距
const PROMPT_GAP: float = 14.0


# =====================================
# 初始化
# =====================================

func _ready() -> void:

	# 檢查必要素材
	if stele_sprite.texture == null:
		push_error("石碑尚未指定圖片")
		return

	if prompt.texture == null:
		push_error("Prompt 尚未指定 KeyPrompt.png")
		return

	if frame.texture == null:
		push_error("Frame 尚未指定 Dialogue Panel PNG")
		return

	# 設定石碑提示圖片
	_setup_world_prompt()

	# 設定閱讀 UI
	_setup_dialogue_ui()

	# 自動排版
	_layout_dialogue_ui()

	# 畫面大小改變時重新排版
	get_viewport().size_changed.connect(
		_layout_dialogue_ui
	)

	# 連接互動訊號
	interaction_area.body_entered.connect(
		_on_body_entered
	)

	interaction_area.body_exited.connect(
		_on_body_exited
	)


# =====================================
# 石碑上方提示圖片
# =====================================

func _setup_world_prompt() -> void:

	# 移除之前建立的舊文字節點
	var old_text = prompt.get_node_or_null("PromptText")

	if old_text != null:
		old_text.queue_free()

	# 以圖片原始大小為基礎
	var texture_size := Vector2(
		prompt.texture.get_size()
	)

	# 最大寬度 120px，絕不放大原圖
	var scale_factor: float = minf(
		1.0,
		WORLD_PROMPT_WIDTH / texture_size.x
	)

	prompt.scale = Vector2.ONE * scale_factor

	# 保持圖片清晰
	prompt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# 以圖片中心定位
	prompt.centered = true

	# 確保提示顯示在石碑前方
	prompt.z_index = 10

	# 計算圖片實際顯示尺寸
	var displayed_size: Vector2 = texture_size * scale_factor

	# 重新計算位置
	position_prompt()

	# 開始時隱藏
	prompt.hide()


# =====================================
# 自動計算提示圖片位置
# =====================================

func position_prompt() -> void:

	if stele_sprite.texture == null:
		return

	if prompt.texture == null:
		return

	# 取得石碑實際圖片範圍
	var stele_rect: Rect2 = stele_sprite.get_rect()

	# 計算石碑四個角在父節點座標中的位置
	var corners: Array[Vector2] = [
		stele_sprite.transform * stele_rect.position,
		stele_sprite.transform * Vector2(
			stele_rect.end.x,
			stele_rect.position.y
		),
		stele_sprite.transform * stele_rect.end,
		stele_sprite.transform * Vector2(
			stele_rect.position.x,
			stele_rect.end.y
		)
	]

	# 找出石碑頂端與左右範圍
	var top_y: float = INF
	var left_x: float = INF
	var right_x: float = -INF

	for point in corners:
		top_y = minf(top_y, point.y)
		left_x = minf(left_x, point.x)
		right_x = maxf(right_x, point.x)

	# 取得提示圖片實際顯示高度
	var prompt_height: float = (
		prompt.texture.get_height() * absf(prompt.scale.y)
	)

	# 放置在石碑上方中央
	prompt.position = Vector2(
		(left_x + right_x) / 2.0,
		top_y - prompt_height / 2.0 - PROMPT_GAP
	)


# =====================================
# 閱讀 UI 初始化
# =====================================

func _setup_dialogue_ui() -> void:

	dialogue_ui.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	dialogue_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE

	dialogue_panel.clip_contents = false

	# 標題
	title_label.text = "古老石碑"

	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# 石碑內容
	dialogue_text.text = """一塊古老的石板寫道：

偃師之偶，丹青之魂，
濡翰濟世，鼎革更始

創世之息，盤古之造，
天地萬象，化為石色"""

	dialogue_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# 保留垂直滾動
	dialogue_text.scroll_active = true
	dialogue_text.scroll_following = false
	dialogue_text.fit_content = false

	# 對話框內的關閉提示
	key_prompt_label = key_prompt.get_node_or_null(
        "KeyPromptLabel"
	) as Label

	if key_prompt_label == null:
		key_prompt_label = Label.new()
		key_prompt_label.name = "KeyPromptLabel"
		key_prompt.add_child(key_prompt_label)

	key_prompt_label.text = ""

	key_prompt_label.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	key_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	key_prompt_label.clip_text = true

	# 初始隱藏
	dialogue_ui.hide()


# =====================================
# UI 自動排版
# =====================================

func _layout_dialogue_ui() -> void:

	var viewport_size: Vector2 = get_viewport_rect().size

	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return

	if frame.texture == null:
		return

	# 主對話框
	var source_size := Vector2(
		frame.texture.get_size()
	)

	var scale_factor: float = min(
		(viewport_size.x * 0.84) / source_size.x,
		(viewport_size.y * 0.36) / source_size.y
	)

	var panel_size: Vector2 = source_size * scale_factor

	dialogue_panel.position = Vector2(
		(viewport_size.x - panel_size.x) / 2.0,
		viewport_size.y - panel_size.y - viewport_size.y * 0.035
	)

	dialogue_panel.size = panel_size

	frame.position = Vector2.ZERO
	frame.size = panel_size
	frame.stretch_mode = TextureRect.STRETCH_SCALE

	# 標題框
	if title_tab.texture != null:

		var title_size := Vector2(
			title_tab.texture.get_size()
		)

		var title_width: float = min(
			panel_size.x * 0.36,
			title_size.x
		)

		var title_height: float = (
			title_width * title_size.y / title_size.x
		)

		title_tab.size = Vector2(
			title_width,
			title_height
		)

		title_tab.position = Vector2(
			(panel_size.x - title_width) / 2.0,
			-title_height * 0.15
		)

		title_tab.stretch_mode = (
			TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		)

		title_label.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT
		)

		title_label.add_theme_font_size_override(
			"font_size",
			clampi(int(viewport_size.y * 0.028), 20, 36)
		)

	# 角落裝飾
	if corner_ornament.texture != null:

		var ornament_size := _fit_texture(
			corner_ornament,
			Vector2(
				panel_size.x * 0.12,
				panel_size.y * 0.22
			)
		)

		corner_ornament.size = ornament_size

		corner_ornament.stretch_mode = (
			TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		)

		corner_ornament.position = Vector2(
			panel_size.x - ornament_size.x - panel_size.x * 0.045,
			panel_size.y * 0.035
		)

	# 主要文字區
	dialogue_text.position = Vector2(
		panel_size.x * 0.12,
		panel_size.y * 0.29
	)

	dialogue_text.size = Vector2(
		panel_size.x * 0.76,
		panel_size.y * 0.49
	)

	dialogue_text.add_theme_font_size_override(
		"normal_font_size",
		clampi(int(viewport_size.y * 0.025), 19, 32)
	)

	# 對話框內的 Key Prompt
	if key_prompt.texture != null:

		var key_size := _fit_texture(
			key_prompt,
			Vector2(
				panel_size.x * 0.17,
				panel_size.y * 0.19
			)
		)

		key_prompt.size = key_size

		key_prompt.stretch_mode = (
			TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		)

		key_prompt.position = Vector2(
			panel_size.x - key_size.x - panel_size.x * 0.07,
			panel_size.y - key_size.y - panel_size.y * 0.075
		)

		key_prompt_label.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT
		)

		key_prompt_label.add_theme_font_size_override(
			"font_size",
			clampi(int(viewport_size.y * 0.019), 16, 26)
		)


# =====================================
# 圖片比例
# =====================================

func _fit_texture(
	texture_rect: TextureRect,
	max_size: Vector2
) -> Vector2:

	if texture_rect.texture == null:
		return Vector2.ZERO

	var texture_size := Vector2(
		texture_rect.texture.get_size()
	)

	var ratio: float = min(
		max_size.x / texture_size.x,
		max_size.y / texture_size.y
	)

	return texture_size * ratio


# =====================================
# 玩家進入互動範圍
# =====================================

func _on_body_entered(body: Node2D) -> void:

	if body.is_in_group("player"):

		player_near = true

		if not reading:
			position_prompt()
			prompt.show()


# =====================================
# 玩家離開互動範圍
# =====================================

func _on_body_exited(body: Node2D) -> void:

	if body.is_in_group("player"):

		player_near = false
		prompt.hide()


# =====================================
# E 鍵互動
# =====================================

func _unhandled_input(event: InputEvent) -> void:

	if event.is_action_pressed("interact") and not event.is_echo():

		if reading:

			# 關閉閱讀視窗
			reading = false
			dialogue_ui.hide()

			if player_near:
				prompt.show()

		elif player_near:

			# 開啟閱讀視窗
			reading = true
			prompt.hide()
			dialogue_ui.show()

		get_viewport().set_input_as_handled()
