extends Minigame

class_name JunkPlatformMinigame

const player_scene = preload("uid://t7tv7x86oo7o")

@export_category("Nodes")
@export var players_node: Node3D
@export var player_spawn_position_node: Node3D
@export var junks_node: Node3D
@export var camera_base: Node3D
@export var visuals_base: Node3D
@export var camera_shaker: ShakerComponent3D
@export var camera: Camera3D
@export var platforms: Array[JunkPlatformPlatform]
@export var ambience_speaker_controllers: Array[SpeakerController]

@export_category("Components")
@export var junk_handler: JunkPlatformJunkHandler

@export_category("States")
@export var countdown_state: State

var players: Dictionary[int, JunkPlatformPlayer]
var active_players: Dictionary[int, JunkPlatformPlayer]

var dead_players: Array[int]
# 8P MOD: when each player died, so victims of one event (the same train, the
# same dropped tile) can share a placement instead of being ranked by signal
# arrival order - Globals.mod_share_tied_placements(), MINIGAMES.md section 24.
var mod_death_msec: Dictionary[int, int] = {}
var player_scores: Dictionary[int, int]
var finished: bool = false

var player_count: int = 0

# --- 8P MOD ------------------------------------------------------------------
# The [PLATFORM] audit below is diagnostic only, gated behind -localtest. The
# gameplay change - a platform per player above four - is the ring section
# further down; neither runs in a 1-4 player game.
#
# The platform deck is a CylinderShape3D of radius 6.0 centred on each Platform
# node, and the four shipped spawn markers sit exactly on those four centres.
# The audit measures every spawned player against the nearest platform centre
# on every peer, so a player who is not standing on a deck - or two who share
# one - shows up in the logs rather than only on screen.
const MOD_PLATFORM_RADIUS: float = 6.0
# spawn_players() is host-only, so a host-side print says nothing about what
# clients see (UPDATING.md, "How to verify anything"). This audit runs on every
# peer and reads global_position, which setup_rpc replicates to all of them.
const MOD_AUDIT_DELAY: float = 6.0

func _mod_localtest_audit() -> void:
	await get_tree().create_timer(MOD_AUDIT_DELAY).timeout

	var tag := "[PLATFORM] is_server=%s peer=%d" % [
		multiplayer.is_server(), multiplayer.get_unique_id()]

	var centres: Array[Vector3] = []
	for p in platforms:
		if p != null:
			centres.append(p.global_position)

	var markers := 0
	if player_spawn_position_node != null:
		markers = player_spawn_position_node.get_child_count()

	print(tag, " markers=", markers, " platforms=", centres.size(),
		" spawned=", players_node.get_child_count())

	# A count of 0 anywhere above means a lookup failed silently.
	if centres.is_empty() or markers == 0:
		push_warning("[PLATFORM] lookup failed: markers=%d platforms=%d"
			% [markers, centres.size()])
		return

	for child in players_node.get_children():
		if not child is Node3D:
			continue
		var pos: Vector3 = (child as Node3D).global_position
		var best: float = -1.0
		var idx: int = -1
		for i in centres.size():
			var d := Vector2(pos.x - centres[i].x, pos.z - centres[i].z).length()
			if best < 0.0 or d < best:
				best = d
				idx = i
		print(tag, " player=", child.name,
			" pos=(%.2f, %.2f, %.2f)" % [pos.x, pos.y, pos.z],
			" platform=", idx + 1, " dist=%.2f" % best,
			" ON_DECK" if best <= MOD_PLATFORM_RADIUS else " OFF_DECK")

