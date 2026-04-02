extends Control

const CELL := 56
const SLOT := CELL + 8
const BOARD_PAD := 12

var state: PoetryGameState
var _selected_anchor_id: int = -1
var _pressure_selected: Dictionary = {}

var _ref_ids_set: Dictionary = {}
var _shadow_under_ids: Dictionary = {}
var _refs_syncing: bool = false
var _shadow_syncing: bool = false
var _pick_refs_by_click: bool = false

var _shadow_row_ids: Array[int] = []

@onready var _vbox: VBoxContainer = $VBox
var _goal_edit: LineEdit
var _start_btn: Button
var _stats: Label
var _board_scroll: ScrollContainer
var _board_root: Control
var _phrase: LineEdit
var _tier: OptionButton
var _relation: OptionButton
var _pick_refs_cb: CheckBox
var _refs: LineEdit
var _shadow_label: Label
var _shadow_list: ItemList
var _shadows_under: LineEdit
var _tie_carried: CheckBox
var _place_btn: Button
var _pressure_label: Label
var _resolve_btn: Button
var _clear_pressure_btn: Button
var _take_btn: Button
var _log: RichTextLabel


func _ready() -> void:
	state = PoetryGameState.new()
	state.state_changed.connect(_refresh_all)
	state.game_lost.connect(_on_lost)
	state.game_won.connect(_on_won)
	_build_ui()
	_refresh_all()


func _build_ui() -> void:
	_goal_edit = LineEdit.new()
	_goal_edit.placeholder_text = "Character goal (first card)"
	_goal_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_btn = Button.new()
	_start_btn.text = "Start / reset game"
	_start_btn.pressed.connect(_on_start)
	_stats = Label.new()
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_board_scroll = ScrollContainer.new()
	_board_scroll.custom_minimum_size = Vector2(420, 280)
	_board_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_board_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_board_root = Control.new()
	_board_root.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_board_root.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_board_scroll.add_child(_board_root)
	_phrase = LineEdit.new()
	_phrase.placeholder_text = "Image phrase"
	_phrase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tier = OptionButton.new()
	for t: int in [
		PoetryGameState.Tier.LANDSCAPE,
		PoetryGameState.Tier.STRUCTURE,
		PoetryGameState.Tier.ROOM,
		PoetryGameState.Tier.CONTAINER,
		PoetryGameState.Tier.OBJECT,
	]:
		_tier.add_item(PoetryGameState.tier_display(t), t)
	_relation = OptionButton.new()
	for r: int in [
		PoetryGameState.Relation.WEST,
		PoetryGameState.Relation.EAST,
		PoetryGameState.Relation.NORTH,
		PoetryGameState.Relation.SOUTH,
	]:
		_relation.add_item(PoetryGameState.relation_display(r), r)
	_pick_refs_cb = CheckBox.new()
	_pick_refs_cb.text = "Pick references by clicking cards (does not change anchor)"
	_pick_refs_cb.toggled.connect(_on_pick_refs_toggled)
	_refs = LineEdit.new()
	_refs.placeholder_text = "Reference card IDs (type, paste, or click mode above)"
	_refs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refs.text_changed.connect(_on_refs_text_changed)
	_shadow_label = Label.new()
	_shadow_label.text = "Loose shadows — click to toggle “under” next placement:"
	_shadow_list = ItemList.new()
	_shadow_list.select_mode = ItemList.SELECT_MULTI
	_shadow_list.allow_reselect = true
	_shadow_list.custom_minimum_size = Vector2(0, 120)
	_shadow_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shadow_list.multi_selected.connect(_on_shadow_multi_selected)
	_shadows_under = LineEdit.new()
	_shadows_under.placeholder_text = "Shadow IDs under (syncs with list; you can still type)"
	_shadows_under.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shadows_under.text_changed.connect(_on_shadows_under_text_changed)
	_tie_carried = CheckBox.new()
	_tie_carried.text = "Use carried object as tie (adds it to refs, clears carry)"
	_place_btn = Button.new()
	_place_btn.text = "Place relative to selected card"
	_place_btn.pressed.connect(_on_place)
	_pressure_label = Label.new()
	_pressure_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_resolve_btn = Button.new()
	_resolve_btn.text = "Resolve pressure (send selected to shadows)"
	_resolve_btn.pressed.connect(_on_resolve_pressure)
	_clear_pressure_btn = Button.new()
	_clear_pressure_btn.text = "Clear pressure selection"
	_clear_pressure_btn.pressed.connect(_on_clear_pressure_sel)
	_take_btn = Button.new()
	_take_btn.text = "Take object (selected card)"
	_take_btn.pressed.connect(_on_take_object)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = true
	_log.scroll_active = true
	_log.custom_minimum_size.y = 120
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 120
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_log)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_goal_edit)
	_vbox.add_child(_start_btn)
	_vbox.add_child(_stats)
	_vbox.add_child(_board_scroll)
	_vbox.add_child(Label.new())
	_vbox.get_child(_vbox.get_child_count() - 1).text = "Click a card to select it as anchor. New cards go Left/Right/Above/Below that card. First landscape starts at the origin."
	_vbox.add_child(_phrase)
	_vbox.add_child(_tier)
	_vbox.add_child(_relation)
	_vbox.add_child(_pick_refs_cb)
	_vbox.add_child(_refs)
	_vbox.add_child(_shadow_label)
	_vbox.add_child(_shadow_list)
	_vbox.add_child(_shadows_under)
	_vbox.add_child(_tie_carried)
	_hrow(_place_btn, _take_btn)
	_vbox.add_child(_pressure_label)
	_hrow(_resolve_btn, _clear_pressure_btn)
	_vbox.add_child(scroll)


