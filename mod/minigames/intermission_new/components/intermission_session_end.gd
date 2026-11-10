class_name Intermission_SessionEnd extends Node

# --- 8P MOD ------------------------------------------------------------------
# The end-of-session results screen. Vanilla collected ranks 1-4 only, so a 5-8
# player session listed the winner and three "failed" subjects and silently
# dropped everyone below fourth place (MINIGAMES.md section 25).
#
# Simply sending all seven non-winners is not a fix, it is a crash: the screen
# is a fixed stack of `lines` - eight rows plus four inline labels - and
# show_subject_entry() gives the failed list rows 4, 5 and 6, then pads to row
# 8 with a loop that only stops when line_index is EXACTLY 8. A fourth name
# puts line_index past 8, the loop runs on to lines[12], and a method call past
# the end of a typed array takes the process down in the release build
# (pitfall 23). So above three names they are packed several to a row, into the
# same three rows; at three names or fewer the list is passed through untouched
# and a 1-4 player session prints exactly what vanilla prints.
const MOD_MAX_RANKS: int = 8
const MOD_LOSER_ROWS: int = 3
# Names are clipped the way the score screen clips them (8 characters and a
# dash there), so three to a row stay inside the screen's width.
const MOD_NAME_CHARS: int = 10

func _mod_name_rows(names: Array) -> Array:
	if names.size() <= MOD_LOSER_ROWS:
		return names

	var per_row: int = ceili(names.size() / float(MOD_LOSER_ROWS))
	var rows: Array = []
	var row: PackedStringArray = PackedStringArray()
	for entry in names:
		var clipped: String = str(entry)
		if clipped.length() > MOD_NAME_CHARS:
			clipped = clipped.left(MOD_NAME_CHARS - 1) + "-"
		row.append(clipped)
		if row.size() == per_row:
			rows.append(", ".join(row))
			row = PackedStringArray()
	if not row.is_empty():
		rows.append(", ".join(row))
	return rows
@export var intermission: IntermissionManager

@export var viewblocker: Control

@export var label_end: Label
@export var char_delay: float

@export var debug_toggle_vis: Control

@export var speaker_char: AudioStreamPlayer
@export var speakear_wave: AudioStreamPlayer
@export var speaker_computer_start: AudioStreamPlayer
@export var speaker_computer_end: AudioStreamPlayer
@export var vhs_shader: ColorRect
@export var anim_grunge_modulate: AnimationPlayer
@export var anim_intermission_screen_main: AnimationPlayer
@export var session_end_parent: Control
@export var lines: Array[Intermission_EndingInfoLabel]
@export var debug_control: Control
@export var intro: Intermission_Cutscene_Intro
@export var scientist_hand: Node3D
@export var credits: CreditsScene
@export var ketas: TextureRect
@export var tower_base_mesh: Node3D
@export var anim_viewblocker_main: AnimationPlayer

@export var speaker_keyboard_instance_parent: Node
@export var speaker_keyboard_instance: PackedScene
@export var sounds_key_press: Array[AudioStream]
@export var sounds_key_enter: Array[AudioStream]
@export var speaker_show_info: AudioStreamPlayer
@export var speaker_drive_spinup: AudioStreamPlayer
@export var speaker_vitabrevis: AudioStreamPlayer
@export var speaker_outro_amb: AudioStreamPlayer

@export_multiline var end_text: String
@export var end_rich: RichTextLabel

var active_string = ""

var negative_comments = [
		"LOC_END_BAD_01",
		"LOC_END_BAD_02",
		"LOC_END_BAD_03",
		"LOC_END_BAD_04",
		"LOC_END_BAD_05"
		]

var positive_comments = [
		"LOC_END_GOOD_01",
		"LOC_END_GOOD_02",
		"LOC_END_GOOD_03",
		"LOC_END_GOOD_04",
		"LOC_END_GOOD_05",
		"LOC_END_GOOD_06",
		]