# --- 8P MOD: one platform per player above four ------------------------------
# Until 2026-11-09 a 5-8 player round seated TWO players on each of the four
# shipped platforms. That is not a cosmetic compromise: junk_handler drops one
# piece of debris per PLAYER spawn point per tick, so a shared deck took debris
# at twice the vanilla rate against the same collapse threshold, and whoever
# shared it died together. With five or seven players it was also lopsided -
# one pair doubled up while the rest played the vanilla game.
#
# Above four players the level now becomes a square ring of platforms, built on
# every peer by zz_mod_build_ring_rpc(): the four shipped corners slide out
# from 13 to MOD_RING_SPACING, and one or two mirror pairs are cloned onto the
# mid-edges - six platforms for 5-6 players, eight for 7-8. Each player gets a
# deck of their own and exactly one debris stream, as in vanilla. Nothing here
# runs at four players or fewer, and the .tscn is untouched (rule 3).
#
# Why the corners move instead of the extras squeezing in between them: at the
# shipped spacing a mid-edge deck would sit 1.0u from its neighbours, which a
# 0.7u-radius character can walk across - and a player who can step off a
# collapsing platform has no game left. The pillar art is also 8.62u deep on
# its camera side (6.68u on the other), so two rows need 15.3u between centres
# before the meshes stop intersecting. 15.5 clears both and keeps the near
# row's deck inside the camera frame (front edge z=21.5 against a frustum edge
# of 23.4 on the deck plane). MINIGAMES.md section 15 has the measurements.
const MOD_VANILLA_PLATFORMS: int = 4
const MOD_RING_SPACING: float = 15.5
# Mid-edge centres as multiples of MOD_RING_SPACING, in the order they are
# built. Consecutive entries are mirror images through the origin: the camera
# and the art turn 180 degrees for players on the far row, so every platform
# needs a partner whose art stands in for its own on those clients - the same
# pairing the shipped scene wires as Platform1<->3 and Platform2<->4.
const MOD_RING_EXTRAS: Array[Vector3] = [
	Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
	Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, 1.0),
]
# A compactor reaches these through exported node references, and duplicate()
# copies such a reference as a pointer to the ORIGINAL's node (pitfall 37) - a
# cloned press would slam, spark and kill on the platform it was copied from.
const MOD_COMPACTOR_NODE_EXPORTS: Array[StringName] = [
	&"visual", &"particle", &"area", &"speaker_slam",
]
# Vanilla's debris pool is 40 pieces for four players. It is a ceiling, not a
# pace: in a four-player round it is rarely reached. With eight streams it is
# hit within seconds and every stream then starves, so the pool keeps vanilla's
# ten pieces per player.
const MOD_JUNK_PER_PLAYER: int = 10
# A press that has come down is a 23u-tall block, and vanilla leaves it there.
# With four corner platforms that is harmless: the camera looks down the open
# middle of the level. In the ring it is not - the near-middle press stands
# squarely between the camera and the far-middle platform and hides whoever is
# still alive on it, and a near-corner press covers half of the side platform
# behind it (reported from an 8-player run, 2026-11-09). So in a ring round the
# press goes back up after it has landed, and the dead platform drops into the
# pit instead of standing there looking playable. Four-player rounds never
# build the ring and keep vanilla's press exactly as shipped.
const MOD_PRESS_HOLD: float = 1.0
const MOD_PRESS_LIFT_TIME: float = 0.8
const MOD_COLLAPSE_DROP: float = 70.0
const MOD_COLLAPSE_TIME: float = 1.2

var mod_ring_built: bool = false
# Platform -> the height its press hangs at, captured before any press moves.
var mod_press_rest_y: Dictionary = {}

func _mod_on_platform_visibility_changed(platform: JunkPlatformPlatform) -> void:
	# collapse_rpc() hides the platform on every peer; that is the only thing
	# that ever does, so it doubles as the "this platform just died" signal
	# without adding the platform script to the overlay.
	if not is_instance_valid(platform) or platform.visible:
		return
	_mod_clear_collapsed_platform(platform)

func _mod_clear_collapsed_platform(platform: JunkPlatformPlatform) -> void:
	await get_tree().create_timer(MOD_PRESS_HOLD, false).timeout
	if not is_inside_tree() or not is_instance_valid(platform):
		return

	var press: Node3D = platform.compactor
	var lift := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	lift.tween_property(press, "position:y",
		mod_press_rest_y.get(platform, press.position.y), MOD_PRESS_LIFT_TIME)

	# `platform_visuals` names the art standing at this platform on THIS peer,
	# flipped camera or not, so dropping what it names is right everywhere.
	for visual in platform.platform_visuals:
		var sink := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		sink.tween_property(visual, "global_position:y",
			visual.global_position.y - MOD_COLLAPSE_DROP, MOD_COLLAPSE_TIME)
		sink.tween_callback(visual.hide)

	# The deck is gone, so its collider goes too - otherwise debris would pile
	# up on thin air. Found by type rather than by path (pitfall 38).
	var colliders: int = 0
	for child in platform.get_children():
		if child is CSGShape3D:
			child.use_collision = false
			colliders += 1
	if colliders == 0:
		push_warning("[PLATFORM] %s: no pillar collider found to remove" % platform.name)

	# Debris resting on the deck is asleep and would hang there; wake it so it
	# falls to the catcher and returns to the pool. Host-only: debris physics
	# is the host's, clients are sent transforms.
	if multiplayer.is_server():
		for body in platform.get_overlapping_bodies():
			if body is RigidBody3D:
				body.sleeping = false

	if Array(OS.get_cmdline_args()).has("-localtest"):
		print("[PLATFORM] cleared ", platform.name, " is_server=", multiplayer.is_server(),
			" peer=", multiplayer.get_unique_id(), " colliders=", colliders)

