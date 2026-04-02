extends RefCounted
class_name PoetryGameState

## Rules prototype for "The Poetry of Place" — relative placement + core loop.
## Internal positions are integer cells on an unbounded plane; first card at origin.

enum Tier { LANDSCAPE, STRUCTURE, ROOM, CONTAINER, OBJECT }

## New card sits orthogonally adjacent to the anchor: offset added to anchor cell.
enum Relation { WEST, EAST, NORTH, SOUTH }

const MAX_CARDS := 35
const PRESSURE_ABOVE := 7
const SHADOW_LOSS_COUNT := 7

var goal: String = ""

var _next_id: int = 1
var _cards_played: int = 0
var cards: Dictionary = {}  # int id -> Dictionary
var cell_to_id: Dictionary = {}  # Vector2i -> int
var shadow_order: Array[int] = []
var carried_object_id: int = -1
var pressure_pending: bool = false
var game_ended: bool = false

signal state_changed
signal game_lost(reason: String)
signal game_won(reason: String)


static func tier_display(t: Variant) -> String:
	var v := int(t)
	match v:
		Tier.LANDSCAPE: return "Landscape"
		Tier.STRUCTURE: return "Structure"
		Tier.ROOM: return "Room"
		Tier.CONTAINER: return "Container"
		Tier.OBJECT: return "Object"
	return "?"


static func relation_offset(r: Relation) -> Vector2i:
	match r:
		Relation.WEST:
			return Vector2i(-1, 0)
		Relation.EAST:
			return Vector2i(1, 0)
		Relation.NORTH:
			return Vector2i(0, -1)
		Relation.SOUTH:
			return Vector2i(0, 1)
	return Vector2i.ZERO


static func relation_display(r: Relation) -> String:
	match r:
		Relation.WEST:
			return "Left of"
		Relation.EAST:
			return "Right of"
		Relation.NORTH:
			return "Above"
		Relation.SOUTH:
			return "Below"
	return "?"


func start_game(p_goal: String) -> void:
	goal = p_goal
	_next_id = 1
	_cards_played = 0
	cards.clear()
	cell_to_id.clear()
	shadow_order.clear()
	carried_object_id = -1
	pressure_pending = false
	game_ended = false
	_place_new_card("Opening landscape", Tier.LANDSCAPE, Vector2i.ZERO, [], [], false)
	state_changed.emit()


func cards_remaining() -> int:
	return MAX_CARDS - _cards_played


func shadow_count() -> int:
	return shadow_order.size()


func is_shadow_card(id: int) -> bool:
	return shadow_order.has(id)


func _host_card_for_shadow(sid: int) -> int:
	for bid in cell_to_id.values():
		var b: Dictionary = cards[int(bid)]
		for u in b.shadows_under:
			if int(u) == sid:
				return int(bid)
	return -1


func loose_shadow_ids() -> Array[int]:
	var out: Array[int] = []
	for sid in shadow_order:
		var i := int(sid)
		if _host_card_for_shadow(i) < 0:
			out.append(i)
	return out


func shadow_pile_hint() -> String:
	if shadow_order.is_empty():
		return "No shadows yet."
	var bits: PackedStringArray = PackedStringArray()
	for sid in loose_shadow_ids():
		var ph := str(cards[int(sid)].phrase)
		if ph.length() > 24:
			ph = ph.substr(0, 21) + "…"
		bits.append("%d: %s" % [int(sid), ph])
	if bits.is_empty():
		return "All shadows are attached under board cards."
	return "Loose shadows (click list below or type IDs): " + " · ".join(bits)


func board_impact_sum() -> int:
	var s := 0
	for id in cell_to_id.values():
		s += int(cards[id].impact)
	return s


func card_at(cell: Vector2i) -> int:
	return int(cell_to_id.get(cell, -1))


func _neighbors4(c: Vector2i) -> Array[Vector2i]:
	return [c + Vector2i.RIGHT, c + Vector2i.LEFT, c + Vector2i.DOWN, c + Vector2i.UP]


func _tier_at_cell(cell: Vector2i) -> int:
	var id := card_at(cell)
	if id < 0:
		return -1
	return int(cards[id].tier)


func _has_orthogonal_neighbor_with_card(cell: Vector2i) -> bool:
	for n in _neighbors4(cell):
		if card_at(n) >= 0:
			return true
	return false


