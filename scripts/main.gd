extends Control

## UI rebuilt board-first: centered column, no OptionButtons. Game rules live in PoetryGameState.

const CARD := 88
const SLOT := CARD + 10
const PAD_H := 16
const PAD_V := 24
const BOARD_MIN := Vector2(560, 320)

const TIER_ORDER: Array[int] = [
	PoetryGameState.Tier.LANDSCAPE,
	PoetryGameState.Tier.STRUCTURE,
	PoetryGameState.Tier.ROOM,
	PoetryGameState.Tier.CONTAINER,
	PoetryGameState.Tier.OBJECT,
]

const TIER_SHORT := ["Ls", "St", "Rm", "Cn", "Ob"]

enum UISession { SETUP_GOAL, SETUP_OPENING, PLAYING }

var state: PoetryGameState

var _ui_phase: UISession = UISession.SETUP_GOAL
var _selected_anchor_id: int = -1
var _selected_tier: int = PoetryGameState.Tier.LANDSCAPE
var _pending_anchor_id: int = -1
var _pending_relation: PoetryGameState.Relation = PoetryGameState.Relation.WEST
var _has_pending_slot: bool = false

var _pressure_sel: Dictionary = {}

var _state_refresh_pending: bool = false

var _center: CenterContainer
var _column: VBoxContainer

var _setup_block: VBoxContainer
var _setup_title: Label
var _setup_edit: LineEdit
var _setup_action: Panel

var _play_block: VBoxContainer
var _stats: Label
var _board_area: BoardRoot
var _tier_row: HBoxContainer
var _tier_panels: Array[Panel] = []
var _phrase_edit: LineEdit
var _action_row: HBoxContainer
var _place_chip: Panel
var _resolve_chip: Panel
var _take_chip: Panel
var _log: RichTextLabel
var _new_chip: Panel

var _board_rebuild_queued: bool = false


func _ready() -> void:
	state = PoetryGameState.new()
	state.state_changed.connect(_on_state_changed_deferred)
	state.game_lost.connect(func(r: String): _log_line("[color=red]%s[/color]" % r))
	state.game_won.connect(func(r: String): _log_line("[color=green]%s[/color]" % r))
	_build_shell()
	_build_setup_block()
	_build_play_block()
	_update_phase_blocks()
	_refresh_all()


func _on_state_changed_deferred() -> void:
	if _state_refresh_pending:
		return
	_state_refresh_pending = true
	call_deferred("_flush_state_refresh")


func _flush_state_refresh() -> void:
	_state_refresh_pending = false
	_refresh_all()


func _build_shell() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_center = CenterContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	var outer := HBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.add_child(outer)
	var sp_l := Control.new()
	sp_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(sp_l)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	_column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_column.custom_minimum_size.x = 640
	outer.add_child(_column)
	var sp_r := Control.new()
	sp_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(sp_r)
	var title := Label.new()
	title.text = "The Poetry of Place"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(title)


func _build_setup_block() -> void:
	_setup_block = VBoxContainer.new()
	_setup_block.add_theme_constant_override("separation", 10)
	_setup_title = Label.new()
	_setup_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_setup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_setup_edit = LineEdit.new()
	_setup_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_setup_action = _make_chip("Continue", _on_setup_action)
	_setup_block.add_child(_setup_title)
	_setup_block.add_child(_setup_edit)
	_setup_block.add_child(_setup_action)
	_column.add_child(_setup_block)