var effect_won = "LOC_END_WINNER"
var effect_lose = "LOC_END_LOSER"

var active_winner: String = ""
var active_losers: Array[String] = []
var active_comment_positive_index = 0
var active_comment_negative_index = 0

var line_index = 0
var is_custom_game: bool = true

func _ready() -> void:
	label_end.text = ""
	credits.scroll_finished.connect(credits_scroll_finished)

func send_session_end_data_host():

	if not multiplayer.is_server():
		return

	NetworkManager.set_lobby_joinable(false)

	if PlayerManager.player_presences.size() <= 1:
		exit_session_after_end()
		return

	var network_ids_by_rank: Dictionary[int, int]
	var player_network_ids_in_score_order: Array[int]

	var user_id_threshold: int = 1
	if GameManager.local_game:
		user_id_threshold = -2

	var intermission_score_screen: Intermission_ScoreScreen = intermission.screen_score
	for uc in intermission_score_screen.user_container_array:
		if uc.user_network_id < user_id_threshold:
			continue
		network_ids_by_rank[uc.user_rank_value] = uc.user_network_id

	# 8P MOD: vanilla walks `for i in 5` - ranks 0..4 - so in a 5-8 player
	# session whoever finished fifth or lower was never sent to the results
	# screen at all. Ranks start at 1, so walking 1..8 yields exactly what
	# vanilla's loop does whenever only ranks 1-4 exist.
	for i in range(1, MOD_MAX_RANKS + 1):
		if network_ids_by_rank.has(i):
			player_network_ids_in_score_order.append(network_ids_by_rank.get(i))

	set_viewing_credits_rpc.rpc()

	var send_winner: int = -1
	if not player_network_ids_in_score_order.is_empty():
		send_winner = player_network_ids_in_score_order.pop_front()

	var send_losers: Array[int] = player_network_ids_in_score_order
	var send_comment_positive_index: int = 0
	var send_comment_negative_index: int = 0

	send_comment_negative_index = randi_range(0, negative_comments.size() - 1)
	send_comment_positive_index = randi_range(0, positive_comments.size() - 1)

	set_session_end_data.rpc(
			send_winner,
			send_losers,
			send_comment_positive_index,
			send_comment_negative_index,
			GameManager.custom_game
			)

@rpc("authority", "call_local", "reliable")
func set_session_end_data(
		winner_id: int,
		loser_ids: Array[int],
		positive_comment_index,
		negative_comment_index,
		_is_custom_game: bool,
		):
	PauseMenu.force_close()

	is_custom_game = _is_custom_game
	active_winner = ""
	active_losers.clear()

	active_winner = intermission.get_user_name_from_network_id(winner_id)
	for network_id in loser_ids:
		active_losers.append(intermission.get_user_name_from_network_id(network_id))

	active_comment_positive_index = positive_comment_index
	active_comment_negative_index = negative_comment_index

	intermission.game.game_session_ended.emit()
	setup_session_end_visuals()

func setup_session_end_visuals():
	tower_base_mesh.visible = true
	PauseMenu.set_can_activate(false)
	GameManager.can_set_cursor = false
	viewblocker.visible = true
	anim_grunge_modulate.play("hide")
	speaker_computer_end.play()
	anim_intermission_screen_main.play("turn off screen instant")
	MusicManager.stop_playing_music()
	await get_tree().create_timer(4, false).timeout
	session_end_parent.visible = true
	viewblocker.visible = false
	speaker_computer_start.play()
	anim_intermission_screen_main.play("turn on screen")
	await get_tree().create_timer(3, false).timeout
	show_subject_entry(true, active_losers, false)