func _mod_platform_count(roster: int) -> int:
	# Always an even number above four, so every clone has its mirror partner.
	return MOD_VANILLA_PLATFORMS + 2 * ceili((roster - MOD_VANILLA_PLATFORMS) / 2.0)

func _mod_corner(from: Vector3) -> Vector3:
	return Vector3(signf(from.x) * MOD_RING_SPACING, from.y, signf(from.z) * MOD_RING_SPACING)

func _mod_ring_spawns(shipped: Array[Transform3D], platform_count: int) -> Array[Transform3D]:
	"""Spawn transforms for a ring round: slot -> the centre of its own deck.

	The first four keep the shipped markers' order and facing and move out with
	their corner; the rest follow MOD_RING_EXTRAS. Host-only, like the spawn
	loop that consumes it - positions reach clients through setup_rpc.
	"""
	var out: Array[Transform3D] = []
	for i in mini(MOD_VANILLA_PLATFORMS, shipped.size()):
		var moved: Transform3D = shipped[i]
		moved.origin = _mod_corner(moved.origin)
		out.append(moved)
	for i in platform_count - MOD_VANILLA_PLATFORMS:
		var centre: Vector3 = MOD_RING_EXTRAS[i] * MOD_RING_SPACING
		# Far-row slots face the way the shipped far-row markers do.
		var facing: Basis = Basis(Vector3.UP, PI) if centre.z < 0.0 else Basis.IDENTITY
		out.append(Transform3D(facing, centre))
	return out

func _mod_shift_platform(platform: JunkPlatformPlatform, delta: Vector3) -> void:
	"""Move a shipped platform and everything that belongs to it.

	World-space moves throughout: the art lives under visuals_base, which is
	turned 180 degrees on far-row clients, and `platform_visuals` always names
	the art currently standing at this platform - so shifting what it names in
	world space is right whether or not this peer has flipped yet.
	"""
	platform.global_position += delta
	for visual in platform.platform_visuals:
		visual.global_position += delta
	platform.compactor.global_position += delta
	platform.speaker_alarm.global_position += delta

func _mod_rebind_compactor(template: Node, copy: Node) -> int:
	var rebound: int = 0
	for prop in MOD_COMPACTOR_NODE_EXPORTS:
		var ref: Node = template.get(prop) as Node
		if ref == null:
			push_warning("[PLATFORM] %s has no %s to rebind" % [template.name, prop])
			continue
		var mine: Node = copy.get_node_or_null(template.get_path_to(ref))
		if mine == null:
			push_warning("[PLATFORM] %s has no node for %s" % [copy.name, prop])
			continue
		copy.set(prop, mine)
		rebound += 1
	return rebound