func _build_play_block() -> void:
	_play_block = VBoxContainer.new()
	_play_block.add_theme_constant_override("separation", 8)
	_play_block.visible = false
	_stats = Label.new()
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board_area = BoardRoot.new()
	_board_area.mouse_filter = Control.MOUSE_FILTER_PASS
	_board_area.custom_minimum_size = BOARD_MIN
	_board_area.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_tier_row = HBoxContainer.new()
	_tier_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tier_row.add_theme_constant_override("separation", 6)
	for i in range(TIER_ORDER.size()):
		var t: int = TIER_ORDER[i]
		var p := _make_chip(TIER_SHORT[i], _on_tier_chip_input.bind(t))
		p.custom_minimum_size = Vector2(52, 36)
		_tier_panels.append(p)
		_tier_row.add_child(p)
	_phrase_edit = LineEdit.new()
	_phrase_edit.placeholder_text = "Image phrase for the card you’re placing"
	_phrase_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phrase_edit.text_changed.connect(func(_t): _clear_pending_slot(); _queue_board_rebuild())
	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 8)
	_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_place_chip = _make_chip("Place card", _on_place_pressed)
	_resolve_chip = _make_chip("Resolve pressure", _on_resolve_pressed)
	_take_chip = _make_chip("Take object", _on_take_pressed)
	_action_row.add_child(_place_chip)
	_action_row.add_child(_resolve_chip)
	_action_row.add_child(_take_chip)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = false
	_log.scroll_active = true
	_log.custom_minimum_size = Vector2(0, 96)
	_log.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_new_chip = _make_chip("New session", _on_new_session)
	_play_block.add_child(_stats)
	_play_block.add_child(_board_area)
	_play_block.add_child(_tier_row)
	_play_block.add_child(_phrase_edit)
	_play_block.add_child(_action_row)
	_play_block.add_child(_log)
	_play_block.add_child(_new_chip)
	_column.add_child(_play_block)
	_style_tier_row()
	_update_action_chips()


func _make_chip(text: String, on_press: Callable) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(120, 40)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.92, 0.93, 0.96)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.35, 0.38, 0.45)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	var lb := Label.new()
	lb.text = text
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.set_anchors_preset(Control.PRESET_FULL_RECT)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lb.add_theme_font_size_override("font_size", 14)
	lb.add_theme_color_override("font_color", Color(0.06, 0.07, 0.1))
	p.add_child(lb)
	p.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton:
			var m := e as InputEventMouseButton
			if m.pressed and m.button_index == MOUSE_BUTTON_LEFT:
				on_press.call()
	)
	return p


func _on_setup_action() -> void:
	var raw := _setup_edit.text.strip_edges()
	match _ui_phase:
		UISession.SETUP_GOAL:
			state.set_goal(raw)
			_ui_phase = UISession.SETUP_OPENING
			_setup_title.text = "Opening landscape — first image on the board (center)."
			_setup_edit.text = ""
			_setup_edit.placeholder_text = "Phrase for the opening landscape"
			_update_setup_chip_text("Place opening & begin")
		UISession.SETUP_OPENING:
			var err := state.place_opening_landscape(raw)
			if not err.is_empty():
				_log_line("[color=red]%s[/color]" % err)
				return
			_ui_phase = UISession.PLAYING
			_log_line("[b]Play.[/b] Opening placed. Goal: %s" % state.goal)
			_update_phase_blocks()
	_update_phase_blocks()
	_refresh_all()


func _update_setup_chip_text(t: String) -> void:
	var lb: Label = _setup_action.get_child(0) as Label
	if lb:
		lb.text = t


func _update_phase_blocks() -> void:
	match _ui_phase:
		UISession.SETUP_GOAL:
			_setup_block.visible = true
			_play_block.visible = false
			_setup_title.text = "What are you reaching for in this place? (goal)"
			_setup_edit.placeholder_text = "Your goal for this session"
			_update_setup_chip_text("Continue")
		UISession.SETUP_OPENING:
			_setup_block.visible = true
			_play_block.visible = false
			_setup_title.text = "Opening landscape — sits at the center of the board."
			_setup_edit.placeholder_text = "Phrase for the opening landscape"
			_update_setup_chip_text("Place opening & begin")
		UISession.PLAYING:
			_setup_block.visible = false
			_play_block.visible = true


func _on_new_session() -> void:
	state.new_session()
	_ui_phase = UISession.SETUP_GOAL
	_selected_anchor_id = -1
	_clear_pending_slot()
	_pressure_sel.clear()
	_phrase_edit.text = ""
	_update_phase_blocks()
	_log_line("[b]New session.[/b] Enter your goal.")
	_refresh_all()


func _on_tier_chip_input(tier_int: int) -> void:
	_selected_tier = tier_int
	_clear_pending_slot()
	_style_tier_row()
	_queue_board_rebuild()