func play_sound_keypress(is_enter: bool):
	var sound: AudioStream
	var speaker: AudioStreamPlayer = speaker_keyboard_instance.instantiate()
	speaker_keyboard_instance_parent.add_child(speaker)
	if is_enter:
		sound = sounds_key_enter[randi_range(0, sounds_key_enter.size() - 1)]
	else:
		sound = sounds_key_press[randi_range(0, sounds_key_press.size() - 1)]
	speaker.stream = sound
	speaker.pitch_scale = randf_range(0.95, 1.05)
	speaker.play()

func show_subject_entry(is_first: bool, player_names: Array, won: bool):
	if is_first:
		await add_text(tr("LOC_END_SIM_CONCLUDED"), 1, 1)
		await add_text(tr("LOC_END_CHECK_GENE"), 2, 1)
		add_text("")
		await get_tree().create_timer(1, false).timeout
	if won:
		await add_text(tr("LOC_END_PASS"), 1, 1)
	else:
		await add_text(tr("LOC_END_FAIL"), 1, 1)
	# 8P MOD: one screen row per entry, and the screen has room for three.
	player_names = _mod_name_rows(player_names)
	var counter = 0
	for i in player_names:
		var last_reached = counter == player_names.size() - 1
		await add_text("- %s" % player_names[counter], 1, 0.3)
		if last_reached:
			await get_tree().create_timer(0.3, false).timeout
			for j in 10:
				line_index += 1
				add_text(" ")
				if line_index == 8:
					break
		counter += 1
	if won:
		await get_tree().create_timer(1, false).timeout
		await add_text(tr("LOC_END_COMMENT") + " ", 1, 1)
		await add_text(tr(positive_comments[active_comment_positive_index]), 1, 1)
		await add_text(tr("LOC_END_EFFECT") + " ", 1, 1)
		await add_text(tr(effect_won), 1, 1)
	else:
		await get_tree().create_timer(1, false).timeout
		await add_text(tr("LOC_END_COMMENT") + " ", 1, 1)
		await add_text(tr(negative_comments[active_comment_negative_index]), 1, 1)
		await add_text(tr("LOC_END_EFFECT") + " ", 1, 1)
		await add_text(tr(effect_lose), 1, 0, 0.4)

	if !won:
		await get_tree().create_timer(2, false).timeout
		for i in range(lines.size()):
			if i != 0 && i != 1:
				lines[i].hide_text()
			line_index = 2
		await get_tree().create_timer(0.5, false).timeout
		label_end.text = tr("LOC_END_SIM_CONCLUDED") + "\n" + tr("LOC_END_CHECK_GENE") + "_"
		await add_text("", 2)
		show_subject_entry(false, [active_winner], true)
	else:
		await get_tree().create_timer(3, false).timeout
		for i in lines:
			i.hide_text()
		line_index = 0
		await get_tree().create_timer(0.4, false).timeout
		await add_text(tr("LOC_END_NEXT"), 1, 1.5)
		await add_text(tr("LOC_END_STANDBY"), 1, 2.5)
		add_text("")
		await add_text(tr("LOC_END_RESISTING"), 1, 1, 0.3)

		await get_tree().create_timer(2, false).timeout
		for i in lines:
			if i.label.text != "" && i.label.text != " ":
				i.hide_text()
		line_index = 0
		await get_tree().create_timer(0.4, false).timeout

		if GameManager.local_game:

			var player_counter = 0
			for p in PlayerManager.player_presences.values():
				intermission.cutscene_intro.rack_nametags[player_counter].set_nametag_text(
						p.network_name.to_upper()
						)
				intermission.cutscene_intro.rack_nametags[player_counter].show_nametag()
				player_counter += 1

			if GameManager.custom_game:

				await get_tree().create_timer(0.5, false).timeout
				exit_game_local()
				return

		if is_custom_game:
			await get_tree().create_timer(0.5, false).timeout
			exit_game_custom()
			return

		show_end_text()
		speaker_drive_spinup.play()
		await get_tree().create_timer(1.5, false).timeout
		scientist_hand.visible = false
		intro.anim_intermission_cam.play("outro")
		speaker_outro_amb.play()
		speaker_vitabrevis.play()
		var sc_hum: SpeakerController = speaker_computer_start.get_child(0)
		sc_hum.fade_duration = 4
		sc_hum.fade_out()
		await get_tree().create_timer(25.67, false).timeout
		intro.temp_viewblocker.get_child(0).color = Color(0, 0, 0, 1)
		intro.temp_viewblocker.visible = true
		intro.speaker_intro_wind.stop()
		speaker_outro_amb.stop()
		cut_to_credits()