func _mod_clone_platform(source: JunkPlatformPlatform, centre: Vector3, number: int) -> JunkPlatformPlatform:
	"""Stand a complete platform at `centre`, copied from a shipped corner.

	A platform is four separate things in this scene - the Area3D with its
	pillar collider, the art (pillar mesh + the deck's indicator rings), the
	compactor overhead and the alarm speaker - tied together only by the
	platform's exported references. Each is copied and the references rebuilt.
	"""
	var delta: Vector3 = centre - source.global_position

	var art: Array[Node3D] = []
	var rings: Node3D = null
	for visual in source.platform_visuals:
		var visual_copy: Node3D = visual.duplicate()
		visual_copy.name = "%s_MOD%d" % [visual.name, number]
		visual.get_parent().add_child(visual_copy)
		visual_copy.global_transform = visual.global_transform.translated(delta)
		art.append(visual_copy)
		if visual == source.damage_circle_parent:
			rings = visual_copy
	if rings == null:
		push_warning("[PLATFORM] %s: indicator rings not among its visuals" % source.name)
		return null

	var press: JunkPlatformCompactor = source.compactor.duplicate()
	press.name = "%s_MOD%d" % [source.compactor.name, number]
	# Before add_child(): _ready() connects the kill area it finds in `area`.
	var rebound: int = _mod_rebind_compactor(source.compactor, press)
	source.compactor.get_parent().add_child(press)
	press.global_position = source.compactor.global_position + delta

	var alarm: AudioStreamPlayer3D = source.speaker_alarm.duplicate()
	alarm.name = "%s_MOD%d" % [source.speaker_alarm.name, number]
	source.speaker_alarm.get_parent().add_child(alarm)
	alarm.global_position = source.speaker_alarm.global_position + delta

	# Instantiated, not duplicate()d: the sub-scene wires its own timer, mesh
	# and materials through node paths that only resolve on instantiation
	# (pitfall 20). The exports that point OUT of it are assigned by hand, before
	# add_child(), because _ready() reads damage_circle_parent.
	var packed: PackedScene = load(source.scene_file_path)
	if packed == null:
		push_warning("[PLATFORM] no scene behind %s" % source.name)
		return null
	var platform: JunkPlatformPlatform = packed.instantiate()
	platform.name = "Platform_MOD%d" % number
	platform.transform = Transform3D(source.global_transform.basis, centre)
	platform.damage_circle_parent = rings
	platform.platform_visuals = art
	platform.compactor = press
	platform.speaker_alarm = alarm
	# Its mirror partner does not exist yet; zz_mod_build_ring_rpc() re-points
	# these once it does. Own art meanwhile, so nothing is ever null.
	platform.damage_circle_parent_flipped = rings
	platform.platform_visuals_flipped = art
	platform.compactor_flipped = press
	add_child(platform)

	if Array(OS.get_cmdline_args()).has("-localtest"):
		print("[PLATFORM] clone ", platform.name, " from=", source.name,
			" centre=(%.1f, %.1f, %.1f)" % [centre.x, centre.y, centre.z],
			" art=", art.size(), " rebound=", rebound, "/", MOD_COMPACTOR_NODE_EXPORTS.size())
	return platform

# The `zz_` prefix is load-bearing: Godot assigns RPC wire ids by sorting each
# script chain's @rpc names alphabetically, so every mod RPC must sort AFTER the
# vanilla ones to leave vanilla's ids identical to an unmodded build (pitfall
# 30). Sent only above four players, so it never reaches a vanilla peer.
@rpc("authority", "call_local", "reliable")
func zz_mod_build_ring_rpc(platform_count: int) -> void:
	"""Turn the four-platform level into the ring, on every peer.

	spawn_players() is host-only, so a local change there would leave seven of
	eight players looking at the shipped level ("Runtime scene changes must be
	RPCs" in UPDATING.md). Reliable and sent before the first setup_rpc, so a
	client has the ring before anything refers to it.
	"""
	if mod_ring_built:
		return
	mod_ring_built = true

	if platforms.size() != MOD_VANILLA_PLATFORMS:
		push_warning("[PLATFORM] expected %d shipped platforms, found %d - ring not built"
			% [MOD_VANILLA_PLATFORMS, platforms.size()])
		return

	var shipped: Array[JunkPlatformPlatform] = []
	shipped.assign(platforms)
	for platform in shipped:
		_mod_shift_platform(platform, _mod_corner(platform.global_position) - platform.global_position)

	var built: Array[JunkPlatformPlatform] = []
	var extras: int = clampi(platform_count - MOD_VANILLA_PLATFORMS, 0, MOD_RING_EXTRAS.size())
	for i in extras:
		var clone: JunkPlatformPlatform = _mod_clone_platform(
			shipped[i % shipped.size()],
			MOD_RING_EXTRAS[i] * MOD_RING_SPACING,
			MOD_VANILLA_PLATFORMS + 1 + i)
		if clone == null:
			break
		built.append(clone)

	# Cross-wire each mirror pair, as the scene does for the shipped four.
	for i in range(0, built.size() - 1, 2):
		var near: JunkPlatformPlatform = built[i]
		var far: JunkPlatformPlatform = built[i + 1]
		near.damage_circle_parent_flipped = far.damage_circle_parent
		near.platform_visuals_flipped = far.platform_visuals
		near.compactor_flipped = far.compactor
		far.damage_circle_parent_flipped = near.damage_circle_parent
		far.platform_visuals_flipped = near.platform_visuals
		far.compactor_flipped = near.compactor

	platforms.append_array(built)

	# Every platform in a ring round, shipped or cloned, clears itself away
	# once it has collapsed - see MOD_PRESS_HOLD.
	for platform in platforms:
		mod_press_rest_y[platform] = platform.compactor.position.y
		platform.visibility_changed.connect(_mod_on_platform_visibility_changed.bind(platform))

	if Array(OS.get_cmdline_args()).has("-localtest"):
		print("[PLATFORM] ring is_server=", multiplayer.is_server(),
			" peer=", multiplayer.get_unique_id(),
			" asked=", platform_count, " platforms=", platforms.size(),
			" cloned=", built.size(), " spacing=", MOD_RING_SPACING)