func placement_error(tier: Tier, cell: Vector2i) -> String:
	if card_at(cell) >= 0:
		return "That position is already occupied."
	if _cards_played >= MAX_CARDS:
		return "No cards left."
	if not _has_orthogonal_neighbor_with_card(cell):
		return "Must be orthogonally adjacent to a card on the board."

	match tier:
		Tier.LANDSCAPE:
			var L := int(Tier.LANDSCAPE)
			if _tier_at_cell(cell + Vector2i.LEFT) == L or _tier_at_cell(cell + Vector2i.RIGHT) == L:
				return ""
			return "Landscape must be horizontally adjacent to a landscape."
		Tier.STRUCTURE:
			if _tier_at_cell(cell + Vector2i.UP) != int(Tier.LANDSCAPE):
				return "Structure must be directly beneath a landscape."
			if _tier_at_cell(cell + Vector2i.LEFT) == int(Tier.STRUCTURE) \
					or _tier_at_cell(cell + Vector2i.RIGHT) == int(Tier.STRUCTURE):
				return "Structures cannot be horizontally adjacent to each other."
			return ""
		Tier.ROOM:
			var up_t := _tier_at_cell(cell + Vector2i.UP)
			if up_t == int(Tier.STRUCTURE):
				return ""
			var R := int(Tier.ROOM)
			if _tier_at_cell(cell + Vector2i.LEFT) == R or _tier_at_cell(cell + Vector2i.RIGHT) == R:
				return ""
			return "Room must be beneath a structure or beside another room."
		Tier.CONTAINER:
			if _tier_at_cell(cell + Vector2i.UP) != int(Tier.ROOM):
				return "Container must be directly beneath a room."
			return ""
		Tier.OBJECT:
			var up_id := card_at(cell + Vector2i.UP)
			if up_id < 0 or int(cards[up_id].tier) != int(Tier.CONTAINER):
				return "Object must be directly beneath a container."
			if bool(cards[up_id].empty_container):
				return "That container no longer holds an object."
			return ""
	return "Unknown tier."


func cell_for_relation(anchor_id: int, relation: Relation) -> Vector2i:
	var c: Dictionary = cards[anchor_id]
	var ac: Vector2i = c.cell
	return ac + relation_offset(relation)


func placement_error_relative(tier: Tier, anchor_id: int, relation: Relation) -> String:
	if not cards.has(anchor_id):
		return "Unknown anchor card."
	if not cell_to_id.has(cards[anchor_id].cell):
		return "Anchor is not on the board."
	var target: Vector2i = cell_for_relation(anchor_id, relation)
	var anchor_cell: Vector2i = cards[anchor_id].cell
	if target == anchor_cell:
		return "Invalid direction."
	# Must be orthogonally adjacent to anchor (relation guarantees this)
	var d := target - anchor_cell
	if abs(d.x) + abs(d.y) != 1:
		return "Invalid direction."
	return placement_error(tier, target)


func can_place_relative(tier: Tier, anchor_id: int, relation: Relation) -> bool:
	return placement_error_relative(tier, anchor_id, relation).is_empty()


func _validate_shadows_under(shadow_ids_under: Array) -> String:
	var seen: Dictionary = {}
	for x in shadow_ids_under:
		var sid := int(x)
		if seen.has(sid):
			return "Duplicate shadow ID in under-list."
		seen[sid] = true
		if not cards.has(sid):
			return "Unknown shadow id %d." % sid
		if not shadow_order.has(sid):
			return "Id %d is not in the shadow pile." % sid
		for bid in cell_to_id.values():
			if int(bid) == sid:
				return "Shadow %d is still on the board." % sid
		var host := _host_card_for_shadow(sid)
		if host >= 0:
			return "Shadow %d is already under card %d." % [sid, host]
	return ""


func _apply_impact_on_place(new_id: int, new_cell: Vector2i, ref_ids: Array) -> void:
	var ref_set: Dictionary = {}
	for r in ref_ids:
		ref_set[int(r)] = true
	for cell in cell_to_id.keys():
		var id := int(cell_to_id[cell])
		if id == new_id:
			continue
		if ref_set.has(id):
			continue
		var p: Vector2i = cards[id].cell
		if p.x == new_cell.x and p.y < new_cell.y:
			continue
		cards[id].impact = int(cards[id].impact) + 1