func exit_game_custom():
	var sc_hum: SpeakerController = speaker_computer_start.get_child(0)
	sc_hum.fade_duration = 1
	sc_hum.fade_out()
	anim_viewblocker_main.play("fade in 1s")
	await get_tree().create_timer(1.05, false).timeout
	exit_session_after_end()
	exit_session_after_end_custom()

func exit_game_local():

	await get_tree().create_timer(1.0).timeout

	var sc_hum: SpeakerController = speaker_computer_start.get_child(0)
	sc_hum.fade_duration = 1
	sc_hum.fade_out()

	var sc: SpeakerController = speaker_vitabrevis.get_child(0)
	sc.fade_duration = 2
	sc.fade_out()
	anim_viewblocker_main.play("fade in")

	GlobalOverlay.fade_overlay(Color.BLACK, 1.0)
	await GlobalOverlay.fade_finished

	if not is_inside_tree():
		return
	await get_tree().create_timer(2.0, false).timeout

	if not is_inside_tree():
		return
	get_tree().change_scene_to_file("res://scenes/local_lobby/local_lobby.tscn")

func credits_scroll_finished():

	if GameManager.local_game and not GameManager.custom_game:

		exit_game_local()
		return

	exit_session_after_end()

func cut_to_credits():

	if not is_custom_game:
		Globals.showing_post_original_menu = true
		Globals.settings["original_finished"] = true
		Globals.save_current_settings()

	await get_tree().create_timer(3, false).timeout
	credits.visible = true
	credits.set_active(true)

func show_end_text():
	var end_lines = end_text.split("\n")
	for i in end_lines:
		end_rich.text += i + "\n"
		await get_tree().create_timer(randf_range(0.03, 0.09), false).timeout
	await get_tree().create_timer(1.5, false).timeout
	end_rich.visible = false
	ketas.visible = true
	await get_tree().create_timer(0.7, false).timeout
	intro.intermission_manager.anim_viewport_screen.play("turn off screen")

func exit_session_after_end():

	Globals.splash_screen_viewed = true
	MusicManager.stop_playing_music(3.0)
	MusicManager.filter_controller.begin_shift(MusicManager.filter_controller.effect_low_pass.cutoff_hz, 20000, 6)
	var sc: SpeakerController = speaker_vitabrevis.get_child(0)
	sc.fade_duration = 2
	sc.fade_out()
	anim_viewblocker_main.play("fade in")

	await get_tree().create_timer(2.2, false).timeout

	if not is_inside_tree():
		return
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

func exit_session_after_end_custom():

	Globals.splash_screen_viewed = true
	MusicManager.filter_controller.begin_shift(MusicManager.filter_controller.effect_low_pass.cutoff_hz, 20000, 6)

	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

func add_text(text: String, num_of_new_lines: int = 1, delay: float = 0, force_pitch: float = 1):
	if text != "" && text != " ":
		speaker_show_info.pitch_scale = randf_range(0.8, 0.9)
		if force_pitch != 1:
			speaker_show_info.pitch_scale = force_pitch
		speaker_show_info.play()
	num_of_new_lines = 1
	lines[line_index].show_text(text)
	if text != " ":
		line_index += num_of_new_lines
	if delay != 0:
		await get_tree().create_timer(delay, false).timeout

@rpc("authority", "call_local", "reliable")
func set_viewing_credits_rpc():
	intermission.game.is_viewing_final_credits = true