func _hrow(a: Control, b: Control) -> void:
	var h := HBoxContainer.new()
	h.add_child(a)
	h.add_child(b)
	_vbox.add_child(h)


func _on_pick_refs_toggled(pressed: bool) -> void:
	_pick_refs_by_click = pressed
	_rebuild_board_ui()


func _sorted_int_keys(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort()
	return keys


func _set_refs_line_from_set() -> void:
	_refs_syncing = true
	var parts: PackedStringArray = PackedStringArray()
	for k in _sorted_int_keys(_ref_ids_set):
		parts.append(str(int(k)))
	_refs.text = ",".join(parts)
	_refs_syncing = false


func _on_refs_text_changed(_new_text: String) -> void:
	if _refs_syncing:
		return
	_ref_ids_set.clear()
	for x in _parse_id_list(_refs.text):
		_ref_ids_set[int(x)] = true


func _set_shadow_line_from_set() -> void:
	_shadow_syncing = true
	var parts: PackedStringArray = PackedStringArray()
	for k in _sorted_int_keys(_shadow_under_ids):
		parts.append(str(int(k)))
	_shadows_under.text = ",".join(parts)
	_shadow_syncing = false


func _on_shadows_under_text_changed(_new_text: String) -> void:
	if _shadow_syncing:
		return
	_shadow_under_ids.clear()
	for x in _parse_id_list(_shadows_under.text):
		_shadow_under_ids[int(x)] = true
	_refresh_shadow_list_selection_only()


func _on_shadow_multi_selected(_index: int, _selected: bool) -> void:
	if _shadow_syncing:
		return
	_shadow_under_ids.clear()
	for row in _shadow_list.get_selected_items():
		if row >= 0 and row < _shadow_row_ids.size():
			_shadow_under_ids[_shadow_row_ids[row]] = true
	_set_shadow_line_from_set()


func _prune_shadow_under_selection() -> void:
	var loose: Dictionary = {}
	for sid in state.loose_shadow_ids():
		loose[int(sid)] = true
	for k in _shadow_under_ids.keys():
		if not loose.has(int(k)):
			_shadow_under_ids.erase(k)


func _refresh_shadow_list() -> void:
	if not is_instance_valid(_shadow_list):
		return
	_prune_shadow_under_selection()
	_shadow_syncing = true
	_shadow_list.clear()
	_shadow_row_ids.clear()
	if state.cards.is_empty():
		_shadow_syncing = false
		return
	for sid in state.loose_shadow_ids():
		var ph := str(state.cards[int(sid)].phrase)
		if ph.length() > 36:
			ph = ph.substr(0, 33) + "…"
		_shadow_list.add_item("%d · %s" % [int(sid), ph])
		_shadow_row_ids.append(int(sid))
	for r in range(_shadow_list.item_count):
		if _shadow_under_ids.has(_shadow_row_ids[r]):
			_shadow_list.select(r)
	_shadow_syncing = false


func _refresh_shadow_list_selection_only() -> void:
	if not is_instance_valid(_shadow_list) or _shadow_syncing:
		return
	_shadow_syncing = true
	for r in range(_shadow_list.item_count):
		var sid := _shadow_row_ids[r] if r < _shadow_row_ids.size() else -1
		if sid < 0:
			continue
		if _shadow_under_ids.has(sid):
			if not _shadow_list.is_selected(r):
				_shadow_list.select(r)
		else:
			if _shadow_list.is_selected(r):
				_shadow_list.deselect(r)
	_shadow_syncing = false


func _ref_ids_for_place() -> Array:
	var merged: Dictionary = {}
	for k in _ref_ids_set:
		merged[int(k)] = true
	for x in _parse_id_list(_refs.text):
		merged[int(x)] = true
	return _sorted_int_keys(merged)


func _shadow_ids_for_place() -> Array:
	var merged: Dictionary = {}
	for k in _shadow_under_ids:
		merged[int(k)] = true
	for x in _parse_id_list(_shadows_under.text):
		merged[int(x)] = true
	return _sorted_int_keys(merged)


func _on_start() -> void:
	var g := _goal_edit.text.strip_edges()
	if g.is_empty():
		g = "Unspoken goal"
	state.start_game(g)
	_pressure_selected.clear()
	_ref_ids_set.clear()
	_shadow_under_ids.clear()
	_refs_syncing = true
	_refs.text = ""
	_refs_syncing = false
	_shadow_syncing = true
	_shadows_under.text = ""
	_shadow_syncing = false
	_pick_refs_cb.button_pressed = false
	_pick_refs_by_click = false
	_log_append("[b]New game.[/b] Opening landscape at origin. %s" % state.goal)
	_rebuild_board_ui()


func _rebuild_board_ui() -> void:
	while _board_root.get_child_count() > 0:
		var ch: Node = _board_root.get_child(0)
		_board_root.remove_child(ch)
		ch.free()
	if state.cards.is_empty():
		_board_root.custom_minimum_size = Vector2(BOARD_PAD * 2 + SLOT, BOARD_PAD * 2 + SLOT)
		return
	var min_x := 999999
	var min_y := 999999
	var max_x := -999999
	var max_y := -999999
	for cell in state.cell_to_id.keys():
		var cv: Vector2i = cell
		min_x = mini(min_x, cv.x)
		min_y = mini(min_y, cv.y)
		max_x = maxi(max_x, cv.x)
		max_y = maxi(max_y, cv.y)
	var span_x := max_x - min_x + 1
	var span_y := max_y - min_y + 1
	_board_root.custom_minimum_size = Vector2(
		BOARD_PAD * 2 + span_x * SLOT,
		BOARD_PAD * 2 + span_y * SLOT)
	for cell in state.cell_to_id.keys():
		var cid := int(state.cell_to_id[cell])
		var cv: Vector2i = cell
		var lx := BOARD_PAD + (cv.x - min_x) * SLOT
		var ly := BOARD_PAD + (cv.y - min_y) * SLOT
		var b := Button.new()
		b.position = Vector2(lx, ly)
		b.custom_minimum_size = Vector2(CELL, CELL)
		b.size = Vector2(CELL, CELL)
		b.clip_text = true
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(_on_board_card_pressed.bind(cid))
		_style_board_button(b, cid)
		_board_root.add_child(b)


func _style_board_button(b: Button, cid: int) -> void:
	var c: Dictionary = state.cards[cid]
	var abbr := PoetryGameState.tier_display(c.tier).substr(0, 1)
	b.text = "%s%d\n%s" % [abbr, int(c.impact), _short_phrase(str(c.phrase))]
	var tip := "ID %d · %s\n%s" % [cid, PoetryGameState.tier_display(c.tier), str(c.phrase)]
	var su: Array = c.shadows_under
	if su.size() > 0:
		var ids_txt: PackedStringArray = PackedStringArray()
		for x in su:
			ids_txt.append(str(x))
		tip += "\nShadows under: " + ", ".join(ids_txt)
	b.tooltip_text = tip
	if state.pressure_pending and _pressure_selected.has(cid):
		b.modulate = Color(1.0, 0.82, 0.65)
	elif not state.pressure_pending and cid == _selected_anchor_id:
		b.modulate = Color(0.85, 0.95, 1.0)
	elif _pick_refs_by_click and not state.pressure_pending and _ref_ids_set.has(cid):
		b.modulate = Color(0.75, 1.0, 0.75)
	else:
		b.modulate = Color.WHITE


func _on_board_card_pressed(card_id: int) -> void:
	if state.pressure_pending:
		if _pressure_selected.has(card_id):
			_pressure_selected.erase(card_id)
		else:
			_pressure_selected[card_id] = true
	elif _pick_refs_by_click:
		if _ref_ids_set.has(card_id):
			_ref_ids_set.erase(card_id)
		else:
			_ref_ids_set[card_id] = true
		_set_refs_line_from_set()
	else:
		_selected_anchor_id = card_id
	_rebuild_board_ui()


func _parse_id_list(raw_line: String) -> Array:
	var out: Array = []
	var raw := raw_line.strip_edges()
	if raw.is_empty():
		return out
	for part in raw.split(","):
		var s := part.strip_edges()
		if s.is_valid_int():
			out.append(s.to_int())
	return out


func _on_place() -> void:
	if state.cards.is_empty():
		_log_append("Start a game first.")
		return
	if _selected_anchor_id < 0:
		_log_append("Select an anchor card on the board.")
		return
	var phrase := _phrase.text.strip_edges()
	if phrase.is_empty():
		phrase = "Untitled image"
	var tier: PoetryGameState.Tier = _tier.get_item_id(_tier.selected) as PoetryGameState.Tier
	var rel: PoetryGameState.Relation = _relation.get_item_id(_relation.selected) as PoetryGameState.Relation
	var refs := _ref_ids_for_place()
	var under := _shadow_ids_for_place()
	var err := state.place_card(
		phrase, tier, _selected_anchor_id, rel, refs, under, _tie_carried.button_pressed)
	if err.is_empty():
		var tgt: Vector2i = state.cell_for_relation(_selected_anchor_id, rel)
		_log_append("Placed [%s] “%s” %s #%d → cell %s — board impact %d." % [
			PoetryGameState.tier_display(tier),
			phrase,
			PoetryGameState.relation_display(rel),
			_selected_anchor_id,
			tgt,
			state.board_impact_sum(),
		])
		if not under.is_empty():
			_log_append("Shadows under: %s" % str(under))
		if state.pressure_pending:
			_log_append("[color=yellow]Pressure: total impact above 7. Select cards to remove, then Resolve.[/color]")
		_phrase.text = ""
		_ref_ids_set.clear()
		_shadow_under_ids.clear()
		_refs_syncing = true
		_refs.text = ""
		_refs_syncing = false
		_shadow_syncing = true
		_shadows_under.text = ""
		_shadow_syncing = false
		_tie_carried.button_pressed = false
	else:
		_log_append("[color=red]%s[/color]" % err)


func _on_resolve_pressure() -> void:
	var ids: Array = _pressure_selected.keys()
	var err := state.resolve_pressure(ids)
	if err.is_empty():
		_log_append("Pressure resolved. Shadows: %d. Board impact: %d." % [
			state.shadow_count(), state.board_impact_sum()
		])
		_pressure_selected.clear()
	else:
		_log_append("[color=red]%s[/color]" % err)


func _on_clear_pressure_sel() -> void:
	_pressure_selected.clear()
	_rebuild_board_ui()


func _on_take_object() -> void:
	if _selected_anchor_id < 0:
		_log_append("Select a card (the object) on the board.")
		return
	var err := state.take_object(_selected_anchor_id)
	if err.is_empty():
		_selected_anchor_id = -1
		_log_append("Object taken. Carried: “%s”." % state.carried_phrase())
	else:
		_log_append("[color=red]%s[/color]" % err)


func _on_lost(reason: String) -> void:
	_log_append("[color=red][b]%s[/b][/color]" % reason)


func _on_won(reason: String) -> void:
	_log_append("[color=green][b]%s[/b][/color]" % reason)


func _anchor_on_board() -> bool:
	if _selected_anchor_id < 0:
		return false
	for bid in state.cell_to_id.values():
		if int(bid) == _selected_anchor_id:
			return true
	return false


## When only one card is on the board, select it as anchor so the first placement works without an extra click.
func _ensure_default_anchor() -> void:
	if state.pressure_pending:
		return
	if _anchor_on_board():
		return
	if state.cell_to_id.size() != 1:
		return
	for bid in state.cell_to_id.values():
		_selected_anchor_id = int(bid)
		return


func _refresh_all() -> void:
	_refresh_shadow_list()
	if not _anchor_on_board():
		_selected_anchor_id = -1
	_ensure_default_anchor()
	_rebuild_board_ui()
	_refresh_stats()


func _refresh_stats() -> void:
	if state.cards.is_empty():
		_stats.text = "Not started."
		_pressure_label.text = ""
		return
	var parts: PackedStringArray = PackedStringArray([
		"Goal: %s" % state.goal,
		"Cards used: %d / %d · Shadows: %d / %d · Board impact: %d" % [
			PoetryGameState.MAX_CARDS - state.cards_remaining(),
			PoetryGameState.MAX_CARDS,
			state.shadow_count(),
			PoetryGameState.SHADOW_LOSS_COUNT,
			state.board_impact_sum(),
		],
	])
	if state.carried_object_id >= 0:
		parts.append("Carrying object: “%s”" % state.carried_phrase())
	parts.append(state.shadow_pile_hint())
	_stats.text = "\n".join(parts)
	if state.pressure_pending:
		_pressure_label.text = "Pressure: remove cards until total impact is below 7. Selected: %d card(s)." % _pressure_selected.size()
	else:
		_pressure_label.text = ""


func _short_phrase(s: String) -> String:
	if s.length() <= 40:
		return s
	return s.substr(0, 37) + "…"


func _log_append(bb: String) -> void:
	_log.append_text(bb + "\n")