func _style_tier_row() -> void:
	for i in range(_tier_panels.size()):
		var p := _tier_panels[i]
		var sb := StyleBoxFlat.new()
		var on := int(TIER_ORDER[i]) == _selected_tier
		sb.bg_color = Color(0.75, 0.88, 1.0) if on else Color(0.92, 0.93, 0.96)
		sb.set_border_width_all(2 if on else 1)
		sb.border_color = Color(0.15, 0.35, 0.65) if on else Color(0.35, 0.38, 0.45)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(6)
		p.add_theme_stylebox_override("panel", sb)


func _on_place_pressed() -> void:
	if _ui_phase != UISession.PLAYING or state.game_ended or state.pressure_pending:
		return
	if not _has_pending_slot:
		_log_line("Pick a green ＋ on the board first.")
		return
	var phrase := _phrase_edit.text.strip_edges()
	if phrase.is_empty():
		_log_line("Type an image phrase first.")
		return
	var err := state.place_card(
		phrase,
		_selected_tier as PoetryGameState.Tier,
		_pending_anchor_id,
		_pending_relation,
		[],
		[],
		false)
	if err.is_empty():
		_log_line("Placed — %s" % phrase)
		_phrase_edit.text = ""
		_clear_pending_slot()
	else:
		_log_line("[color=red]%s[/color]" % err)
	_refresh_all()


func _on_resolve_pressed() -> void:
	if not state.pressure_pending:
		return
	var ids: Array = _pressure_sel.keys()
	var err := state.resolve_pressure(ids)
	if err.is_empty():
		_log_line("Pressure resolved.")
		_pressure_sel.clear()
	else:
		_log_line("[color=red]%s[/color]" % err)
	_refresh_all()


func _on_take_pressed() -> void:
	if _selected_anchor_id < 0:
		_log_line("Select an object card on the board (click it).")
		return
	var err := state.take_object(_selected_anchor_id)
	if err.is_empty():
		_log_line("Object taken: %s" % state.carried_phrase())
		_selected_anchor_id = -1
	else:
		_log_line("[color=red]%s[/color]" % err)
	_refresh_all()


func _clear_pending_slot() -> void:
	_has_pending_slot = false
	_pending_anchor_id = -1


func _queue_board_rebuild() -> void:
	if _board_rebuild_queued:
		return
	_board_rebuild_queued = true
	call_deferred("_flush_board_rebuild")


func _flush_board_rebuild() -> void:
	_board_rebuild_queued = false
	_rebuild_board()


func _cell_of_card(cid: int) -> Vector2i:
	var cd: Dictionary = state.cards[cid]
	var raw: Variant = cd.get("cell", Vector2i.ZERO)
	if raw is Vector2i:
		return raw as Vector2i
	if raw is Vector2:
		var v2 := raw as Vector2
		return Vector2i(int(v2.x), int(v2.y))
	return Vector2i.ZERO


func _sorted_board_ids() -> Array[int]:
	var ids: Array[int] = []
	for bid in state.cell_to_id.values():
		ids.append(int(bid))
	ids.sort()
	return ids


func _apply_tile(c: Control, lx: int, ly: int) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = Vector2(float(lx), float(ly))
	c.size = Vector2(CARD, CARD)
	c.custom_minimum_size = Vector2(CARD, CARD)


func _panel_style(bg: Color, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border_w)
	sb.border_color = bg.darkened(0.35)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(6)
	return sb