func _ready() -> void :
	super._ready()

	camera.current = true

	if Array(OS.get_cmdline_args()).has("-localtest"):
		_mod_localtest_audit()

	if multiplayer.is_server():

		countdown_state.countdown_started.connect(_on_countdown_started)
		countdown_state.tick.connect(_on_countdown_tick)
		countdown_state.expired.connect(_on_countdown_expired)

	if GameManager.local_game:
		await get_tree().create_timer(1.0).timeout
		minigame_ready.emit(1)

func fade_in_ambience():
	for speaker_controller in ambience_speaker_controllers:
		speaker_controller.speaker.volume_linear = 0
		speaker_controller.fade_duration = 3
		speaker_controller.fade_in_custom(db_to_linear(speaker_controller.original_volume_db), true)

func all_players_loaded():
	super.all_players_loaded()

	if not multiplayer.is_server():
		return

	is_all_player_loaded = true
	minigame_ready.emit(multiplayer.get_unique_id())

func initialize(_round_number: int, _total_rounds: int, _scores: Dictionary = {}):
	super.initialize(_round_number, _total_rounds, _scores)

	spawn_players()

	round_number = _round_number
	total_rounds = _total_rounds
	minigame_overlay.set_round_rpc.rpc(_round_number, _total_rounds)

	state_machine.transition_to_rpc.rpc(&"Round", {"round": _round_number, "total": _total_rounds})

func spawn_players():

	player_count = PlayerManager.player_presences.size()
	var spawn_positions: Array[Transform3D]
	for p in player_spawn_position_node.get_children():
		spawn_positions.append(p.global_transform)
	if GameManager.local_game:
		spawn_positions.shuffle()

	# 8P MOD: above four players everyone gets a platform of their own. The ring
	# is built on every peer first, then the spawn list is rebuilt from its
	# centres - the scene's `_MOD` markers (two per shipped deck) are no longer
	# read. Online only; couch mode never exceeds four.
	var mod_ring: bool = player_count > MOD_VANILLA_PLATFORMS and not GameManager.local_game
	if mod_ring:
		var mod_platform_count: int = _mod_platform_count(player_count)
		zz_mod_build_ring_rpc.rpc(mod_platform_count)
		spawn_positions = _mod_ring_spawns(spawn_positions, mod_platform_count)
		junk_handler.max_junk = maxi(junk_handler.max_junk, MOD_JUNK_PER_PLAYER * player_count)

	for i in PlayerManager.player_presences.size():
		var network_id = PlayerManager.player_presences.keys()[i]

		var camera_rotation: float = 0.0
		var position: Vector3 = spawn_positions[i].origin
		var player_character: JunkPlatformPlayer = player_scene.instantiate()
		players_node.add_child(player_character, true)

		junk_handler.add_spawn_point(
			network_id, 
			position + (Vector3.UP * 20.0)
		)

		player_character.network_id = network_id

		if position.z < 0:
			camera_rotation = 180.0

		if GameManager.local_game:
			camera_rotation = rad_to_deg(spawn_positions[i].basis.get_euler().y)

		if Array(OS.get_cmdline_args()).has("-localtest"):
			var spawn_marker: Node3D = player_spawn_position_node.get_child(i)
			print("[PLATFORM] assign slot=", i, " id=", network_id,
				" marker=", "ring" if mod_ring else spawn_marker.name,
				" pos=(%.2f, %.2f, %.2f)" % [position.x, position.y, position.z],
				" camrot=", camera_rotation)

		player_character.set_player_presence.rpc(network_id)
		player_character.setup_rpc.rpc(
			position, camera_rotation
		)

		if not GameManager.local_game and camera_rotation > 0.0:

			if network_id == 1:
				camera_base.rotation_degrees.y = camera_rotation
				visuals_base.rotation_degrees.y = camera_rotation
				for j in platforms:
					j.damage_circle_parent = j.damage_circle_parent_flipped
					j.platform_visuals = j.platform_visuals_flipped
					j.assign_indicators()
					j.assign_flipped_compactor()
			else:
				rotate_camera_rpc.rpc_id(network_id, camera_rotation)

		player_character.emit_died.connect(_on_player_died)
		player_character.event_fallen.connect(_on_player_fallen)

		players[network_id] = player_character
		active_players[network_id] = player_character
		player_scores[network_id] = 0