func _place_new_card(phrase: String, tier: Tier, cell: Vector2i, ref_ids: Array, shadows_under: Array, apply_impact: bool) -> int:
	var id := _next_id
	_next_id += 1
	_cards_played += 1
	var data := {
		"id": id,
		"phrase": phrase,
		"tier": int(tier),
		"impact": 1,
		"cell": cell,
		"refs": ref_ids.duplicate(),
		"shadows_under": shadows_under.duplicate(),
		"empty_container": false,
	}
	cards[id] = data
	cell_to_id[cell] = id
	if apply_impact:
		_apply_impact_on_place(id, cell, ref_ids)
	return id


## shadow_ids_under: shadow card IDs to attach under this new card.
## use_carried_tie: add carried object id to refs for impact, then clear carry.
func place_card(
		phrase: String,
		tier: Tier,
		anchor_id: int,
		relation: Relation,
		ref_ids: Array = [],
		shadow_ids_under: Array = [],
		use_carried_tie: bool = false) -> String:
	if game_ended:
		return "Game is over. Start a new game."
	if pressure_pending:
		return "Resolve pressure first (remove cards until total impact is below 7)."
	var err := placement_error_relative(tier, anchor_id, relation)
	if not err.is_empty():
		return err
	var su_err := _validate_shadows_under(shadow_ids_under)
	if not su_err.is_empty():
		return su_err
	var refs_eff: Array = ref_ids.duplicate()
	if use_carried_tie:
		if carried_object_id < 0:
			return "Nothing carried to tie with."
		if not refs_eff.has(carried_object_id):
			refs_eff.append(carried_object_id)
	var shadows_under: Array = shadow_ids_under.duplicate()
	var target: Vector2i = cell_for_relation(anchor_id, relation)
	_place_new_card(phrase, tier, target, refs_eff, shadows_under, true)
	if use_carried_tie:
		carried_object_id = -1
	if board_impact_sum() > PRESSURE_ABOVE:
		pressure_pending = true
	state_changed.emit()
	_check_end_after_action()
	return ""


func _check_end_after_action() -> void:
	if game_ended:
		return
	if shadow_order.size() >= SHADOW_LOSS_COUNT:
		game_ended = true
		game_lost.emit("Seven shadows — the place is lost.")
		return
	if _cards_played >= MAX_CARDS and not pressure_pending:
		game_ended = true
		game_won.emit("All cards placed — your goal resolves as you describe it.")


func resolve_pressure(remove_ids: Array) -> String:
	if game_ended:
		return "Game is over."
	if not pressure_pending:
		return "No pressure to resolve."
	var s := board_impact_sum()
	for id in remove_ids:
		s -= int(cards[int(id)].impact)
	if s >= PRESSURE_ABOVE:
		return "Total impact must end below 7."
	for id in remove_ids:
		_move_card_to_shadow(int(id))
	pressure_pending = false
	state_changed.emit()
	_check_end_after_action()
	return ""


func _move_card_to_shadow(id: int) -> void:
	if not cards.has(id):
		return
	var c: Dictionary = cards[id]
	if not cell_to_id.has(c.cell):
		return
	cell_to_id.erase(c.cell)
	if not shadow_order.has(id):
		shadow_order.append(id)
	for sid in c.shadows_under:
		var sid_i := int(sid)
		if cards.has(sid_i) and not shadow_order.has(sid_i):
			shadow_order.append(sid_i)


func take_object(object_id: int) -> String:
	if game_ended:
		return "Game is over."
	if not cards.has(object_id):
		return "Invalid object."
	var c: Dictionary = cards[object_id]
	if int(c.tier) != int(Tier.OBJECT):
		return "That is not an object."
	if not cell_to_id.has(c.cell):
		return "Object is not on the board."
	var obj_cell: Vector2i = c.cell
	var up: Vector2i = obj_cell + Vector2i.UP
	var cid := card_at(up)
	if cid < 0 or int(cards[cid].tier) != int(Tier.CONTAINER):
		return "No container above."
	cell_to_id.erase(c.cell)
	carried_object_id = object_id
	cards[cid].empty_container = true
	state_changed.emit()
	return ""


func carried_phrase() -> String:
	if carried_object_id < 0:
		return ""
	return str(cards[carried_object_id].phrase)