func _rebuild_board() -> void:
	while _board_area.get_child_count() > 0:
		var ch: Node = _board_area.get_child(0)
		_board_area.remove_child(ch)
		ch.free()
	if state.cards.is_empty():
		_board_area.custom_minimum_size = Vector2(
			maxi(PAD_H * 2 + SLOT, int(BOARD_MIN.x)),
			maxi(PAD_V * 2 + SLOT, int(BOARD_MIN.y)))
		_board_area.queue_redraw()
		return
	var slots: Dictionary = {}
	if _ui_phase == UISession.PLAYING and not state.pressure_pending and not state.game_ended and _selected_anchor_id >= 0:
		slots = state.valid_placement_slots_from_anchor(_selected_tier as PoetryGameState.Tier, _selected_anchor_id)
	var min_x := 999999
	var min_y := 999999
	var max_x := -999999
	var max_y := -999999
	for cid in _sorted_board_ids():
		var cv := _cell_of_card(cid)
		min_x = mini(min_x, cv.x)
		min_y = mini(min_y, cv.y)
		max_x = maxi(max_x, cv.x)
		max_y = maxi(max_y, cv.y)
	for ck in slots.keys():
		var ent: Dictionary = slots[ck]
		var vc: Vector2i = ent["cell"]
		min_x = mini(min_x, vc.x)
		min_y = mini(min_y, vc.y)
		max_x = maxi(max_x, vc.x)
		max_y = maxi(max_y, vc.y)
	var span_x := max_x - min_x + 1
	var span_y := max_y - min_y + 1
	_board_area.custom_minimum_size = Vector2(
		maxi(PAD_H * 2 + span_x * SLOT, int(BOARD_MIN.x)),
		maxi(PAD_V * 2 + span_y * SLOT, int(BOARD_MIN.y)))
	for cid in _sorted_board_ids():
		var cv := _cell_of_card(cid)
		var lx := PAD_H + (cv.x - min_x) * SLOT
		var ly := PAD_V + (cv.y - min_y) * SLOT
		var card_p := Panel.new()
		card_p.mouse_filter = Control.MOUSE_FILTER_STOP
		card_p.z_index = 0
		_apply_tile(card_p, lx, ly)
		var c: Dictionary = state.cards[cid]
		var abbr := PoetryGameState.tier_display(c.tier).substr(0, 1)
		card_p.add_theme_stylebox_override("panel", _panel_style(Color(0.98, 0.95, 0.88), 2))
		var lb := Label.new()
		lb.text = "%s%d\n%s" % [abbr, int(c.impact), _short(str(c.phrase), 18)]
		lb.add_theme_font_size_override("font_size", 13)
		lb.add_theme_color_override("font_color", Color(0.05, 0.06, 0.12))
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.position = Vector2(6, 6)
		lb.size = Vector2(CARD - 12, CARD - 12)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_p.add_child(lb)
		card_p.tooltip_text = "ID %d · %s\n%s" % [cid, PoetryGameState.tier_display(c.tier), str(c.phrase)]
		card_p.gui_input.connect(_on_card_gui.bind(cid))
		if state.pressure_pending and _pressure_sel.has(cid):
			card_p.modulate = Color(1.0, 0.75, 0.55)
		elif not state.pressure_pending and cid == _selected_anchor_id:
			card_p.modulate = Color(0.82, 0.92, 1.0)
		else:
			card_p.modulate = Color.WHITE
		_board_area.add_child(card_p)
	for ck in slots.keys():
		var entry: Dictionary = slots[ck]
		var cl: Vector2i = entry["cell"]
		if state.card_at(cl) >= 0:
			continue
		var lx2 := PAD_H + (cl.x - min_x) * SLOT
		var ly2 := PAD_V + (cl.y - min_y) * SLOT
		var slot_p := Panel.new()
		slot_p.mouse_filter = Control.MOUSE_FILTER_STOP
		slot_p.z_index = 2
		_apply_tile(slot_p, lx2, ly2)
		var g := Color(0.35, 0.82, 0.48)
		slot_p.add_theme_stylebox_override("panel", _panel_style(g, 2))
		var pl := Label.new()
		pl.text = "＋"
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pl.set_anchors_preset(Control.PRESET_FULL_RECT)
		pl.add_theme_font_size_override("font_size", 26)
		pl.add_theme_color_override("font_color", Color(0.02, 0.2, 0.08))
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_p.add_child(pl)
		slot_p.gui_input.connect(_on_slot_gui.bind(ck))
		_board_area.add_child(slot_p)
	_board_area.queue_redraw()


func _short(s: String, n: int) -> String:
	var t := s.strip_edges()
	if t.length() <= n:
		return t
	return t.substr(0, maxi(0, n - 1)) + "…"