func cleanup():

	if is_multiplayer_authority():
		queue_free()

func player_disconnected(_network_id: int):
	super.player_disconnected(_network_id)

	if not multiplayer.is_server():
		return

	# 8P MOD: before the game has started there is nothing to end - the peer
	# was never spawned here and its presence is already pruned. Vanilla's end
	# check below would see zero players and finish an unstarted game
	# (pitfall 32; session log 2026-08-15).
	if not is_all_player_loaded:
		return

	remove_player_rpc.rpc(_network_id)
	await get_tree().create_timer(1.0).timeout

	check_game_end()


func check_game_end():

	if finished:
		return

	if active_players.size() > 1:
		return

	finished = true

	for i in dead_players.size():
		player_scores[dead_players[i]] = i

	# 8P MOD: same-moment deaths share the best placement of their group. Above
	# four players only, so a 1-4 lobby keeps vanilla's ordering (rule 3).
	if player_count > Globals.MOD_VANILLA_ROSTER:
		Globals.mod_share_tied_placements(player_scores, dead_players, mod_death_msec)

	for network_id in active_players.keys():
		player_scores[network_id] = player_count


		break

	player_scores_finalized.emit(player_scores)

	await get_tree().create_timer(2.0).timeout
	set_minigame_sfx_linear_volume_rpc.rpc(0.0)

	state_machine.transition_to_rpc.rpc(&"Finished")
	set_effects_visibility_rpc.rpc(false)



@rpc("any_peer", "call_remote", "reliable")
func rotate_camera_rpc(_rotation: float):
	camera_base.rotation_degrees.y = _rotation
	visuals_base.rotation_degrees.y = _rotation
	for i in platforms:
		i.damage_circle_parent = i.damage_circle_parent_flipped
		i.platform_visuals = i.platform_visuals_flipped
		i.assign_indicators()
		i.assign_flipped_compactor()

@rpc("any_peer", "call_local", "reliable")
func shake_camera_rpc():
	camera_shaker.play_shake()

@rpc("any_peer", "call_local", "reliable")
func remove_player_rpc(_network_id: int):

	var player_instance = players.get(_network_id, null)
	if player_instance:
		player_instance.queue_free()
		players.erase(_network_id)
		active_players.erase(_network_id)

	if multiplayer.is_server():
		junk_handler.remove_spawn_point(_network_id)



func _on_countdown_expired():
	super._on_countdown_expired()

	for player in players.values():
		player.set_active_rpc.rpc(true)

	junk_handler.set_active(true)

	state_machine.transition_to_rpc.rpc(&"Play")

func _on_player_died(_network_id: int):

	if active_players.has(_network_id):
		active_players.erase(_network_id)
		shake_camera_rpc.rpc()
		if not finished:
			dead_players.append(_network_id)
			mod_death_msec[_network_id] = Time.get_ticks_msec()

	junk_handler.remove_spawn_point(_network_id)

	check_game_end()

func _on_player_fallen(last_hit_by_network_id: int):

	if last_hit_by_network_id > 0:

		if GameManager.local_game:
			AchievementManager.set_achievement("ACH_03")
			return

		if players.has(last_hit_by_network_id):
			players[last_hit_by_network_id].trigger_achievement_rpc.rpc()

	pass