func _on_card_gui(event: InputEvent, cid: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if state.pressure_pending:
		if _pressure_sel.has(cid):
			_pressure_sel.erase(cid)
		else:
			_pressure_sel[cid] = true
		_rebuild_board()
		_update_action_chips()
		return
	_clear_pending_slot()
	if _selected_anchor_id != cid:
		_selected_anchor_id = cid
	_refresh_all()


func _on_slot_gui(event: InputEvent, cell_key: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var m := state.valid_placement_slots_from_anchor(_selected_tier as PoetryGameState.Tier, _selected_anchor_id)
	if not m.has(cell_key):
		return
	var d: Dictionary = m[cell_key]
	_pending_anchor_id = int(d["anchor_id"])
	_pending_relation = int(d["relation"]) as PoetryGameState.Relation
	_has_pending_slot = true
	_update_action_chips()
	_queue_board_rebuild()


func _anchor_ok() -> bool:
	if _selected_anchor_id < 0:
		return false
	return state.cards.has(_selected_anchor_id)


func _ensure_anchor() -> void:
	if _anchor_ok():
		return
	if state.cell_to_id.size() == 1:
		for bid in state.cell_to_id.values():
			_selected_anchor_id = int(bid)
			return


func _maybe_auto_slot() -> void:
	if _ui_phase != UISession.PLAYING or state.pressure_pending or state.game_ended:
		return
	if _selected_anchor_id < 0:
		return
	var rels: Array[int] = state.valid_relations_from_anchor(_selected_tier as PoetryGameState.Tier, _selected_anchor_id)
	if rels.size() != 1:
		return
	_pending_anchor_id = _selected_anchor_id
	_pending_relation = rels[0] as PoetryGameState.Relation
	_has_pending_slot = true


func _refresh_all() -> void:
	_board_rebuild_queued = false
	if _ui_phase == UISession.PLAYING:
		if not _anchor_ok():
			_selected_anchor_id = -1
		_ensure_anchor()
		if state.pressure_pending or state.game_ended:
			_clear_pending_slot()
		else:
			_maybe_auto_slot()
	_rebuild_board()
	_refresh_stats()
	_update_action_chips()


func _refresh_stats() -> void:
	if _ui_phase != UISession.PLAYING:
		_stats.text = ""
		return
	if state.cards.is_empty():
		_stats.text = ""
		return
	var lines: PackedStringArray = PackedStringArray([
		state.goal,
		"Cards %d/%d · Shadows %d/%d · Impact %d" % [
			PoetryGameState.MAX_CARDS - state.cards_remaining(),
			PoetryGameState.MAX_CARDS,
			state.shadow_count(),
			PoetryGameState.SHADOW_LOSS_COUNT,
			state.board_impact_sum(),
		],
	])
	if state.carried_object_id >= 0:
		lines.append("Carrying: %s" % state.carried_phrase())
	if state.pressure_pending:
		lines.append("Pressure — pick cards, then Resolve.")
	_stats.text = "\n".join(lines)


func _update_action_chips() -> void:
	if not is_instance_valid(_place_chip):
		return
	var can_place := _ui_phase == UISession.PLAYING and not state.game_ended and not state.pressure_pending \
		and _has_pending_slot and not _phrase_edit.text.strip_edges().is_empty()
	_set_chip_enabled(_place_chip, can_place)
	var can_res := state.pressure_pending and not state.game_ended and _pressure_sel.size() > 0
	_set_chip_enabled(_resolve_chip, can_res)
	var can_take := _ui_phase == UISession.PLAYING and not state.game_ended and not state.pressure_pending \
		and _selected_anchor_id >= 0 and state.cards.has(_selected_anchor_id) \
		and int(state.cards[_selected_anchor_id].tier) == PoetryGameState.Tier.OBJECT
	_set_chip_enabled(_take_chip, can_take)
	_resolve_chip.visible = state.pressure_pending and not state.game_ended


func _set_chip_enabled(p: Panel, on: bool) -> void:
	p.modulate = Color(1, 1, 1, 1) if on else Color(1, 1, 1, 0.38)
	p.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


func _log_line(bb: String) -> void:
	_log.append_text(bb + "\n")


class BoardRoot extends Control:
	func _ready() -> void:
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if r.size.x < 2 or r.size.y < 2:
			return
		draw_rect(r, Color(0.88, 0.9, 0.93))
		draw_rect(r, Color(0.4, 0.45, 0.52), false, 2.0)
