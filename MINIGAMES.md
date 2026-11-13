# Machine Party 8-Player Mod — per-minigame reference

Companion to `UPDATING.md`, which is the entry point: current state, the rules,
the update procedure and the test harness live there; the numbered
pitfalls live in `PITFALLS.md`, and the session log in `SESSION-LOG.md`. **Read
that first.** This file is the detail you only need once you are touching a
specific minigame — every change the mod makes, minigame by minigame, plus the
diagnostic traces and the caps.

Numbered sections here are stable identifiers. `UPDATING.md`'s overlay manifest
maps each overlay file to the section that explains it, so start from the
manifest and come here for the "why".

Cross-file conventions: **pitfall N** always means `PITFALLS.md`;
**rule N** always refers to
`UPDATING.md`; **section N** always refers to this file.

---

## What the mod changes

57 files today; the authoritative count and file list is the overlay manifest
in `UPDATING.md` (CI checks it). Re-apply all of these to the new version.

### 1. `modules/multiplayer/network_manager.gd`
```gdscript
const MAX_PLAYERS: int = 8          # was 4
const MAX_DEBUG_PLAYERS: int = 9    # was 5 (MAX_PLAYERS + 1)
```
That is the entire cap. `steam_backend.gd` feeds `NetworkManager.max_player_count`
into `Steam.createLobby`, and both backends gate joins on `MAX_PLAYERS`.
`MAX_DEBUG_PLAYERS` is deliberately one higher: the spare slot is the `-trailer`
free-fly observer camera, which joins once the real seats are full.

### 2. `autoloads/globals.gd`
- `game_version` = game version + `-8P-` + the mod release label (**bump the
  base version on update; keep the mod release label**). Shown on the main menu
  via `main_menu.gd`. Since vanilla-compat it is the **display** string only:
  `MOD_NETWORK_GAME_VERSION` (vanilla's exact version) and `MOD_SUFFIX` are what
  the handshake puts on the wire. See `UPDATING.md` step 6 — all three have to be
  bumped, and a stale `MOD_NETWORK_GAME_VERSION` silently refuses every vanilla
  peer.
- `CustomizationColors` enum + `suit_colors` array gain `Orange, Cyan, Pink`.
- New `modded_suit_tints` — maps each new colour to a shipped base texture plus
  an `albedo_color` tint. There are only five suit *textures*; the three added
  colours are tints, not new art.
- New `modded_minigame_player_cap` + `supports_player_count()`.
- **`default_playlist` is byte-identical to vanilla** since 2026-08-09, including
  `MinigameIdentifier.CutsceneTest` in its vanilla slot — so there is nothing to
  re-apply here on update. The wheat-field cutscene is still dropped at every
  roster size, but dynamically, in `game.gd` and only when every peer is modded;
  see "The first sanctioned exception" in `UPDATING.md` for why.

### 3. `scripts/scenes/game/game.gd`
- `for p in 4:` → `for p in NetworkManager.MAX_PLAYERS:` (player label array).
- In `generate_session_playlist()`: derive `lobby_size` by counting the
  **non-debug** entries of `NetworkManager.active_backend.connected_players`,
  then skip any minigame failing `Globals.supports_player_count()` — **in all
  three branches** (custom-game, default rotation, and Arcade). The count must
  exclude demoted debug spectators, which do sit in `connected_players`: until
  2026-08-13 it was a plain `.size()`, so a 9th connection (8 players plus a
  demoted spectator) pushed `lobby_size` past every cap and emptied the
  playlist, fallback included — a silent session dead-end (issue #6;
  reproduction in the archived 2026-08-13 session-log entry).
- Fallback: if filtering empties the playlist, rebuild from `default_playlist`
  with the same rule, so a custom playlist of only-capped games cannot dead-end.

**Arcade (game v1.5.0).** Upstream added a third branch that ignores
`session_playlist` entirely and takes ten entries straight off
`Globals.CustomMinigamesWhitelist` (15 long) after a `shuffle()` — the one
playlist path that never consulted the caps, so at 5-8 players it could seat
`ManufactureGun` or `BurnRecycle`. Two changes:

1. Filter the whitelist through `supports_player_count()` before shuffling. At
   1-4 every cap is 4, so nothing is removed and Arcade is bit-for-bit vanilla
   there (rule 3).
2. Clamp the shipped literal `10` with `mini()` against the filtered size.
   Vanilla assumes ≥ 10 candidates; once filtered that is not guaranteed, and
   `array[i]` past the end returns **null silently** in the release template
   (pitfall 23) — so the failure would be nulls in the playlist, not an error.
   Nothing is filtered at any roster size today (`modded_minigame_player_cap`
   holds only `ScavangerChairs`, in neither playlist), so all 15 survive and the
   clamp does not bind. It exists so a future cap change cannot turn silent.

**Run under the harness once, never by people.** `GameManager.arcade_game` is
set only by the main menu's Arcade button and `-localtest` enters via the debug
lobby, so the stock harness never reaches this branch. On 2026-08-17 a
local-only harness aid (not in the repo) forced it: at 8 and at 4 the host built
ten distinct whitelist entries, rounds 1–2, `lobby_size` = seated count, and
sessions played through on every client with no errors (session log). A real
Arcade session with 5–8 people is still untested — issue #4.

Host-authoritative: the host builds the list and ships it via
`update_playlist_state_rpc`, so clients need no equivalent check.

### 4. `scripts/components/character customization/customization_assigner.gd`
- `get_suit_texture()` remaps a modded colour name to its base texture.
- New `get_suit_tint()`.
- `assign_suit_color()` also sets `albedo_color` — white for the five original
  colours, so switching away from a modded suit clears the tint.

### 5. `minigames/chisel_gauntlet_multiplayer/scripts/chisel_gauntlet_local_handler.gd`
`Layouts` dictionary gains keys `5`–`8` (3×2 grid for 5–6, 4×2 for 7–8), as
normalised `[position, size]` Vector2 pairs. Nothing else needed — it builds
viewports with `TextureRect.new()` per player.

### 6. The lobby — two separate blockers, both fatal at 5 players
`scenes/lobby/scripts/lobby_scene.gd` holds `player_order_by_seat`, hardcoded to
four entries. `player_joined_lobby_rpc` walks it for the first free seat, so
players 5-8 join and are never seated. Derive it from `MAX_PLAYERS` (two sites:
the member initialiser, filled in `_ready()`, and the host reset in
`start_host`). `modules/multiplayer_lobby/multiplayer_menu.gd` has its own copy
for the debug lobby.

`scenes/lobby/lobby_scene.tscn` wires exactly four preview characters, and
`lobby_handler.gd` does `customization_assigners[seat]` — an out-of-bounds crash
at seat 4, not a cosmetic overflow. `tools/lobby_expand.py` clones `Player2`
(the compact `ExtResource` variant; `Player1` has its assigner expanded inline)
into `Player5`-`Player8` and extends all four exported arrays.

Note `counter += 1` sits *inside* the `connected_players.has(...)` check, so an
instance that does not know a peer skips it silently. That masks the crash on
clients and is why the bug is easy to miss.

**Where players 5-8 sit (since 2026-11-13): on a chair of their own.** From
2026-08-16 (issue #14) they sat on the laps of 1-4, because the room has only
four upright, visible chairs; players reported it as people "sitting on other
players". Each seat lives in its preview's `Armature_001` transform (the
`PlayerN` nodes at x = −6, −2, 2, 6 are an authoring row, not seats — a lesson
that cost a real lobby, pitfall 35).

Each of `Player5`-`Player8` is now a **rigid copy of vanilla seat 2** —
`Player2` sitting on `chair_001` in `lobby_scene_pose_1`, the pose slots 5-8
already played — moved to a new chair spot: `Armature_001` =
`new chair · chair_001⁻¹ · Player2's armature`, and the nametag moved by the
same motion. Every upright chair in the room shares one mesh (identical AABB
and vertex count), so the body lands on its new chair exactly as Player2 sits
on `chair_001`; the method reproduces Player2's own baked transform to 3e-16 when
handed `chair_001`'s spot. The chair itself is a `chair_MOD5`-`chair_MOD8`
node (the shared `chair_001` mesh) **under the slot's `Armature_001`**, with
one constant local transform. That placement does two jobs: the vanilla
handler shows and hides the whole `PlayerN` slot, so the chair appears only
while its seat is taken (rule 3 holds with no script, as before), and moving a
sitter with `tools/lobby_preview/` carries its chair along.

| Slot | Chair (x, z, yaw) | Where |
|---|---|---|
| 5 | 2.20, −0.10, −15° | back, right of centre |
| 6 | −2.90, 2.90, +30° | between Player1 and Player2 |
| 7 | 5.20, 6.40, −55° | front right |
| 8 | −5.30, 7.10, +50° | front left |

The order alternates sides so five, six and seven players still look
balanced. Spots were chosen offline against the camera (all in frame, hips at
least 2.3 u from any other seat, wall clear by 1.2 u or more), then **looked at
in the running game on 2026-11-13**: the maintainer hosted a Steam lobby in the
`tools/lobby_preview/` build with all eight slots forced visible, and the
game's own frame showed every player on a chair of their own, every nametag
above its sitter, nobody on anybody, and P5's legs behind P3 from the camera
as the only overlap. Slots 5-8 have still never been filled by real joiners
(open item 3). The toppled chair at the front right (`chair_012`) is vanilla
set dressing and was left in place, next to P7. To move a seat, do it in the running game with
`tools/lobby_preview/` (Testing, "Placing the lobby previews") and paste the
printed lines; F10 (auto-place on a lap) no longer applies. Never re-run
`lobby_expand.py` on this scene, it would overwrite the seats.

### 7. Lobby roster (new file)
`modules/multiplayer_lobby/mod_player_name_list.gd` is the only file the mod
*adds* rather than replaces. It draws a text list of Steam names in the lobby's
top-left, attached to `lobby_handler.root` so it follows the lobby UI's
visibility. Both `lobby_scene.gd` and `multiplayer_menu.gd` `preload()` it and
call `attach()` in `_ready()` plus `refresh()` in `update_player_list()`.

Two things to preserve on update: it must have **no `class_name`** (the pck's
`global_script_class_cache.cfg` is not regenerated by the build, so a new global
class would not resolve), and its styling mirrors the lobby's `message` Label —
if the game restyles its UI, re-copy those `theme_override_*` values.

### 8. `-localtest` (testing aid, optional)
`bootstrap.gd` routes to the debug lobby, `network_manager.gd` stays on the ENet
backend, `multiplayer_menu.gd` tiles 8 windows and staggers joins,
`multiplayer_backend.gd` titles each window. `multiplayer_menu.gd` also honours
**`-original`**, which flips `GameManager.custom_game` back to `false` so the
default (non-custom) playlist branch is exercised — see "The debug lobby is a
*custom* game" in Testing. See Testing below.

### 9. The spawn-marker scenes (fifteen of them)
Every minigame ships exactly **four** evenly spaced spawn markers and the spawn
code does `spawn_positions[counter]`, so player 5 is an out-of-bounds crash.

Resampling eight markers across the span the original four covered was the
tool's *abandoned* first design, and its docstring says why it went: the four
markers are collinear in only 4 of the 15 scenes — the rest are facing rows,
rings, arcs and scattered stations, off a straight line by up to 26 world units
— so resampling laid players along diagonals through the level. What it actually
does:

- **The four originals are left byte-identical**, positions included. Verified by
  diffing vanilla against the overlay: `disco_dodge` keeps `(-2,0,-2) (2,0,-2)
  (2,0,2) (-2,0,2)` exactly.
- Each new marker is a **clone of an existing one displaced `OFFSET` (default
  1.2u) along that marker's own local X**, inheriting its full rotation. Sitting
  beside a known-good spawn facing the same way beats interpolating a position.
- It therefore **can** extend beyond the original span — `disco_dodge`'s
  `Marker3D2_MOD6` sits at x `3.2` where the outermost original is x `2`.

Any exported `Array[Node3D]` spawn list gets the new NodePaths appended (in
v1.0.6 that was `escalator_pit`, `smoke_break`, `exploding_collar_race`).

Targets live in `tools/spawn_targets.txt`.

### 10. Changes made after the first pass

These were all found by actually playing the game at 8 players, not by reading
code, and each is described in the pitfalls list below.

- `minigames/disco_dodge/disco_dodge.tscn` - `MultiplayerSpawner.spawn_limit`
  4 -> 8 on `Networked/PlayerSpawner`, kept as **defence-in-depth, not a proven
  fix**. A matched pair of 90s 8-player runs differing *only* in that value
  (deployed pck grepped to confirm the control really carried 4):

  | | log lines | ERROR lines | missing-synchroniser | `[DISCO8] spawned` |
  |---|---|---|---|---|
  | `spawn_limit = 8` | 847 | 212 | 0 | **8** |
  | `spawn_limit = 4` | 845 | 211 | 0 | **8** |

  All eight spawn and replicate at the cap either way. The earlier "proof" — a
  jump in client log volume — was confounded by the `blood_trail.gd` fix in the
  same session. Hypothesis for the null result: `spawn_limit` governs explicit
  `spawn()` calls, not the auto-replication of children added under `spawn_path`
  (how `spawn_players()` works here) — unmeasured. Godot documents it as a cap
  on spawns, so matching it to the player count stays. Stable Footing is
  verified the right way instead: `[DISCO8] spawned=8` with all eight nodes
  named, on the host and all seven clients. (`manufacture_gun.tscn` also ships
  `spawn_limit = 4`; Firearm Factory was uncapped 2026-08-07 and raises it at
  runtime by property write, so that scene stays out of the overlay — §22.)
- `minigames/exploding_collar_race/.../blood_trail.gd` - guards an empty
  `Curve3D`; fired ~380 errors per round at eight players.
- `minigames/green_pea/scripts/green_pea.gd` - **runtime** eight-seat layout
  (chairs repositioned + narrowed, camera pulled back), applied by RPC only when
  the roster exceeds four. The scene stays vanilla.
- `tools/green_pea_chairs.py` is **legacy** as a layout tool: baking chair
  *positions* into the .tscn breaks 4-player games, and `green_pea.gd`'s runtime
  path supersedes that. But note `green_pea.tscn` **does** legitimately carry
  four extra chair nodes (`chair player{left,right}_MOD3/4`), shipped
  `visible = false`. `_mod_chairs()` collects everything named `chair player*`
  and only positions and reveals them above four players, so 1-4 still sees the
  shipped four chairs untouched. Scene supplies the nodes; script owns the
  layout. Do not "clean up" those hidden nodes.
- `minigames/chisel_gauntlet_multiplayer/scripts/chisel_gauntlet.gd` -
  8 distinct `player_rotations`, conditional `shotgun_check_order`, and
  `zz_mod_add_stations_rpc()` which clones the console/desk/ring geometry for the
  added slots — ten named nodes, including **exactly** the four desk
  `StaticBody3D`s out of `Colliders`' six children. The other two (the room's
  concave collision mesh + WorldBoundary, and the centre CSG pillar) must never
  be cloned: until 2026-08-13 a clone-the-whole-container loop duplicated the
  room's collider rotated 45° every 5-8 player round (archived 2026-08-13
  session-log entry). The same RPC hides `MOD_HIDE_PROPS` — the two corner barrels the
  135° slot's character stood inside (0.44u/0.89u) — and disables their own
  `StaticBody3D`s; 1-4 keeps the shipped dressing. Trace summary:
  `cloned 10 single nodes, hid 2 props`.

  **Jumbotron HUD overlay (since 2026-08-16).** The four added seats face a
  corner of the jumbotron and read its CRTs at 53.6° (cardinals: 7°,
  head-on). Rather than clone screens (a 45° clone is buried in the pillar
  box and its neighbours — archived 2026-08-16 session-log entry), every
  player in a 5-8 lobby gets a full-screen HUD of the couch-mode
  `LocalMultiplayer/JumbotronViewport` — a SubViewport whose camera sits at
  seat 1's jumbotron pose — for as long as the local player's camera
  animation is `look at jumbotron*` (hooked on each player's
  `camera_animation_player.animation_started` via
  `player_spawn_node.child_entered_tree`; local player picked by
  `player_presence.network_id`). Roster gate: a flag latched inside
  `zz_mod_add_stations_rpc()`, so no new RPC and nothing at 1-4; the scene is
  untouched. While shown, `LocalMultiplayer` + its four cardinal `Lights` are
  made visible and the local seat light hidden (online, only the local
  player's own seat light lights the room, which made the render vary by
  seat and go black off-cardinal), and the overlay camera's `near` is set to
  2.0 (seat 1's tall third-person rig stands 0.77 u in front of it, head
  breaching the frame); on hide the viewport is frozen and both restored
  *before* the 0.5 s fade. No trace by design — verified by eye.
- `minigames/chisel_gauntlet_multiplayer/chisel_gauntlet.tscn` - four spectate
  markers (`Marker3D_MOD5`..`Marker3D4_MOD8`) added under
  `DeadLobby/SpectatePositions`, **transformless like the shipped four** -
  vanilla stacks every spectate camera at the parent's origin, and
  `spawn_players()` does `spectate_positions[counter]`, so a 5-8 roster needs
  indices 4-7 to exist (indexing past the end is pitfall 23's silent-null
  case). This path never shuffles, so 1-4 always lands on the shipped markers.
  Until 2026-08-13 the overlay carried seven clones wearing a Label3D's
  transform instead - players 5-8 spectated from knee height at the screen
  plane; see pitfall 31 and the archived 2026-08-13 session-log entry.
- `minigames/chisel_gauntlet_multiplayer/states/round_eliminate.gd` - `[SHOTGUN]`
  trace of the execution sweep under `-localtest`.

### 11. `minigames/intermission_new/components/intermission_score_screen.gd`

The end-of-minigame score screen showed only **four** players at eight, without
crashing: `reset_user_containers()` fills from a score-*sorted* list bounded by
`user_container_array.size()`, so the four lowest-placed players were silently
dropped off the bottom of the board. Worth remembering as a category - a
too-small array that is *filled from a sorted list* loses data quietly, where
one that is *indexed* by player crashes loudly.

Three things had to line up:

- `rank_y_positions` was a **`const`** with four entries, now a `var` recomputed
  per round. That matters because the array has a reader outside this file:
  `user_container_order_manager.switch_places()` indexes it by
  `user_rank_value - 1` during the rank-swap animation, so ranks 5-8 would have
  gone out of bounds there even after the board itself was widened. Making it a
  `var` fixes all four readers without touching that file.
- The scene wires exactly four rows (`users list/user info1`..`4`). Four more
  are cloned at runtime from `user_info.tscn`.
- Each `Intermission_UserContainer` builds its own `user_container_array` from
  `get_parent().get_children()` in `_ready()`, which would sweep up the spare
  rows. It is re-pinned to the active set every round.

**Also fixed here: a negative reverb pitch.** `lerp_total_score()` floors
`speaker_score_click.pitch_scale` at 0.1, then `set_final_label()` sets the
reverb speaker to `that - 0.2`, i.e. **-0.1**, and Godot rejects it with
`Condition "p_pitch_scale <= 0.0" is true`. Reaching the floor takes ~380
decrements of the score countdown, which only happens once the totals are large
enough - so it fired once per peer at eight players and never at four. Vanilla
code; found by the 4-vs-8 error-class diff, not by the mod breaking anything.
Now `maxf(..., 0.1)`, which is identity at <= 4.

Vanilla is preserved by `MOD_VANILLA_RANK_Y`: at <= 4 players the y array, the
row scale (1.0) and the container set are restored to exactly the shipped
values, and the spare rows are hidden and emptied. Confirmed by the `[SCORE8]`
trace reading `rows=4 scale=1.000 expanded=false`.

**One row per player above four** (since 2026-11-09; until then every 5-8
roster got the eight-row board, i.e. the smallest text for the lobbies that
needed it least, plus blank placeholder rows). The rows are resampled across the
span the four originals covered rather than extended downward (which would run
off the screen panel), so the row pitch shrinks by `3/(rows-1)` and
`_mod_row_scale()` scales the rows by the same ratio to keep the shipped
gap-to-row proportion: 0.75 at five players, 0.6 at six, 0.5 at seven, 3/7 at
eight. Clones the roster does not need stay parked - hidden, emptied and out of
`user_container_array`, so nothing sorts against them. The briefing screen
(section 12) deliberately keeps eight cards: its empty cards are the invite
buttons. `[SCORE8]` reads `players=5 rows=5 scale=0.750` on host and clients.

**No RPC is needed.** `setup()` is already invoked on every peer by
`intermission_manager.show_score_screen_rpc`, and the score dictionaries it
carries are identical everywhere, so the board is sized from
`_total_score_by_network_id.size()` and cannot desync. This is the exception to
the "runtime scene changes must be RPCs" rule below - the entry point was
already replicated.

### 12. `minigames/intermission_new/components/intermission_briefing_screen.gd`

The pre-minigame player cards, same four-row cap as section 11 but with more
state that has to grow together. Its `rank_y_positions` was already a `var`
(2D pixel offsets `[0, 19, 38, 57]`, four readers in this file). What made it
harder than the score screen:

- `sort_user_containers_by_score()` **assigns** `score_container_nodes[i]` by
  index rather than appending, so leaving that array at four while the card list
  grows is an out-of-bounds *write*, not a silent truncation.
- `speakers_show_player_card` is indexed per row in `show_score_nodes()` and
  `update_players()` - pitfall 23, and a hard crash at row 5. Wrapped modulo,
  which is identity at <= 4 rows.
- Each card dereferences `invite_visual_button` / `invite_interact_button` in
  its **own `_ready()`** via `hide_invite_button()`, with no null check, so a
  clone crashes on entering the tree unless both are assigned first. Each added
  row therefore clones a visual button and an overlay interact button too, and
  connects the Steam invite hook by hand (`setup_invite_buttons()` has already
  run by then).

The two invite buttons live in different coordinate spaces from the card - the
interact button is in the un-scaled screen overlay - so the card-y to
button-offset ratio is **learned from the shipped four** rather than hardcoded,
the way `green_pea_chairs.py` learns its marker->chair offset. That earned its
keep: the overlay buttons are not evenly spaced (`act_ratio=2.1754`, not the
2.53 the first two nodes suggest).

Rows cannot be extended downward here: `ready button parent` sits at
`offset_top` 149.5 in the same column and the four shipped rows already reach
~144. So the eight rows are resampled across the shipped span and scaled, which
lands on the same 3/7 ratio as the score screen.

### 13. `minigames/escalator_pit/scripts/escalator_pit.gd`

Vanilla has four escalator troughs. At eight players the added markers put
players 6-8 **1.2 units underneath** players 2-4 (see the pitfall below), so
they read as doubled up with their input arrows drawn on top of each other.

The fix splits each trough into **two narrower parallel stair strips** - eight
sets of stairs, one player each, with no art changes. That is only possible
because the stairs are procedural: `stair_handler.gd` iterates
`paths_parent.get_children()` with no hardcoded count, every lane shares one
`Curve3D`, and all four `MultiMeshInstance3D` nodes already share a **single
MultiMesh** - a lane differs from its neighbours purely by its `Path3D`
transform. Cloning one is therefore a `Path3D.duplicate()` at a new x. The four
CRT screens are separate sibling nodes and get the same inward/outward split.

Strips sit at trough centre +/- `MOD_STRIP_OFFSET` (1.6, against a 6.4 trough
pitch). `MOD_STRIP_SCALE` is **1.0** - do not "helpfully" narrow it. The step
mesh measures **2.44 x 0.66 x 1.08**, not the ~6 needed to fill a trough: the
steps always sat as a narrow band inside a much wider baked housing, so two of
them at the 3.2 strip pitch already clear each other by 0.76. An earlier
0.48 here shrank them to 1.17 and made the stairs look like slivers sunk into
the floor, which read as "the lanes haven't changed at all" because the wide
surface on screen is the housing, not the steps. The `[LANES8] lane` trace
prints `step_size` and the applied `mmi_scale` precisely so this is measured
rather than assumed.

`MOD_STEP_LIFT` and `MOD_PLAYER_LIFT` are both **0.0**: stairs and players sit
exactly where vanilla puts them, and only the *count* and lateral spacing are
modded. Steps that look embedded in the floor are the handrail assembly
crowding the lane, not a height problem - check what is crowding a lane before
adding an offset.

If they are re-tuned, both are applied as **node** offsets, never
per-instance: `stair_handler` rewrites every instance each frame as
`Transform3D(Basis(), position)`, so anything written there is erased on the
next tick. Players are safe to move this way because they ride a `PathFollow3D`
carried inside their own scene rather than physics - the root is teleported to
the marker and the whole path travels with it.

**Hidden art**, all gated on roster > 4 and all pure visibility toggles:

| Node | What it is | Why |
|---|---|---|
| `Plane_003` | the long diagonal handrails | players clip them at the 3.2 strip pitch |
| `Cylinder`,`Cylinder2`,`Cylinder3` | 0.89 x 1.76 posts on the trough boundaries | same |

**When a mesh must be identified, toggle it and look - name and listed position
both mislead here.** `Plane_003` is rotated 90 degrees about Z, so its
22.9-unit extent runs *across* the lanes and its position `(-9.6, 6.4, -11.4)`
reads as a single left-hand prop rather than something spanning the whole run;
and the theory that the rails were baked into `base platform` (`surfaces=1`,
single material `paint rusted1`, hence unremovable without the GLB) died in one
run - hiding it made the floor vanish and left the rails. `_mod_dump_all_meshes()`
prints every mesh with world position and size under `-localtest` for this.

`MOD_FLOOR_DROP` (0.75) sinks `base platform` slightly below its shipped
`y = -0.81` so the stairs read as resting on it, and it is deliberately a
**plain eyeballed offset**. Deriving it does not work: aligning the floor's AABB
top to the lowest point of the lane curve produced `y = -23`, because the lane
curve is a **closed loop** whose minimum is the return run passing ~21 units
*under* the escalator, and `base platform` is a 15.5-tall structure whose AABB
top (11.3) is the top of the housing. Neither quantity means "the bottom of the
stairs".

The **input arrow** is a `Sprite3D` at local `(0, 16.74, -13.84)` on the
player - far up and back, so it renders near the CRT bank, not over the
player's head. The monitor housing `Cube_009` sits at world
`(-0.13, 16.52, -14.67)`, barely behind it, so lifting the players pushed the
arrow *into* the housing and it vanished entirely. `MOD_INDICATOR_NUDGE` in
`escalator_pit_player.gd` is back to `Vector3.ZERO` now the lift is 0, but the
coupling stands: **raise `MOD_PLAYER_LIFT` and the arrows disappear behind the
monitors unless that nudge is re-tuned.**

Built in **`_enter_tree()`, not `_ready()`** - `StairHandler._ready()` caches
the path list, and `_ready` fires bottom-up, so by the time the minigame root is
ready the handler has already committed to four lanes. No RPC: every peer loads
the scene and `PlayerManager.player_presences` is replicated.

**What could not be done from script:** eight *full-width* lanes. The four
escalator housings and the pit floor are baked into one mesh
(`base platform`, `ArrayMesh_go7oh`), so lanes at the shipped 6.4 pitch would
span +/-22.4 against a platform ending near +/-13 and the outer ones would hang
off the level. That needs the GLB re-authored, and is why both strips stay
inside an existing trough.

### 14. Smoke Break — `smoke_break.gd`, `smoke_break_trolley.gd`,
### `smoke_break_player_anim_handler.gd`, `smoke_break.tscn`

Smoke Break seats players on a bench and a trolley-mounted revolver executes the
losers. **Four separate arrays were capped at four seats**, none of which
produced a log line - the static pre-check and a `[SMOKE8]` trace found them,
not a crash:

| Site | Cap | Effect at seats 4-7 |
|---|---|---|
| `rot_by_seat_index_array[seat]` | 4 | **the gun aimed at nothing and missed** |
| `particles_smoke[idx]` | 4 | one puff consumed per shot; eight shots overrun it |
| `blood_decals_by_seat_index_array[seat]` | 4 | out-of-range read mid-elimination |
| `match seat:` in the anim handler | cases 0-3 | `death_anim_active` stayed `""`, so `anim_player.play("")` ran and **eliminated players never fell** |

That last one is the pattern worth remembering: an unmatched `match` leaving an
empty string is not an error, so half the players were shot with no death
animation and nothing said so. The mod adds cases 4-7 **and** a `_` catch-all so
a missing case can never silently mean "no animation" again.

`particles_smoke` wraps modulo (identity at <= 4). Blood decals are deliberately
**skipped** for seats 4-7 rather than wrapped: each decal node is positioned on
its own bit of scenery, so wrapping would paint blood on the wrong seat.

**Seat layout.** Seats 0-3 are pinned - they are what a 1-4 player game uses.
The four added seats sit two beyond the ends of the bench arc and two in the
widest internal gaps, and each end seat gets a `crate1_003` clone to sit on.
Those clones live in the scene but ship `visible = false`;
`_mod_reveal_extra_seating()` shows them only above four players, the same
pattern green_pea uses. Verified: at 4 players the `[SMOKE8] seating` line is
absent entirely, so the crates stay hidden and the scene is vanilla.

**Aim angles are static, not computed.** `rot_by_seat_index_array` is scene data.
The four added angles were derived by interpolating position and angle *together*
along the bench arc, so they stay consistent by construction. Measured against
the runtime `[SMOKE8]` trace, the added seats' residuals (2.23, 2.00, 7.65, 9.28
deg) match the shipped seats' own (4.60, 1.50, 0.70, 9.10). **If a seat moves,
its angle must be re-derived** - they are coupled.

**Known limitation, accepted:** some player-model clipping remains on the left
four. Seats 1 and 2 are pinned 2.19 apart, so anything placed between them lands
at 1.094 either side. The right side is *tighter* (1.003) and does not clip - the
difference is facing, not distance: the left seats turn 45-60 deg inward so arms
swing along the bench. **The lever is facing, not spacing.** Pushing the seat out
of that gap instead puts it past the camera's +19.5 deg frame edge (below).

**Camera frame is the binding constraint.** fov is 22.5 vertical, so at 16:9 the
horizontal half-angle is **19.5 deg**. MOD5 already sits at 16.40. A seat pushed
to 3.0 beyond the left end measured 22.78 and was off-camera entirely. Check any
new seat against this before trusting a screenshot.

### 15. `minigames/junk_platform/scripts/junk_platform.gd`

**A platform per player above four** - a ring of six or eight platforms built
at runtime on every peer. Until 2026-11-09 this section read "diagnostic only":
the mod seated two players on each of the four shipped decks and called it
"fine because scoring is last-man-standing". It was not fine, and the reason is
in a file the mod never opened: `junk_handler.gd` drops one piece of debris per
**player spawn point** per tick (`for p in spawn_points.values()`), so a shared
deck took debris at **twice** the vanilla rate against the same collapse
threshold (`collapse_after = 3`, set in the platform sub-scene), and its two
players died together when it went. At five or seven players it was also
lopsided - one pair doubled up while the rest played the vanilla game. Reported
by players as "it doubles the debris, which breaks the game".

**What a platform is.** Four separate things tied together only by the
platform's exported references, which is why adding one is not a single clone:

| Part | Node | Notes |
|---|---|---|
| Logic + collider | `Platform1`-`4`, instances of `junk_platform_platform.tscn` at the scene root | `Area3D`; the deck you stand on is an invisible `CSGCylinder3D` inside it, radius 6.0, height 105.5 - a solid pillar, not a disc |
| Art | `visuals base/junk platform visuals2/platform main parentN` and `visuals base/damage indicators/damage indicator parentN` | pillar mesh, and eight concentric indicator rings lying on the deck |
| Press | `junk platform compactors/compactorN` | hangs at y ~26.8, slams to 1.355; carries the kill area and its own collider |
| Alarm | `speaker_indicator alarmN` at the scene root | positional audio |

**The flip.** Players on the far row (`position.z < 0`) get the camera *and*
`visuals base` turned 180 degrees, so the art that stands at their platform is
the art authored for the diagonally opposite one. That is what
`platform_visuals_flipped` / `damage_circle_parent_flipped` are for, and it
means **every platform needs a mirror partner through the origin**. The ring is
therefore built in mirror pairs, and a clone's flipped set is its partner's art.
Presses and platforms are not under `visuals base` and never turn
(`assign_flipped_compactor()` returns on its first line).

**The layout** (`zz_mod_build_ring_rpc`, sent by the host from `spawn_players()`
and run on every peer): the four shipped corners slide from 13 to
`MOD_RING_SPACING` = **15.5**, and the mid-edges are filled in mirror pairs -
`(-S, 0)` and `(S, 0)` for 5-6 players (six platforms), plus `(0, -S)` and
`(0, S)` for 7-8 (eight). The spare deck at five and seven players is just an
empty platform, as vanilla has with two or three. Why the corners move rather
than the extras squeezing in between them, all measured from the scene:

| Constraint | Number | Consequence |
|---|---|---|
| Deck radius 6.0, character capsule radius 0.7, **no jump** in this minigame (`junk_platform_player.gd` has gravity and `move_speed` only) | a gap under ~1.4u can be walked | at the shipped 13.0 a mid-edge deck would sit 1.0u from its neighbours - and a player who can step off a collapsing platform has no game left |
| Pillar art AABB: 6.68u deep on the far side, **8.62u on the camera side** | two rows need >= 15.3u between centres | 15.5 clears it by 0.2u |
| Press kill box 13.2 x 13.7, origin up to ~1u off the platform centre | reaches <= 8.8u from a centre | neighbour deck edge is at 9.5u |
| Camera at (0, 27.1, 30.7), pitched 49.8 degrees down, vertical FOV 50.3 | the frustum meets the deck plane at z = 23.4 | near row's front edge is z = 21.5; a ring any wider starts losing the near decks off the bottom of the screen |
| Support beams from the side walls end at x = +-18, z = -10.2, ~11u below the decks | - | the moved far corners still cover the beam ends; the side platforms' art stops 3.5u short of them |

World-space moves throughout (`_mod_shift_platform`, `_mod_clone_platform`):
`platform_visuals` always names the art currently standing at a platform on
this peer, so shifting or copying what it names is correct whether or not the
peer has flipped. The platform itself is **instantiated** from its scene, not
`duplicate()`d (pitfall 20); the press is `duplicate()`d and its four exported
node references (`visual`, `particle`, `area`, `speaker_slam`) are re-pointed at
its own children **before** `add_child()`, because `_ready()` connects the kill
area it finds there (pitfall 37 - an unrebound press slams, sparks and kills on
the platform it was copied from). `[PLATFORM] clone` prints `rebound=4/4`.

**Spawns and debris.** `_mod_ring_spawns()` rebuilds the host's spawn list from
the ring: slots 0-3 keep the shipped markers' order and move out with their
corner, 4-7 follow the mid-edges. The scene's four `_MOD` markers are no longer
read at any roster size (the `.tscn` is unchanged and still carries them).
`junk_handler.max_junk` rises from 40 to `MOD_JUNK_PER_PLAYER` (10) x roster:
the pool is a ceiling that a four-player round rarely reaches, but eight
streams exhaust 40 within seconds and then every stream starves.

**A collapsed platform clears itself away in a ring round.** Vanilla leaves the
press standing where it landed, a 23u-tall block. With four corners that is
harmless because the camera looks down the open middle of the level; in the
ring the near-middle press stands between the camera and the far-middle
platform and hides whoever is alive on it, and a near-corner press covers half
of the side platform behind it - **reported from the first 8-player run, and
invisible to every trace** (pitfall 39). So `_mod_clear_collapsed_platform()`
waits `MOD_PRESS_HOLD` (1.0 s), lifts the press back to the height recorded
before it moved, drops the platform's art 70u into the pit and hides it,
disables the pillar collider (found by type, pitfall 38) and wakes the debris
resting on it so it falls to the catcher and returns to the pool. It hangs off
`visibility_changed`: `collapse_rpc()` hides the platform on every peer and
nothing else ever does, so that signal is "this platform just died" without
adding the platform script to the overlay.

**Rule 3.** Everything above is behind `player_count > 4` on the host and
reaches clients only through the RPC, which is never sent at four or fewer; the
`.tscn` is untouched. At four players `[PLATFORM]` shows no `ring` line and the
shipped `Marker3D`-`Marker3D4` at +-13.

**Verified 2026-11-09 by trace** on host and every client - 8 players: `ring
asked=8 platforms=8 cloned=4`, each of eight players `ON_DECK dist=0.00` on a
distinct platform, three rounds, `cleared` 24 times per peer with
`colliders=1`; 5 players: `asked=6 platforms=6 cloned=2`; 4 players: no ring,
shipped markers. **Placement and the self-clearing collapse were watched in the
8-window harness and confirmed by eye the same day** - the far-middle player
stays visible once the near-middle press has lifted - **but neither has been
played by a full lobby.** The evidence tables are in the 2026-11-09
session-log entry.

### 16. `train_race.gd`, `spine_breaker.gd`, `dvd_roomba.gd`

`[TRAIN8]`, `[SPINE8]`, `[ROOMBA8]`. **`train_race.gd` and `dvd_roomba.gd` are
diagnostic only** - no gameplay change at any roster size; `spine_breaker.gd`
was too until 2026-08-02, when its kill pace was scaled to the roster (**section
18**). This section covers only the spawn audit. None of the three needed a
*capacity* fix - nothing beyond the expanded spawn markers - and *why* is worth
recording, so a future session does not go looking for a cap that is not there:

| Minigame | Why it already scales |
|---|---|
| Tunnel Hazard | the level ships **8** nooks; `nooks_to_open` is computed, not a constant |
| Spine Breaker | the device picks its victim with `active_players.values().pick_random()` |
| Lethal Rebound | roombas spawn on a timer up to `max_roomba_count`; nothing is per-player |

Not needing a capacity fix is not the same as playing *well* at eight - Spine
Breaker scaled correctly and still ran 2.5x too long, which is section 18.

Each trace carries a **landing audit**: 6s after the scene is ready, on every
peer, each player's distance to its nearest spawn marker with an
`OK`/`DISPLACED`/`FELL_THROUGH`/`DEAD_OR_HIDDEN` verdict. It exists because
`spawn_expand.py` puts the added markers **1.2u outboard** of the shipped ones
(Lethal Rebound's MOD6 lands at x=6.2 against a shipped extreme of 5.0), so a
clone inside a wall is a live risk that produces no error - physics just shoves
the player clear. Worst case across all four on **v1.0.7**: **0.57u**, nothing
displaced. Re-measured on v1.5.0 / Godot 4.5.2 (2026-08-05): **192/192 `OK`
across eight peers, worst 0.49u**.

**That clean result is the point, because Tunnel Hazard was visibly broken at
eight anyway** — a 2026-08-05 screenshot showed four shoulder-to-shoulder *pairs*
with the top-right player inside the right-hand wall, while the audit correctly
reported `OK` for every one: each player *was* on its marker. **The landing audit
validates the spawn *mechanism*, not the level design.** `DISPLACED` fires when
physics *rejects* a placement; one physics happily accepts, flush inside a wall
the player never has to leave, produces no verdict at all.

**Fixed 2026-08-05** by `spawn_expand.py`'s `inward` mode (opt-in, third field in
`spawn_targets.txt`). The expander had been generating both `±offset` candidates
all along but ranking them by `(source-usage, step)` alone, so the two signs tied
and the stable sort always chose `+`; `inward` breaks the tie toward the centroid
of the shipped markers:

| clone | before | after |
|---|---|---|
| `Marker3D2_MOD6` | x=+4.619 (in wall) | **x=+2.219** |
| `Marker3D4_MOD8` | x=+5.311 (in wall) | **x=+2.911** |
| `Marker3D_MOD5` / `Marker3D3_MOD7` | x=−2.750 / −2.770 | unchanged |

Worst physics push-out fell 0.49u → 0.20u. Verdicts were `192/192 OK` both before
and after, so **the audit neither found this nor confirms the fix** — a
screenshot-verified change, and that is the honest label. The other narrow levels
have never been checked by eye for the wall case either. Still open and
level-agnostic: `OFFSET`=1.2u against a ~1.6u-wide character, so every expanded
pair starts interpenetrating — Open item 0 in `UPDATING.md` owns that.

`DEAD_OR_HIDDEN` is keyed off `visible`, which `kill_rpc()` clears on every
peer. Without it the audit reported a bogus `DISPLACED` whenever it landed
after the first casualties - which it does in Tunnel Hazard, where idle test
instances are run over by the first train.

**Lethal Rebound's `max_roomba_count` is an `@export` whose script default of 5
is overridden to 10 by the scene.** Read the trace's `max_roombas=` field, not
the script. It is deliberately left alone: it is not per-player, so raising it
would change the 1-4 player game too.

### 17. Inside Job — `knife_at_the_office.gd`, `countdown_handler.gd`

Two real bugs, neither of which produced a single log line. Both were found by
reading the code, not by running it.

**The search economy could make the round unwinnable.**
`guaranteed_search_result` is the running total of container searches after
which the syringe turns up. Vanilla computes it as

```gdscript
var searchable_count: int = 26
var player_ratio: float = PlayerManager.player_presences.size() / float(4)
var searchable_base: int = round(searchable_count * player_ratio)
guaranteed_search_result = searchable_base - round((searchable_base * 0.5) * randf())
```

A container can only be searched **once** (`searchable.searched` is set true and
never reset), so the number of containers in the level is a hard ceiling on that
total. The office holds **36** (26 `cabinet_single_dynamic` + 3
`drawer_desk_dynamic` x 2 + 4 placed directly). At four players the target lands
in `[13, 26]` - always reachable. At eight it is `[26, 52]`, and **any roll above
36 means the syringe is never found**: the hunting phase never starts, no timer
is ever armed, and the round runs forever. It starts to bite at **six** players.

The mod counts the searchables at runtime and clamps the target to
`total - MOD_SEARCH_MARGIN`. Clamped rather than rescaled, so the developers'
intent (more players => proportionally more searches, so the search phase lasts
the same wall-clock time) survives wherever it is satisfiable. Counted rather
than hardcoded so an art pass cannot silently reintroduce the stall. Host-only
and correctly so: `guaranteed_search_result` is read only inside
`request_item_find_rpc`, which returns early on non-servers.

Proven at runtime by the `[KATO8] search` line:

```
roster=8 markers=8 searchables=36 base=52 target=34 clamped=true    # 8 players
roster=4 markers=8 searchables=36 base=26 target=17 clamped=false   # 4 players
```

**The hunt HUD only ever showed four survivors.**
`alive_indicator_icons` is wired to exactly four `TextureRect`s, and both
`setup_alive_indicator()` and `update_alive_indicator_rpc()` walk it with
`for i in num_of_alive_players` - called with `active_players.size() - 1`, i.e.
**7** at eight players. `_mod_ensure_indicator_capacity()` clones the template
icon up to the number needed. `duplicate()` is safe here (bare `TextureRect`s
with only a `texture`, no `node_paths` - pitfall 20 does not apply), and it is
a no-op at four players or fewer, so a 1-4 game has the shipped four nodes and
nothing else. Verified `needed=7 icons=7` on the host **and all seven clients**,
and absent entirely at four players.

**Severity: the HUD undercount is cosmetic** — the round is unaffected, only
the survivor icons are. The search-target clamp above is the real bug.

**Two `-localtest` test aids**, both inert in a shipped build:

| Flag | What it does |
|---|---|
| `-kato-target=N` | overrides the search target so one driven window can trigger the hunt |
| `-kato-hunt=N` | host enters the hunting phase N seconds into the round, through the real `_on_item_found` entry point |

`-kato-hunt` earns its keep: unattended instances never search a container, so
without it the entire second half of this minigame - and the bug that lived
there - is unreachable in a localtest run.

```bash
ARGS="-kato-hunt=8" START=1 MINIGAME=KnifeAtTheOffice tools/localtest.sh 8 \
  testgame 130
```

### 18. Spine Breaker kill pace — `spine_breaker.gd`

**The mod's first gameplay *tuning* change** (2026-08-02, on request).
Everything else in this file is a capacity fix - making eight players fit where
four did. This one deliberately alters how the minigame plays above four.

The problem is arithmetic, not feel. The per-kill cycle is fixed:

```
fuse (activation_duration) + kill animation (1.0s) + dead time (3.0s) = ~24s
```

and the number of kills needed scales with the lobby. Three kills at four
players is ~72s; **seven kills at eight players is ~168s**, measured at ~190s
wall-clock with per-round overhead.

**Two mechanics facts the design rests on, both non-obvious:**

1. **The fuse is never restarted by a throw.** `try_throw_rpc` in
   `spine_breaker_device.gd` does not touch `activation_timer`, and
   `attached_state.gd` reads `timed_out = owner.activation_timer.is_stopped()`
   on entry - so once the fuse burns out mid-chase, the *next* attach kills
   instantly. `activation_duration` is therefore a hard cap on
   time-from-arming-to-death, which is what makes the cycle scalable at all.
2. **Travel happens inside the fuse window.** `choose_new_target()` transitions
   the device to `Follow` and calls `start_timer()` on the same frame, so
   **raising the spider's chase speed would not shorten a round** - it would
   only spend more of the fuse attached. `new_target_speed`, `default_speed` and
   the `speed_increase_*` ramp are left alone deliberately: speeding up the
   spider is not a pacing lever, and that is the trap to avoid.

**The scaling.** `factor = MOD_VANILLA_KILLS / (roster - 1)`, clamped to 1.0,
applied to the fuse and the dead time:

| roster | kills | factor | fuse | dead | round |
|---|---|---|---|---|---|
| 1-4 | 3 | 1.000 | 20.000 | 3.000 | ~72s (vanilla) |
| 5 | 4 | 0.750 | 15.000 | 2.250 | ~73s |
| 6 | 5 | 0.600 | 12.000 | 1.800 | ~74s |
| 7 | 6 | 0.500 | 10.000 | 1.500 | ~75s |
| 8 | 7 | 0.429 | 8.571 | 1.286 | ~76s |

At four players the expression is exactly `3/3 = 1.0`, so **1-4 is vanilla by
construction rather than by an `if`** - `20.0 * 1.0` and `3.0 * 1.0` are
bit-identical to the shipped values. Below four it clamps.

It keys off `player_count` (set once in `spawn_players()`), **not**
`active_players.size()`, which shrinks as players die - that would make the
fuse *lengthen* as the round progressed and would drift out of vanilla at four
players after the first death. The `[SPINE8] pace` trace prints both so the
distinction is visible: `roster=4 active=2 factor=1.000`.

**The shipped fuse is learned, not hardcoded.** `activation_duration` is an
`@export` whose script default (15.0) is overridden *twice* - to 10.0 in
`spine_breaker_device.tscn`, then to **20.0** by the `Device` instance in
`spine_breaker.tscn`. `_ready()` snapshots the live value into
`_mod_vanilla_fuse` before anything mutates it, and `choose_new_target()`
assigns `_mod_vanilla_fuse * factor`. Multiplying the *current* value would
compound on every kill; hardcoding 20.0 would silently ignore a developer
retuning that scene value on a future update. Same learn-from-shipped-data
pattern as `green_pea_chairs.py` and the briefing screen's button ratios.
The trace prints `vanilla_fuse=` so a bad capture is visible immediately.

**Assign the member, not the timer.** `device.activation_duration = ...` rather
than `activation_timer.start(x)`, because `spine_breaker_device.gd`'s `_process`
divides by that same member to drive the warning light's blink ramp - setting
the member keeps the light in step with the real fuse for free.

**No RPC, and none is wanted.** Both changed sites are host-only:
`device.request_new_target` is connected inside an `is_server()` guard, and
`choose_new_target()` is otherwise only reached from `_on_countdown_expired`
under the same guard. The device sets `set_process(false)` /
`set_physics_process(false)` on clients and its state machine is pinned to the
inert `Empty` state there; client visuals come from the
`SceneReplicationConfig` plus `call_local` RPCs. Verified: all 8 peers logged
the same 3 round advances.

**The 1.0s kill sequence is deliberately untouched.** It lives in
`spine_breaker_player.gd`'s `break_spine_rpc`, whose two `create_timer` waits
run independently on *every* peer - shortening it host-side would desync the
corpse drop, and it is the only part of the chain that would need a new overlay
file.

**Measured, 280s at 8 players:** 11 kills / 2 rounds before -> **21 kills / 3
rounds** after, i.e. three complete 7-elimination rounds. Per-round wall clock
~190s -> ~93s. (The ~93s exceeds the ~76s of kill-cycle above because of fixed
per-round overhead - countdown, fades, briefing, end-of-round waits - which no
amount of pace tuning removes.)

### 19. Duck Hunt — `duck_hunt.gd`, `hunter_player.gd`, `globals.gd`

Uncapped 2026-08-02 on request. **The cap rested on a wrong premise.**
The mode is **1 hunter + (N-1) ducks**, not "3 duck slots + 1 hunter": the hunter
is popped from a shuffled `possible_hunters` pool and every remaining player is a
duck, so the duck count always scaled by itself. Ducks are human-controlled
runners, not AI on paths, so nothing needed new behaviour. The "3" was only the
number of spawn markers.

**The one fatal blocker** was those markers. The scene ships exactly three under
`Networked/DuckPlayerSpawner/DuckPlayerSpawnPositions` and `spawn_players()`
reads `spawn_positions[counter]`. At five players `counter` hits 3, the read runs
off the end, and the host's spawn loop aborts *before the hunter is created* —
Forklift Certified's black-screen failure. The tell is that `set_hunter_rpc`
never fires.

**Markers are created at runtime, host-only, gated on roster > 4** — never in the
`.tscn`. That gating matters more here than elsewhere: the marker list is
`shuffle()`d, so baking extras into the scene would let a 4-player game seat
ducks on modded positions, which is exactly the deviation documented under
"The second sanctioned exception" in `UPDATING.md`. Creating them only above
four means Duck Hunt **sidesteps that deviation entirely** — at 1-4 the shipped
three are the only markers that exist. Host-only suffices because clients never
see a marker, only the position it resolves to via `teleport_rpc`.

Placement keeps the shipped three exactly (x = -5, 0, +5 at z = 104) and
interleaves up to four more at **half the shipped spacing**, alternating outward:
x = ±2.5 then ±7.5. All seven sit on the same z so every duck runs the same
134-unit course — a staggered second row would hand the front row a real head
start. The span stays inside **±11.75**, the half-width of the `FinishArea` box
(`23.5 x 7 x 5.5`), which is provably traversable because every duck must pass
through it. Spacing and depth are **learned from the shipped markers** at
runtime, not hardcoded.

**Magazine curve extended** (`hunter_player.gd`). `duck_count` is roster minus
the hunter, so vanilla only ever needed keys 0-3; above that
`.get(duck_count, 7)` fell back to **seven** shells and a 0.95 cycle — fewer
rounds and a slower bolt than the hunter gets against *three* ducks. The curve
inverted exactly where the pressure went up. Added keys continue the shipped
slope (+2 shells per duck) rather than inventing one:

| ducks | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| magazine | 7 | 8 | 10 | 12 | 14 | 16 | 18 |
| cycle | 0.95 | 0.90 | 0.80 | 0.70 | 0.60 | 0.50 | 0.45 |

Keys 0-3 are byte-identical to vanilla. **`hunter_player.tscn` does not override
either dictionary**, so the script defaults are live — re-check that after an
update. No plumbing was needed: `setup_rpc(position, duck_count)` already carries
the count to every peer and `set_active_rpc` recomputes capacity from it.

**Round pacing.** Every player hunts exactly once (`possible_hunters` is popped
without replacement and never refilled), so the *internal* round count IS the
roster, multiplied by `MinigameRoundsByPlayerCount`. That dictionary stopped at
`4: 2`, so 5-8 fell back to 2 and eight players would have run **sixteen** hunter
turns. Keys `5-8: 1` keep eight players at 8 turns — the same total vanilla
already runs at 4 (4 hunters × 2).

**Two pre-existing vanilla bugs fixed** in `duck_hunt.gd`, both likelier with a
bigger roster: `remove_player_rpc` decremented `duck_player_count` when the
**hunter** left (it was never counted as a duck, and that count feeds the
magazine size), and `_on_player_died` dereferenced `hunter_player.player_presence`
unguarded after the same path had nulled it.

**`duck_hunt_local_handler.gd` is no longer in the overlay.** Its delta added
keys 5-8 to a roster-indexed `Layouts` dict that `duck_hunt.gd` reached
**unconditionally** at the end of `spawn_players()` — not only in couch mode —
so a missing key errored even online. Upstream v2.1.2 deleted that dict for a
roster-independent two-pane `setup()`, the re-derived file came out
byte-identical to vanilla, and it left the overlay on 2026-08-14. Do not re-add
it.

**Verified:** at 8 players `markers=7 added=4` all inside the gate,
`ducks=7 magazine=18 cycle=0.45` on the host **and clients**, reached `Play`,
zero script errors on all eight instances, and `[DUCK8] spawned` reporting
`ducks=7 hunters=1` on every peer. At 4 players `markers=3 added=0`,
`magazine=10 cycle=0.80` and `ducks=3 hunters=1` — bit-identical to vanilla.

**The shortened cycle outran the rifle animations** (fixed 2026-08-02, second
pass). `shoot()` waits 0.5s, plays the bolt, waits `cycle_time`, then re-enables
firing — but nothing else touches `anim_rig` at the moment of a shot (the recoil
is a tween on `recoil_progress`, not an animation), so the bolt keeps playing
until the *next* `anim_rig.play()`, one more 0.5s after the next shot. **The
window is `cycle_time + 0.5`, not `cycle_time`** — and that extra half second is
exactly why the shipped duck counts look right and the added ones did not:

| ducks | cycle | window | speed needed | |
|---|---|---|---|---|
| 0-2 | 0.95 | 1.45 | 0.839 | fits — shipped |
| 3 | 0.80 | 1.30 | 0.936 | fits — shipped |
| 4 | 0.70 | 1.20 | 1.014 | clipped — mod |
| 5 | 0.60 | 1.10 | 1.106 | clipped — mod |
| 6 | 0.50 | 1.00 | 1.217 | clipped — mod |
| 7 | 0.45 | 0.95 | **1.281** | clipped — mod |

`_mod_play_to_fit(name, window)` passes a custom speed to
`anim_rig.play(name, -1, speed)`, raising it **only** when the animation does not
fit. Every shipped duck count needs ≤ 1.0, so at four players or fewer the call
is `play(name, -1, 1.0)` — identical to vanilla's bare `play(name)`. **1-4
parity holds by construction; there is no roster check and none is needed**, the
same property as the Spine Breaker pace factor.

The length is read at runtime via `anim_rig.get_animation(name).length`, not
hardcoded, so a retimed animation on a future update corrects itself. The reload
had the same defect, milder — a 4.0167s animation against a 3.80s window at
seven ducks (1.057x) — and gets the same treatment; vanilla's `3.8 - 0.95`
subtracts the *fallback* cycle time, so it drifts as soon as the real cycle
differs.

**`MOD_POST_SHOT_DELAY` is coupled to a bare `0.5` literal in `shoot()`** that
cannot be derived. If a game update retimes that wait, change the constant to
match or every window is computed against the wrong figure. The `[DUCK8]` trace
prints `bolt_window` and `bolt_speed` so a divergence is visible rather than
silent.

Verified: `bolt_speed=1.000` at four players (parity gate) and `1.281` at eight,
on host and clients, zero script errors. The engine reported
`bolt_len=1.2167`, matching the offline measurement below exactly.

**Round pacing — verified 2026-08-03, and it needed two more fixes.**

The original change (adding `5-8: 1` to `MinigameRoundsByPlayerCount`) was not
sufficient on its own. Two things were wrong with it:

1. **There are TWO sites that resolve `total_rounds`, and only one was in the
   overlay.** `game.gd` resolves it when loading the *next* minigame, but
   `scripts/scenes/game/states/minigame_playing_state.gd` resolves it again to
   compute `more_rounds`, and **that** is what actually gates the replay.
   Changing only `game.gd` would have left the displayed total and the real one
   disagreeing. `minigame_playing_state.gd` is now in the overlay for this.
   (A third site, `local_game.gd`, is couch mode and out of scope.)
2. **Vanilla gates the lookup on `if not GameManager.custom_game`**, so a custom
   lobby never received it at all. Both sites now read
   `if not GameManager.custom_game or player_count > 4`. The `player_count > 4`
   half is what preserves rule 3: a 1-4 custom lobby keeps exactly the round
   count its host configured in the playlist UI rather than having it silently
   overridden.

Measured with the `[ROUNDS8]` trace, all four cases:

| players | mode | rounds | |
|---|---|---|---|
| 8 | Original | **1** | 8 hunter turns, not 16 |
| 4 | Original | **2** | vanilla, unchanged |
| 8 | custom | **1** | the relaxation working |
| 4 | custom | **2** | host's count NOT overridden |

**This measurement cannot be taken under `START=1`.** See "`START=1` hardcodes
Duck Hunt's round count" in Testing — the shortcut path passes a literal 3.

**Duck-node count — verified 2026-08-03.** `[DUCK8] spawned` reports, per peer,
the duck nodes that actually exist plus the hunter, named, with an
`expected_ducks` cross-check that `push_warning`s on any mismatch. Measured
`ducks=7 hunters=1` on the host **and all seven clients** at eight players, and
`ducks=3 hunters=1` on all four at four — replacing an earlier position where
seven ducks rested on a visual check and the automated evidence was
absence-of-errors, the proxy this file warns against everywhere else.

**The `debug_skip_brief` reveal-skip repair — 2026-08-05.** Under `START=1`
(`Globals.debug_skip_brief`) the skipped `RoleReveal` state was the **only**
online caller of `set_can_aim_rpc(true)`, and `can_aim` defaults to `false` — so
the hunter could never fire, no duck could die, and the minigame hung.
`_mod_apply_skipped_reveal()` in `duck_hunt.gd` re-does what the skipped state
did: `set_can_aim_rpc.rpc(true)` plus `zz_mod_clear_role_overlay_rpc()`, which
clears the role overlay on every peer. It is gated on `Globals.debug_skip_brief`
and called from the end of `spawn_players()`, which `reset_state.gd` re-runs per
hunter turn, so every hunter is covered rather than only the first. Verified
`overlay_visible=false alpha=0.00` on the host **and all seven clients**. Even
with the fix Duck Hunt cannot complete unattended — idle instances never shoot
or finish. The full mechanism and the lesson live in `UPDATING.md`, Testing,
under "`START=1` HANGS Duck Hunt permanently"; this is a pointer, not a copy.

**Third vanilla bug fixed — 2026-08-15: a peer dropping during the load.**
Pitfall 32 owns the mechanism (vanilla's load gate is re-evaluated only on
arrivals; Duck Hunt's `player_disconnected()` → `check_game_end()` then starts
the round via `Reset` with `initialize()` skipped — silent `MINIGAME_SFX` bus
and a black screen at the end, issues #10 and #12). Two hunks, **applied at
every roster size** by the maintainer's decision, same precedent as the two
fixes above:

- `game.gd::_on_peer_disconnected` (host): while the current minigame has not
  started (`is_all_player_loaded` false — set by every minigame's
  `all_players_loaded()` before it emits `minigame_ready`), erase the dead peer
  from `minigame.players_loaded` and re-run the gate with `>=`, calling
  `all_players_loaded()` when it passes. Placed **before**
  `minigame.player_disconnected()` so `spawn_players()`'s 1 s timer is created
  ahead of `check_game_end()`'s; `is_instance_valid(minigame)` because
  `load_minigame()` holds the `queue_free`d previous instance for a second.
  Generic — it repairs the gate for all 20 minigames, not only this one.
- `duck_hunt.gd::player_disconnected`: `if not is_all_player_loaded: return`
  after `remove_player_rpc.rpc()` (the dead peer still leaves
  `possible_hunters`). Before the first spawn there is nothing to end, and the
  `Reset` side door would otherwise race the real start into a double spawn.

Verified 2026-08-15 with the kill-at-load recipe (Testing): at 4 the maintainer
played a P4-killed run to `Play → Finished → Game: MinigamePlaying →
MinigameEnd` and the score screen on all three peers; at 8 the same kill gave
`SessionIntro → MinigameStart → MinigamePlaying`, `Empty → Round` and
`markers roster=7 ducks_needed=6 added=3` on host and clients; no-kill controls
at 4 and 8 unchanged. Evidence in the archived 2026-08-15 session-log entry.
**The same guard went into the other fourteen handlers later that day** — a peer
that *quits* during a load reaches them pre-spawn (§23, pitfall 33).

### 20. Forklift Certified — `forklift_certified.gd`, `crate_manager.gd`

Uncapped 2026-08-04. **Three separate blockers, only one of which was known.**
No `.tscn` is touched; everything is runtime and gated on the roster exceeding
four, so a 1-4 game runs the shipped code on the shipped scene.

**The yard is much emptier than the cap claimed.** Measured off the scene:

| | |
|---|---|
| Floor (`Placeholder/CSGBox3D main collider`, inverted) | 53.57 x 58.57 |
| Other static colliders in the level | **none** - shelves and pipes are visual-only |
| Zone footprint (`BoxShape3D`, shared by all four) | 14.42 x 13.02 |
| Four zones as a share of the floor | **24%** |
| Free channel between the zone columns | 16.66 wide |
| Free band between the zone rows | 18.29 deep |

The four zones sit at the corners of a 3x3 grid with the middle row and column
empty, so the added four go at the **mid-edges**, making a ring with a free
centre cell. Positions are the midpoints of the shipped grid, not literals.

**Blocker 1 - the index (known).** `spawn_players()` builds `shuffled_indicies`
from `player_spawn_positions_node.get_child_count()` and uses it to index *both*
the markers and `delivery_areas`. Pitfall 13 exactly: at player 5 it runs off a
4-entry array and the host's spawn loop aborts before any state transition, so
the minigame loads to a black screen with the ambience looping.

Zones and markers must therefore grow **together and in the same order**, built
differently on purpose:

- **Zones go out as `zz_mod_add_delivery_areas_rpc()`** (`authority`, `call_local`,
  `reliable`). They sit outside any `MultiplayerSpawner` and the game drives them
  with `set_owner_rpc` / `update_counter_rpc` / `set_indicator_light_rpc`, all
  resolving **by node path** - a host-local clone is an RPC into thin air on seven
  clients. Reliable RPCs are ordered, so the `set_owner_rpc` calls
  `spawn_players()` sends immediately afterwards land with the nodes already
  built. Same guarantee `zz_mod_add_stations_rpc()` leans on in Chisel.
- **Markers are host-only.** `setup_rpc()` carries the resolved position and
  rotation, so clients never need one — which also keeps them out of the shuffled
  marker list a 1-4 game walks. Forklift sidesteps the "The second sanctioned
  exception" deviation (`UPDATING.md`) entirely, as Duck Hunt does.

**Two things about `duplicate()` here, both silent if missed.**

1. It is called with **`DUPLICATE_GROUPS | DUPLICATE_SCRIPTS` (6), not the
   default 7**. Signals must be dropped: each zone connects its own
   `body_entered`/`body_exited` in *its* `_ready()`, which runs again on the
   clone when it enters the tree, and on the host the shipped zones also carry a
   `crate_number_changed` connection made in the minigame's `_ready()`. Copying
   those would count every crate twice.
2. Every `@export` node reference must be **rebound to the clone's own
   children** before `add_child()`, or the clone drives the template's border,
   counter, light and speaker. Missed on the first pass; nothing measurable was
   wrong and only a screenshot caught it. Pitfall 37.

The server's `delivery_areas` array is built in `_ready()` from the children that
existed then, so clones are appended by hand and their `crate_number_changed`
wired (guarded with `is_connected`). A zone missing from that array never lights
up and never grants its achievement.

**Blocker 2 - `spawn_crates()` never terminates above five players.** It loops

```gdscript
while points.size() < target_size:
    points = PoissonDiscSampling.generate_points_for_polygon(polygon, spawn_radius, 20, Vector2.ZERO)
```

with no bound, asking for `roster * 2` points in a fixed 12x12 box. **The scene
overrides `spawn_radius = 4.0`** — the 6.0 in `crate_manager.gd` is dead, the
same "scene overrides the script" trap as `[ROOMBA8]`'s `max_roombas`.
Reimplementing the shipped sampler and running it 100,000 times per case:

| players | crates wanted | sampler succeeds | cost |
|---|---|---|---|
| 4 | 8 | 49% | ~2 calls - why vanilla works |
| 5 | 10 | 0.6% | ~160 calls, a visible hitch |
| 6 | 12 | **0 in 100,000** (max ever 11) | **never terminates** |
| 8 | 16 | **0 in 100,000** | **never terminates** |

A host freeze inside a `while`, with no error line — considerably nastier than
the black screen, and invisible until blocker 1 is fixed. Two changes:

- The polygon becomes the **free centre cell**, derived at runtime from the zone
  colliders (inner edges of the zones either side of the middle) and inset by
  **2.122** — the half-diagonal of a 3x3 crate, which is spawned with a random Y
  rotation. Anything less and a crate spawns already inside a zone and scores for
  its owner for free. Result: `x[-6.22,6.16] z[-10.50,3.55]`, and note it is
  centred ~3.5u off the `ItemSpawnPosition` the shipped box is built around.
- `target_size` is clamped to **10, the ceiling the shipped loop already
  enforced** via `if counter >= 10: return`. A 16-crate request was never going
  to produce more than 10 crates — it only made the sampler chase an
  unreachable target. Ten in the widened cell lands in 1-8 calls, which also
  fixes the five-player hitch.

`MOD_MAX_SAMPLER_ATTEMPTS = 200` bounds the loop regardless. At four players
tripping it would take `0.51^200`, so 1-4 is untouched in behaviour as well as
in numbers.

**Blocker 3 - the blood decal pool, vanilla, reachable only by a 5th
elimination.** `spawn_blood_rpc()` does
`blood_decals_environment_parent.get_child(0)` and moves that decal out of the
parent **permanently**. The scene ships **four**, and four players can only
produce three eliminations, so vanilla never empties it; eight produce seven.
The fifth ran `get_child(0)` against an empty node, returning null and aborting
the caller *mid-loop* — `remove_zero_scoring_players()` never finished,
`round_finished()` never reached `check_game_end()`, and **the round hung on
every peer** with one engine ERROR and nothing else in the log; one client
segfaulted. The pool now refills by duplicating a decal already on the floor,
keeping all seven visible; at <= 4 players the branch is unreachable, so parity
holds by construction rather than by an `if`.

**Fitting the added zones' art — all of it found by looking, none by a trace.**
The zone plates are positioned for a bay **recessed into the floor art**, and
the mid-edges have no bay. All of this was invisible to the logs because the
recess is art only: the level's single collider is the flat CSG box, so as far
as the game is concerned the floor is level everywhere.

| Symptom on screen | Cause | Fix |
|---|---|---|
| Added zones rendered as bare floor | the red plate sits at local y `-0.221` and the readout at `-0.255`, i.e. below the drivable plane; at a corner the recess is deeper than that, at a mid-edge it is not | both lifted to `floor_y + 0.03`, with `floor_y` read off a shipped spawn marker |
| Red bars poking through the grating beside the top two score boxes | same burial - the plate showed only through the slots in the floor art | as above |
| Red overlapping the top two score boxes | the far row's readouts jut ~2.4u past their own zones into the mid band, and an unshifted side zone's plate reached into them | side zones shifted +z clear of them, distance computed from the actual readout geometry each run |
| Added plates read as oversized slabs | vanilla's red is mostly hidden *under* the bay art; with no bay the whole plate shows | `MOD_BORDER_SHRINK = 0.9`, **visual only** - the Area3D that detects crates stays at the shipped size |
| No grey grid plate inside the square | the bay plate is painted into `main floor_001`, not a node under the zone | faked - see below |
| Side readouts in the wrong place | cloned from a far-row template, so they pointed along z where neither direction is free | moved into the margin against the side wall, a quarter turn so the 4.6u housing fits a ~4.3u margin |

**Faking the bay plate.** The obvious workarounds look right and are not: the
zone's own `SpotLight3D.light_projector` is `knife_at_the_office/light_01.png`,
a generic cookie, **not** the bay art; `main floor_001` has no per-bay child to
clone; a `Decal` would blend better but the blood pool already spawns up to
eight, so its size/orientation is a second unknown; shipping a texture is
unnecessary. What works: the shipped atlas `...fc area indicator8 marked8.png`
carries the plate as a clean sub-rect - framed grid, corner brackets,
"DESIGNATED LOAD AREA" legend - so a `PlaneMesh` with `uv1_offset` / `uv1_scale`
set to that box reproduces it in the original's exact tone. Nearest-filtered to
match the shipped border material, inset to 86% so the red shows as a frame.
**The sanctioned deviation:** the faked plate sits *on* the floor where the
shipped ones are recessed *into* it.

All these numbers are derived at runtime and visibly track each other: shrinking
the plate by 10% pulled the required side-zone shift from 1.87 to 1.19 with
nothing else touched.

**Verified.** At 8: `zones=8 added=4 rebound=20/20 plates=4/4` on the host **and
all seven clients**; `players=8 zones=8 owned=8` with eight distinct owner ids,
three complete plays; `pairing` showing eight distinct slots, each marker with
its matching zone; `crates requested=16 target=10 attempts=1-8 points=10
region=centre_cell`; side readouts at `(-24.66, -2.39)` and `(24.65, -2.39)`,
clearing walls at +/-26.8 by ~0.7; zero `[FORK8]` warnings. At 4, re-run after
all of the art work: `added=0 (vanilla)`, `region=vanilla`, `target=8`, **no
`fit` lines at all**, `zones=4 markers=4 owned=4` on all four peers.

**Reading the 4-vs-8 error diff here needs a control that actually dies.** Two
classes appear at 8 and not at 4 — `Attempt to disconnect a nonexistent
connection ... tree_exited` and `The multiplayer instance isn't currently
active` — both at the score-screen transition, naming global autoloads and the
shared `MineExplosion`/`BloodMist` pool (one BloodMist per elimination), so they
scale with **deaths**. Stable Footing is useless as a control (idle players never
die) and Spine Breaker never reached a score screen inside the window.
**Minefield at 8 — long since signed off — produces more of both (82 and 112 per
peer) than Forklift (41 and 112).** Pre-existing teardown churn.

**Human-verified.** Forklift's 8-player layout was driven by a person playing it
across several sessions, not just measured — that is what turned up the buried
plates, the red clipping into the score boxes, the oversized squares and the
readout positions, none of which any trace could see.

**One benign 8-only line, left alone.** `Playback can only happen when a node is
inside the scene tree`, once per session, **host only**, as the minigame is freed
and the next loads. Host-only is what identifies it: every other audio call here
is `call_local` and would print on all eight peers, while `crate_number_changed`
is connected inside `if multiplayer.is_server()`, making
`_on_crate_numbers_changed` -> `set_indicator_light_rpc()` ->
`speaker_mechanism.play()` the only server-only audio path (an inference from the
pattern, not a probe). Inaudible either way —
`set_minigame_sfx_linear_volume_rpc(0.0)` muted the bus two seconds earlier.
Silencing it properly would mean adding `forklift_certified_delivery_area.gd` as
a **51st overlay file** to be re-derived on every game update, for one log
line — declined.

**Re-check these three on a game update — the rest of this section derives
itself.** Floor height, zone footprints, the readout gap, plate sizes and the
side-zone shift are all measured at runtime, so a retuned level carries through
on its own. Three constants do not:

| Constant | Coupled to | If it drifts |
|---|---|---|
| `MOD_PLATE_TEXTURE` | a hardcoded `res://` path to the yard atlas | `load()` returns null, a `push_warning` fires and the added zones keep a plain red plate. **Fails soft** |
| `MOD_PLATE_UV_OFFSET` / `MOD_PLATE_UV_SCALE` | a pixel box measured off the **512x512** v1.0.7 atlas | a *re-authored* atlas puts the wrong art on the plate **with no warning at all** - the worst case here, and the only one to check by eye |
| `MOD_CRATE_CLEARANCE` (2.122) | the half-diagonal of a **3x3** crate | crates could spawn overlapping a zone edge and score for free |

Also `forklift_certified.tscn` overrides `spawn_radius = 4.0` on the crate
manager, so the script default is dead - re-read it from the *scene*, not the
script, the same trap as `[ROOMBA8]`'s `max_roombas`.

**Crossing another player's zone is a non-issue — do not "fix" it.** The gaps
between an added zone and its corner neighbours are ~1.1u against a 3.0-wide
forklift, so reaching a corner zone often means driving *across* someone else's.
A carried crate cannot register: `set_forked_rpc(true, ...)` in
`forklift_certified_crate.gd` teleports the crate to `Vector3.DOWN * 50.0`,
clears its collision layers 1 and 9 and hides it (the forklift shows an attached
stand-in), and a DropArea's `collision_mask` is `256` — layer 9 alone. Only a
crate actually set down counts, and the score is the set sitting in the area at
round end. Confirmed in play, then in the code.

**Not addressed, and parked:** whether 10 crates split eight ways is a good
*game*. `remove_zero_scoring_players()` eliminates everyone holding nothing at
round end, so round one culls hard — vanilla's shape at a bigger roster, not a
regression. **Tabled 2026-08-04 as untestable here** (idle instances create no
crate contention; same structural gap as open item 1); the lever would be the
crate count, which means a bigger centre cell and smaller zones.

### Diagnostic traces (all gated behind `-localtest`)

These exist because screenshots repeatedly proved unreliable. Prefer them.

| Trace | Where | Tells you |
|---|---|---|
| `[SEATS]` | `multiplayer_menu.gd` | lobby seat map + connected count |
| `[SEATS8]` | `green_pea.gd` | `is_server`, markers found, **chairs found** |
| `[STATIONS]` | `chisel_gauntlet.gd` | `is_server`, which nodes resolved, clones made |
| `[SHOTGUN]` | `round_eliminate.gd` | every slot the gun visits, with angle + peer |
| `[MINIGAME]` | `game.gd` | which minigame `MINIGAME=` pinned |
| `[AUTOSTART]` | `multiplayer_menu.gd` | host starting the session |
| `[ORIGINAL]` | `multiplayer_menu.gd` | confirms `-original` flipped the session to the **non-custom** playlist branch |
| `[FLOW]` | `intermission_briefing_screen.gd` | auto-ready under `FLOW=1`, one line per peer |
| `[SMOKE8]` | `smoke_break.gd`, `smoke_break_trolley.gd` | crate reveal, seats eliminated, and per-shot aim + decal range |
| `[PLATFORM]` | `junk_platform.gd` | per-slot spawn assignment (`marker=ring` above four players), then a per-peer audit of where every player actually landed with `ON_DECK`/`OFF_DECK` against the 6.0 platform radius and **which platform** - two players reporting the same `platform=` is the shared-deck bug. Above four players also `clone` (one per added platform, with `rebound=4/4`), `ring` (`asked` / `platforms` / `cloned`, per peer) and `cleared` (one per collapsed platform per peer, `colliders=1`). No `ring` line at four players is the pass |
| `[SCORE8]` | `intermission_score_screen.gd` | `is_server`, roster size, **rows**, row scale, `expanded` |
| `[BRIEF8]` | `intermission_briefing_screen.gd` | same, plus the learned invite-button offset ratios |
| `[DUCK8]` | `duck_hunt.gd`, `hunter_player.gd` | markers before/after with every x and an `outside_gate` count; `spawned` — the duck nodes that actually exist plus the hunter, per peer, named, with an `expected_ducks` cross-check; plus the hunter's `ducks`/`magazine`/`cycle` and the bolt animation's `bolt_len`/`bolt_window`/`bolt_speed`, per peer. `added=0` and `bolt_speed=1.000` at <= 4 players are the vanilla-parity gates |
| `[ROUNDS8]` | `game.gd`, `minigame_playing_state.gd` | how many rounds a minigame is actually getting: identifier, roster, `custom`, the value passed into `load_minigame`, and the resolved `max_rounds`. `load` fires on every minigame start including the first; `site=repeat` fires at the replay decision |
| `[DISCO8]` | `disco_dodge.gd` | roster, markers, **spawned player count** and every player node's name, per peer - the positive check that replaced "no errors appeared" |
| `[LANES8]` | `escalator_pit.gd` | `is_server`, lanes, **screens**, hidden art, lifts, strip scale, every lane's x, plus per-lane `step_size`/`mmi_scale` |
| `[ART]` | `escalator_pit.gd` | every mesh in the scene with world position, size and visibility - for identifying art to hide |
| `[TRAIN8]` | `train_race.gd` | markers, **nooks**, spawned count, per-peer landing audit, plus per-cycle `nooks_opened` / active / dead |
| `[KATO8]` | `knife_at_the_office.gd`, `countdown_handler.gd` | **searchables** counted, search target and whether it was `clamped`, landing audit, and indicator-icon growth per peer |
| `[SPINE8]` | `spine_breaker.gd` | markers, spawned, device resolved, landing audit; plus `pace` — roster, **active**, factor, fuse, dead time and the learned `vanilla_fuse` (see section 18; `factor=1.000` at <= 4 is the vanilla-parity gate) |
| `[ROOMBA8]` | `dvd_roomba.gd` | markers, spawned, live roombas, **`max_roombas`** (scene overrides the script), landing audit |
| `[FORK8]` | `forklift_certified.gd`, `crate_manager.gd` | `zones` — the delivery zones built on each peer, with every centre; `crate_region` — the free centre cell derived from the zone colliders; `pairing` — the marker/zone pair each player was actually given (they share one index, so a list that grew out of step pairs a player with someone else's zone **silently**); `crates` — requested vs target vs sampler attempts vs points, and `region=vanilla` or `centre_cell`; `rebound` — exported node references re-pointed at each clone's own children (20/20; anything less means a clone is driving the template's border or counter); `plates` — faked bay plates built; `fit` — the side zones' z-shift and where their readouts landed; `spawned` — per peer, the forklifts, the zones and how many zones have an owner. `added=0 (vanilla)`, `region=vanilla` and `zones=4` at <= 4 players are the vanilla-parity gates |

| `[FILTER8]` | `burn_recycle.gd` | `rooms` — per peer: `is_server`, `peer`, `rooms`, `subtrees=n/5` — **`4/5` is the complete result under v2.1.2**: `MOD_ROOM_SUBTREES` names five nodes and the shipped scene no longer has `burn recycle visuals blockout` (v1.5.0 did); judge room B by `belts`/`presses`/`indicators`/`timer_labels` — `belts`, `presses`, `indicators`, `timer_labels`; `eliminate` — `victims` this round, `alive_by_room=[r0=…, r1=…]`, `dead_total` and `contested`. `rooms=1` at <= 4 players is the vanilla-parity gate — room B is never built there |
| `[GUN8]` | `manufacture_gun.gd` | `expand` — host-side, per round: `roster`, `spawns=8 (+4)`, `desks=8 (+4)`, `closest_spawn_pair`, `empty_desks`, and `added=` with every mod desk's **position and yaw**, which is the only way to check `MOD_WALL_DESK_PUSH` from a log; `items` — `markers`, `per_marker` and `total`; `preview raised` — the ingredient projection's measured own height and its resulting y span, printed **inside the RPC so all eight peers report it**. At <= 4 players the parity gates are that `expand` and `preview raised` **do not appear at all** and `items` reads `per_marker=1 total=26` |

A count of **0** in any of these (`chairs=0`, `MISSING <path>`) means a lookup
failed silently - that is the single most common way a change does nothing.

**Two of these are absence-gated rather than value-gated** (`[GUN8]`'s `expand` and
`preview raised`), because the changes they report are built at runtime behind a
roster gate. For those, "no line at 4 players" *is* the pass — so grepping for a
value and finding nothing is ambiguous unless you know which kind of gate you are
looking at.

### Minigames deliberately NOT scaled — a historical record

**Nothing in the rotation is capped any more.** `modded_minigame_player_cap`
holds exactly one entry, **Scavenger Chairs**, and it is unreachable — in
neither `default_playlist` nor `CustomMinigamesWhitelist`, so the cap never
fires. Its reason stands on paper only (musical chairs; `4 - players.size()`
goes negative at five or more; the chairs are props, not seats bound to spawn
markers), because nothing can reach it to re-derive it.

| Minigame | The reason recorded here | What became of it |
|---|---|---|
| Duck Hunt | asymmetric: 3 duck slots + 1 hunter; magazine size derived from duck count | **Removed 2026-08-02 — the reason was wrong.** §19 |
| Forklift Certified | 4 DropAreas tile the whole yard, assigned per player by index | **Uncapped 2026-08-04 — the reason was wrong.** §20 |
| Manufacture Gun | 4 workstations are physical level geometry | **Uncapped 2026-08-07 — the reason was wrong.** The workstations are clonable at runtime and eight are now built that way. §22 |
| Burn Recycle | 4 player nodes hard-instanced into the scene, not spawned at markers | **Uncapped 2026-08-07 — the one recorded reason that survived inspection.** It is true, and the two-room split is how it was worked around rather than refuted. §21 |
| Scavenger Chairs | musical chairs; `4 - players.size()` goes negative; chairs are props | **Still capped**, and unreachable — in neither playlist |

**A cap reason is a judgement nobody re-tests, because a capped minigame never
runs and so never contradicts itself.** Three of the four recorded reasons were
wrong on measurement, and Forklift's measurement also turned up two failure
modes the static reading had never suggested. Re-derive an entry before trusting
it, and prefer a pinned run to a reading.

Scavenger Chairs, Shape Cutter, Memorize Path and Cutscene Game 02 have been
absent from both playlists since v1.0.6 — re-check after an update, the
developers may have enabled one.


### 21. The Filter — `burn_recycle.gd`, `burn_recycle_player.gd`

**Uncapped 2026-08-07, as TWO ROOMS rather than eight stations in one.** This is
the first entry in `modded_minigame_player_cap` whose recorded reason survived
inspection — Duck Hunt's and Forklift's both collapsed, this one did not:

- players are told apart **by rotation alone**, `90.0 * counter`, which wraps at
  eight (`90 * 4 = 360 = 0`), stacking players 5-8 on top of 1-4 (pitfall 14);
- `belts`, `presses` and `indicators` are exported arrays of exactly **four**.

Both failures are silent. `set_active_belt` does `belts[seat]`, an out-of-bounds
**read** that returns null with no error (pitfall 23), and `set_active_press`
simply finds no matching `press_id`. At >4 players four people would have had no
station at all, and a clean log.

#### Why two rooms and not eight stations

The first attempt cloned each station 45 degrees round the same ring. It measured
perfectly — `belts=8 presses=8 indicators=8` on all eight peers, zero errors —
and was **visibly wrong**: the shipped art already fills the ring at four, so the
consoles interpenetrated. Only a screenshot showed it.

Two rooms keeps every station at the shipped 90-degree spacing, so nothing clips,
**and the four authored camera clips stay exact** — within a room every other
player is still 90 or 180 degrees away. The 45-degree version had to snap seven
relative directions onto four clips, which no care would have fixed: the clips
are authored animations and the mod ships no `.res`. It also costs no new
replication surface — still **one** script, one `StateMachine`, one
`MinigameOverlay` and one `MultiplayerSpawner`, and the rooms cannot drift apart
because they share a timer.

**The lighting is free.** All six OmniLights, the incinerator and the main wall
live under `clientside visuals parent`, which vanilla already *rotates* to face
the local player's seat. It is per-viewer, not per-room — so room B needs no
lighting of its own, the assembly just moves to whichever room the local client
sits in. That is done in `setup_clientside_visuals()`, which runs in the
`camera.current = true` branch, i.e. exactly once, for the local player.

#### Balanced rooms, and the seat/station distinction

Rooms are `ceil`/`floor`: 5 -> 3+2, 6 -> 3+3, 7 -> 4+3, 8 -> 4+4. Filling room A
to four first would leave a **lone player** in room B at five, and with per-room
elimination a room of one is already finished — that player would collect a
survivor's score having played nothing.

**A player's ordinal and its station are different numbers**, and conflating them
is silent. With a 3+2 split the first room-B player is ordinal 3 but owns station
**4**; passing the ordinal hands it `belts[3]` and `press_id == 3` — room A's
belt and room A's press — with no error, because `belts[3]` exists.

#### Elimination and scoring

Elimination is **per room**: each room runs the shipped rule on its own players
(zero score -> a random zero-scorer dies; non-zero lowest -> only if exactly one
player holds it, otherwise **nobody** dies). That keeps vanilla's pace — three
rounds to resolve four players, against the seven a pooled ladder of eight would
take, doubled again by the minigame's two matches.

Scoring stays **global** — place in the overall elimination order, not within the
room. Same-round eliminations are tied **upward** to the top of that round's
batch (`mod_death_score`), because vanilla's raw index gave two players knocked
out at the same instant different scores, always in room order, and one raw point
is 85 session points. With one room a batch holds one victim, so the recorded
value is that victim's own index and **1-4 players score exactly as vanilla**
with no roster check — it falls out of the batching.

Measured: `[1, 1, 3, 3, 5, 5, 8, 8]` at eight, `[1, 1, 2, 5, 5]` at five, and
`[0, 1, 2, 4]` at four, which is vanilla byte for byte. Note nobody scores zero
at 5-8 any more; last place takes 1.

**Accepted asymmetry at odd rosters.** Both room winners take the full
`player_count`, so at seven room B's winner outlasts two players and room A's
outlasts three, and both score seven. Signed off deliberately rather than
overlooked.

#### Roster-gated dispatches, for vanilla-compat (2026-08-09)

All three mod RPC dispatches here are gated to **roster > 4**, so no mod RPC
crosses the wire in a lobby that may contain an unmodded peer. Two were provable
no-ops at ≤4. The third, `zz_mod_place_item_rpc`, also carries vanilla's
incinerator spark-ramp tail — at >4 that tail has to reach every peer so each one
ramps *its* room's incinerator — so its gate branches: >4 dispatches as before,
≤4 runs vanilla's original tail verbatim, host-side. That second branch **closes
an undocumented 1-4 parity deviation**: the pre-gate code ramped `spark_ratio` on
every peer where vanilla ramps host-only. See the archived 2026-08-09
session-log entry, and pitfall 30 for why the RPCs are named `zz_`.

#### Three traps this minigame produced

1. **`player spawn parent` holds four instances of the PLAYER SCENE** as editor
   placeholders, never referenced by `spawn_players()`. Duplicating it into room
   B created four full character rigs, each starting `SkeletonIK3D` and running
   the absolute-path manager handoff while detached — 256 errors a run, plus four
   bodies standing in room B. First written off as pre-existing churn on a grep
   for `type="Skeleton3D"` returning zero; the grep **cannot see inside instanced
   sub-scenes**. Controls settled it — DiscoDodge@8, ExplodingCollarRace@8 and
   BurnRecycle@4 all gave 0/0 while BurnRecycle@8 gave 128/128.
2. **`zz_mod_set_room_rpc` as `@rpc("authority")` was rejected silently.**
   `set_player_presence()` hands each player node's authority to that player's
   own peer, so the host is not the authority for anyone else's node. The offset
   never applied and all eight stood stacked two-per-station. Vanilla's
   `setup_rpc` is `any_peer` for exactly this reason.
3. **`launch_rpc` sets rotation and never position**, so a room-B player's tossed
   picture spawned at room A's centre and appeared to vanish. `item_parent_node`
   **is** the `ItemSpawner`'s `spawn_path`, so items cannot be re-parented into
   room B without breaking replication — the item is moved instead, on the same
   reliable channel just before `launch_rpc`, and re-set every launch because the
   items are pooled and reused across both rooms.

### 22. Firearm Factory — `manufacture_gun.gd`

**One file in the overlay.** The whole mod surface, so a re-derivation after a game
update can be checked off rather than reconstructed from the prose below:

| Identifier | What it is |
|---|---|
| `MOD_VANILLA_SLOTS` = 4 | the roster gate; everything below is skipped at <= 4 players |
| `MOD_WALL_DESK_TURN_DEG` = −90 | the wall desks' turn. **One sign, and it was backwards on the first attempt** — see below. Confirmed correct by eye 2026-08-08 |
| `MOD_WALL_DESK_SLIDE` = 3.8 | slide along the wall, off its midpoint |
| `MOD_WALL_DESK_PUSH` = 2.05 | push out against the wall (added 2026-08-08) |
| `MOD_ITEM_SPREAD` = 1.10 | how far a doubled ingredient is nudged (was 0.45) |
| `_mod_expand_container()` | inserts a marker at each pair of angularly-adjacent shipped markers; applies the turn/slide/push to the Z-dominated workstation ones |
| `_mod_nearest_shipped()` | copies rotation from the nearest shipped marker rather than inventing one |
| `_mod_expand_for_roster()` | host-only entry point; also raises `spawn_limit` on the three spawners by property write |
| `_mod_subtree_mesh_y_extent()` | measures the projection's own height without `get_transformed_aabb()` (pitfall 18) |
| `_mod_raise_item_preview()` / `_mod_preview_mover()` / `zz_mod_raise_item_preview_rpc()` | raise the ingredient projection clear of `MOD8`'s desk, on every peer |
| plus | the `remove_empty_workstation_rpc` bounds guard, and the roster-scaled item count in `spawn_items()` |

**`manufacture_gun.tscn` is deliberately NOT in the overlay** — every change here
is made at runtime behind the roster gate, including the `spawn_limit` raise, so
1-4 is untouched by construction and this minigame costs one file to re-derive.

**Uncapped 2026-08-07 — the last capped minigame.** Four blockers, of which only
the first is ever observed because it masks the rest:

1. `$SpawnPositions` ships **4** markers. `spawn_positions[counter].global_position`
   past index 3 is a null read (pitfall 23, silent), so `teleport_rpc` receives
   `Nil` and **aborts the host's spawn loop**. Measured at 8: the minigame never
   reaches `Round` at all.
2. `$WorkstationSpawns` ships 4, identical shape in `spawn_workstations()`.
3. `empty_desk_array` holds 4 and is used as `empty_desk_array[i].queue_free()` —
   a **method call** past the end, which is the pitfall-23 case that **SIGSEGVs**
   rather than failing quietly. Never seen, because (1) aborts first. Guarded.
4. `spawn_limit = 4` on all three MultiplayerSpawners (pitfall 11), raised by
   **property write** so `manufacture_gun.tscn` stays out of the overlay.

Unlike THE FILTER this arena has room — shipped workstations sit **15.1u** apart
on an 18.6 × 16.5 rectangle — so it expands in place rather than splitting into
rooms, which would also have halved the opponent pool in a PvP arena. Markers are
built at **runtime, host-only, gated on roster > 4**, so 1-4 seats on the shipped
four only.

#### The wall-desk turn, and the rule that looked principled and was backwards

Two of the four added mid-edge desks land against a wall with their approach side
pointing into it. **Which two is decided by the interact box, not by proximity.**
`InteractArea` is `BoxShape3D(2, 5, 3.6)`: the side a player approaches from runs
along the desk's **local Z**, the 3.6-deep axis, which at the shipped yaw of ~0 is
world Z — so the desks needing a turn are those whose offset from the arena
centre is **Z-dominated**. The first attempt tested **X**-dominance, reasoning
about which wall was nearest rather than which way the box ran, and selected the
exact complement: it turned the two desks that were already correct. Pitfall 29.

It was invisible from the logs and nearly invisible in a screenshot, because
**the camera is not axis-aligned**: it sits at `(-17.9, 11.9, 0)` looking along
`+X` with its right axis on world `+Z`, so on screen **right = +Z and up = +X**
(pitfall 28) and the desks turned in world ±X appear at *top- and bottom-centre*.
Any discussion of "the left one" is meaningless until that mapping is stated.

Turned desks then slide `MOD_WALL_DESK_SLIDE` (3.8u) along their wall in opposite
directions, `-sign(off.z)` on X, preserving the level's 180-degree rotational
symmetry, and finally push `MOD_WALL_DESK_PUSH` (2.05u) straight out at the wall
(next heading). Final layout, closest desk-to-desk 4.92u against a 2.0-wide desk:

| | position | yaw | |
|---|---|---|---|
| `MOD5` | (5.48, **−9.93**) | 86.5 | turned + slid +X + pushed at −Z wall |
| `MOD6` | (10.75, 0.11) | −5.1 | as generated |
| `MOD7` | (−2.02, **+10.00**) | −85.9 | turned + slid −X + pushed at +Z wall |
| `MOD8` | (−7.29, −0.03) | −3.5 | as generated |

#### The wall push, and where the wall actually is (2026-08-08)

Sliding alone left each turned desk on the line the shipped corner desks occupy —
**2.80u** (`MOD5`) and **2.71u** (`MOD7`) of bare floor short of the wall behind
it, marooned in the room rather than installed against it. One constant, measured:

| | |
|---|---|
| ±Z wall inner faces | **\|z\| = 11.99** (1.0 thick, outer at 12.99) |
| turned desk footprint | `BoxShape3D(2.4, 2, 3.8)` → reaches **1.315u** (`MOD5`, final yaw +93.54°) and **1.333u** (`MOD7`, −94.10°) along z from its centre |
| target margin | **0.73u**, which is what shipped `Marker3D2` leaves against the −X wall |
| ⇒ push | **2.05u**, giving 0.75u (MOD5) and 0.66u (MOD7) |

The two desks differ on every row because each inherits its yaw from its own
nearest shipped marker, and the shipped four sit at yaws of +3.54° to +5.08°
rather than 0. **Do not expect the pair to be symmetric** — the level's props are
not either.

Recover the wall position after a re-author by pulling
`ConcavePolygonShape3D_70a5h` out of `manufacture_gun.tscn`, offsetting by its
`CollisionShape3D` transform `(10.6282, 2.34833, 0)`, and keeping triangles whose
normal is Z-dominated at waist height: they span the whole x range at |z| = 11.99
exactly. **A vertex-only scan is not enough** — the walls are a handful of large
triangles, so vertices exist at only four x positions and the bins between them
read as empty floor.

**2.05 is set by the +Z side, not by the wall.** MOD7 is boxed in on three sides,
and the two neighbours are only visible if you test rotated rectangles, not AABBs:

| MOD7 clearance at push 2.05 | | at push 2.40 |
|---|---|---|
| +Z wall face | 0.66 | 0.31 |
| rotated crate collider (`BoxShape3D_ulsii` at (−6.82, 3.36, 12.71)) | 0.72 | 0.49 |
| `desk trolley` art (x 0.68…5.21, inner z 9.10) | 0.73 | 0.72 |

The crate is the reason. Its **AABB** is x[−9.96, −3.68] z[9.65, 15.77], which
looks like it overlaps MOD7's x span and forbids the push outright. It is rotated
~50°, so its true inner edge runs from (−6.10, 9.64) to (−3.68, 12.56) and only
crosses into the room (z < 11.99) at **x < −4.15** — clear of MOD7's desk, whose
nearest corner is x = −4.00. An AABB test here is wrong in the conservative
direction, which is how you end up believing a placement is impossible.

The camera constrains nothing: the ±Z walls are themselves in frame (half-width
at the desks' depth is 17.9u at 16:9 and 13.5u even at 4:3, against a wall at
11.99), so a desk against the wall is in frame by construction.

#### The interact volumes are generous — the desk is reachable from all four sides

Measured off the scenes 2026-08-08, and it **qualifies** pitfall 29 rather than
overturning it. Detection is Area3D↔Area3D on layer 256, `area_entered`:

| | |
|---|---|
| workstation `InteractArea` | `BoxShape3D(2, 5, 3.6)` at local (0, 2.5, 0) |
| player `Components/Rotated/InteractArea` | `CylinderShape3D` r=1.0 h=5.0 at local **(0, 2.5, −1)** — projected 1.0u forward, so it reaches 2.0u ahead of the player |
| player body | `CapsuleShape3D` r=0.7 |

The desk's interact box is *inset* from its own solid collider (2 vs 2.4, 3.6 vs
3.8), so the overlap always comes from the forward-projected cylinder, and the
desk is **reachable from all four sides with margin**. So the approach axis
decides how a desk *reads* and how much floor a player has, not whether the
interaction fires — "the side a player approaches from runs along the desk's
local Z" is the authored intent, not a hard constraint, and pitfall 29's rule
still holds. This is scene geometry plus the two shapes above; nothing here was
observed in play.

#### Ingredients scale with the roster

`spawn_items()` spawns exactly one item per shipped marker — a fixed **26** at any
roster. These are the components the guns are assembled from, so eight players
competing over a four-player supply halves everyone's share. Now 1 per marker at
1-4 and 2 at 5-8 (26 → 52), keeping ingredients-per-player constant. Copy 0 sits
exactly where vanilla puts it, so 1-4 is unchanged. Extras are nudged
`MOD_ITEM_SPREAD` sideways rather than stacked: a `ManufactureGunItem` is a plain
**Node3D with no physics**, so two at an identical position would intersect and
never settle apart.

**`MOD_ITEM_SPREAD` was 0.45 and that was too small — raised to 1.10 on
2026-08-08** after a report of ingredients clipping into each other. The five
variations' footprints, off `manufacture_gun_item.tscn`:

| variation | footprint (w × h × d) |
|---|---|
| `Cylinder_012` — the flat disc | **1.614** × 0.343 × 1.614 |
| `Cylinder_013` | 1.283 × 1.435 × 1.322 |
| `Torus` | 1.079 × 1.476 × 1.078 |
| `Cube_003` | 0.755 × 0.755 × 1.358 |
| `Cube_002` | 0.629 × 1.749 × 1.060 |

0.45 puts two of those inside one another whichever pair is drawn. Two copies stop
touching at `(w1 + w2) / 2` = **1.07** for the average pair, which is where 1.10
comes from. The worst case — two flat discs — still touches; separating that needs
1.61, which overhangs four markers.

**Checked against the surfaces the markers actually sit on**, since the risk of a
bigger nudge is a copy sliding off a table. Of the 26 markers, **11 are on the
floor** (unbounded), 2 on the +Z trolley, and 13 on desks at y ≈ 2.02; ten of
those 13 have ≥ 1.10u of desk left in the offset direction. The three that do not
are `part_011` (0.39u), `part_012` (0.75u) and `part_004` (0.93u) — and
`part_011`'s **shipped** item already overhangs, a 1.614-wide disc centred 0.39u
from the edge hanging 0.42u past it in vanilla.

**The offset stays in world space, deliberately.** Using the marker's own local X
— what `spawn_expand.py` does — is wrong here: **25 of the 26 item markers are
rotated**, and `part_001`'s basis has its Y column on world −Z, i.e. it is laid on
its side, so a local-X nudge would bury a copy under the table (pitfall 17).
`spawn_items()` discards marker rotation anyway and spawns every item
axis-aligned, so world space is also the consistent choice.

#### The ingredient projection is raised at 5-8 players

The five-slot recipe hologram — the "ingredient display bar" along the bottom of
the screen — is **one node in the level** (`Interactive/ItemSequencePreview/Visual`,
reached by the `item_sequence_preview_node_parent` export), not a per-player HUD,
and `MOD8`'s added desk lands on top of it:

| | x | z | y |
|---|---|---|---|
| projection | −7.56 … −6.34 | −4.63 … 5.12 | 0.62 … 2.50 |
| `MOD8` desk | −8.60 … −5.97 | −2.00 … 1.94 | 0 … 2.14 |

They overlap on all three axes, so the desk buries the **middle three of the five
slots** and the item holograms show through it. Moving the desk was ruled out —
it would change the balance of the arena — so the projection goes up instead, by
exactly its own height: **1.8741u**, measured at runtime, landing it at y 2.495 …
4.369, clear of the desk's 2.14 top. Three things about how:

- **The height is measured, not baked.** `_mod_subtree_mesh_y_extent()` walks the
  subtree and unions `mesh.get_aabb()` (local space) through each node's
  `global_transform`. It does **not** use `get_transformed_aabb()`, which returns
  null in the release template and aborts the calling function with no error line
  at all — pitfall 18. The runtime figure agrees with the static computation off
  the `.tscn` to 0.0013u.
- **The node that moves is the *parent* of the exported one.** Each of the five
  `recipe item parentN` children carries an `anim_spin recipe item`
  AnimationPlayer whose tracks are `.:position` and `.:rotation` on itself, so
  anything at or below `Visual` would be fought over every frame. Nothing animates
  `ItemSequencePreview`.
- **It is an RPC** (`zz_mod_raise_item_preview_rpc`, `authority`/`call_local`),
  because `initialize()` runs host-only and this alters the shipped scene. The
  trace lives *inside* the RPC for the same reason: verified `1.8741` on the host
  **and all seven clients**, exactly one `is_server=true`.

The `Recipe` collider box is x[−10.17,−6.17] y[0,4.50] z[−4.5,4.5], so 4.369 is
still under its ceiling, and the move is *toward* screen centre (screen-up is the
camera's Y basis). **The projection is not fully contained by that box and never
was** — it spans z[−4.63, 5.12], so its two end slots stick out at both ends in
vanilla too. It is a player barrier, not a bound on the hologram; do not use it as
one. At 1-4 players none of this runs — `MOD8` does not exist, so nothing covers
the projection. **Confirmed by eye at 8 players on 2026-08-08** and kept as
written: raise by the measured height exactly, no added clearance.

**One thin number:** a workstation's `gun assembly main parent` sits at local
y = 2.469 against the raised projection's underside at y = 2.495 — on `MOD8`, the
desk directly beneath it, a **0.026u** gap. Not a problem in the playtest, but if
either number moves this is the first thing to re-check, and the fix would be to
raise by the height plus a small clearance.

### 23. Pre-start disconnect guard — every rotation minigame's `player_disconnected()`

**Added 2026-08-15, all roster sizes, the §19 precedent (issue #13).** The
mechanism is pitfall 32's through a different door: a peer disconnects DURING a
minigame load while another peer is still loading, so the host processes the
disconnect before the load gate can pass and `player_disconnected()` runs
against an unspawned game — every per-player container empty,
`is_all_player_loaded` false, the state machine still in `Empty`. Pitfall 33
explains why that ordering is a **quit** (Alt-F4, pause menu — noticed by the
host immediately) rather than a crash (ENet timeout, noticed after everyone has
loaded), and why the kill-at-load recipe alone never showed it.

What each vanilla handler did at zero players, from the pre-spawn read of all
fifteen (verbatim extraction reviewed 2026-08-15):

| Handler | Pre-spawn behaviour |
|---|---|
| burn_recycle, dvd_roomba, forklift_certified, green_pea, junk_platform, spine_breaker, train_race (`size() > 1: return`), escalator_pit (same, checked synchronously), exploding_collar_race (`is_empty()` not returned), knife_at_the_office (`size() <= 1` → `end_game()`), manufacture_gun | end check falls through: `player_scores_finalized.emit({})`, 1–4 s later `MINIGAME_SFX` → 0, `set_effects_visibility_rpc(false)`, **`Empty → Finished`** and `minigame_finished` with no listener yet |
| chisel_gauntlet | safe: `check_all_submitted()` is behind `can_submit`, false until `RoundPlay` |
| disco_dodge | safe: `check_game_end_on_death()` returns unless `size() == 1` |
| smoke_break | no end check; `player_characters[_network_id]` unguarded (see pitfall 34) |
| duck_hunt | already guarded 2026-08-15 (§19) |

What follows the premature `Finished` depends on when the slow peer loads: if
before the transition fires (1–4 s), the real start runs first and the round is
cut off ~2 s in with no scores; if after, the game starts **from** `Finished`
(`can_leave()` is true) with `finished`/`game_end` already latched in
burn_recycle, dvd_roomba, green_pea, junk_platform, spine_breaker and
train_race, so `check_game_end()` returns forever and the round cannot end.
Reproduced pre-fix on DvdRoomba (`Empty → Finished`, then `Finished → Round →
Play` and no round end in 150 s where the healthy run cycles three rounds),
KnifeAtTheOffice and BurnRecycle (one elimination, then nothing) — runs in the
archived 2026-08-15 session-log entry.

**The fix, one hunk per handler:** `if not is_all_player_loaded: return` as
the first thing the handler does after its `is_server` check (Duck Hunt keeps
its removal RPC ahead of the guard because `_ready()` builds `possible_hunters`
from the roster; none of the other fourteen populate any per-player container
before `spawn_players()`, verified, so nothing needs removing pre-spawn). The
flag is safe to key on: every minigame's `all_players_loaded()` sets it and
emits `minigame_ready` synchronously, `game.gd::_on_minigame_ready` calls
`initialize()` in the same call stack, and in all fourteen `spawn_players()`
runs before any `await` — so once the flag is true the game is spawned. That
is also why the v1.3 gate re-run in `game.gd` (§19) already made the crash
ordering safe for these fourteen: it spawns the game before the handler runs.
A single generic gate in `game.gd` was considered and rejected because of
Duck Hunt's pre-spawn `possible_hunters`. `exploding_collar_race.gd` joins the
overlay for this (55 → 56 files); chisel_gauntlet and disco_dodge carry the
guard for uniformity.

Two hygiene hunks alongside: `manufacture_gun.gd` and `smoke_break.gd` now
`.get()` the per-player dictionary instead of indexing it, because a peer that
dropped during the load was never spawned there even once the game has started.
In the shipped release build the vanilla index was a silent null (pitfall 34),
so these change nothing observable there; a debug build would have errored.

Verified 2026-08-15 with the quit-at-load recipe (Testing) on the fixed build
across the eleven affected minigames and smoke_break — leaver noticed within
~0.7 s, no `Empty → Finished`, then the healthy start on host and clients —
plus kill-at-load regressions on the two `.get()` files and no-kill controls
at 4 and 8; evidence tables in the second archived 2026-08-15 session-log entry.

### 24. Roster-scaled scoring - `game.gd`, `globals.gd`, five elimination scripts

**Reported by players 2026-11-09 as "the points don't seem accurate" and "some
games pay far more".** Scoring was open item 1 - never played at 8 - and this
is what playing it found.

**The mechanism.** Every minigame hands the host a `player_scores` dictionary
of small raw integers through `player_scores_finalized`, and `game.gd`
multiplies by `score_multiplier` (**85**, read from `game.scn`). The
survival-order minigames build theirs as

```gdscript
for i in dead_players.size():
    player_scores[dead_players[i]] = i          # 0, 1, 2 ... in death order
for network_id in active_players.keys():
    player_scores[network_id] = player_count    # the winner
```

so the payout **is the roster size**: 0 / 85 / 170 and 340 for the winner at
four players, but 0 ... 510 and **680** at eight. The task-scored minigames
do not move - Table Manners tops out at 3 raw (255) at any roster - so at eight
players dying fifth in Lethal Rebound (4 raw) out-earned winning Table Manners,
and totals ran past the score screen's four digits.

**The fix** is one multiplication, in `_on_minigame_player_score_finalized()`:
`Globals.mod_score_scale(identifier, roster)` returns `4 / roster` for the
minigames in `Globals.mod_roster_scored_minigames` above four players and 1.0
otherwise, which maps 0..N back onto vanilla's 0..4. `roster` is the minigame's
own `player_count` - the roster the round started with, and the number it gives
the winner - so a mid-round disconnect does not rescale everybody else. When
the scale is 1.0 the vanilla integer line runs untouched, so 1-4 player lobbies
and every unlisted minigame score exactly as the unmodded game.

| Roster | Raw -> points (x85) |
|---|---|
| 4 (vanilla) | 0, 85, 170 - winner 340 |
| 5 | 0, 68, 136, 204 - winner 340 |
| 6 | 0, 57, 113, 170, 227 - winner 340 |
| 7 | 0, 49, 97, 146, 194, 243 - winner 340 |
| 8 | 0, 43, 85, 128, 170, 213, 255 - winner 340 |

**In the list:** `DvdRoomba`, `SpineBreaker`, `DiscoDodge`, `JunkPlatform`,
`TrainRace` (index-scored as above); `ForkliftCertified`, `BurnRecycle`,
`ChiselGauntlet` (same 0..N range by other routes - `dead_players.size()` at
removal, the batch index of section 21, `player_count - players_alive.size()`);
and `EscalatorPit`, whose *finalized* dictionary is +1 per rival outlived and so
also runs 0..N (its finish bonuses go through `player_scored`, which is not
scaled).

**Deliberately not in the list**, each for a reason that should be re-checked
rather than assumed if these files change:

- `DuckHunt` - `MinigameRoundsByPlayerCount` already drops it from two outer
  rounds to one above four players, which holds its payout level: 22 raw
  attainable at eight (hunter 8, plus 7 duck turns at 2) against 20 at four
  (two rounds of 4 + 3x2).
- `ManufactureGun`, `KnifeAtTheOffice` - they pay per kill or infection. The
  *most* one player can take grows with the roster, but the kills available
  per player do not, so the average payout is flat.
- `GreenPea`, `ExplodingCollarRace`, `SmokeBreak` - fixed per-player task
  points.

**Same-moment deaths share a placement.** Vanilla ranks two players killed by
the same train a full raw point apart, in whatever order the signals arrived.
The five index-scored scripts now record `Time.get_ticks_msec()` per death
(`mod_death_msec`) and, above four players, call
`Globals.mod_share_tied_placements()`, which gives every death within
`MOD_TIE_WINDOW_MSEC` (350) of the previous one the **best** index in its
group - the same "ties resolve upward" rule The Filter applies to its per-room
batches (section 21). A death with no recorded time (a disconnect) is never
tied. Forklift Certified and Chisel Gauntlet already score a simultaneous
batch equally (downward) in vanilla and are left alone. **Upward has a
degenerate end:** a whole lobby wiped by one event all score the top dead
index - an idle 8-player Tunnel Hazard, where the first train takes seven at
once, awards seven players 255 each (measured 2026-11-09). In real play a tie
is usually two or three players and co-survivors of a final collapse arguably
should score high, which is why upward was chosen; averaging each group's
indices would instead preserve exactly the pool vanilla hands out, at the cost
of carrying half-points through `player_scores` (typed `int` in every script).
Revisit if real sessions show wipes paying too well.

**Verified 2026-11-09** with a temporary host-side trace that printed each
finalized dictionary and the points awarded - built into the test pck from a
side overlay and **not in `mod/`** (the session-log entry has the lines):
`roster=4 scale=1.000` awarding 0/85/170/340; `roster=5 scale=0.800` awarding
68/136/204/340; `roster=8 scale=0.500` awarding 85/128/170/213/255/340, with
tied groups sharing a value. Idle instances, so what is exercised is death
order and the arithmetic, not skill play.

### 25. End-of-session results - `intermission_session_end.gd`

Joined the overlay 2026-11-09 (56 -> 57 files). Vanilla's
`send_session_end_data_host()` collects the final ranking with `for i in 5:` -
ranks 0..4 - so in a 5-8 player session the results screen named the winner
and three "failed" subjects and silently dropped everyone who finished fifth
or lower. The score screen was widened in v1.0 (section 11); this, its only
consumer, was not.

**Sending all seven non-winners is not the fix - it is a crash.** The screen
is a fixed stack: `lines` holds eight rows plus four inline labels (twelve),
and `show_subject_entry()` gives the failed list rows 4-6, then pads with

```gdscript
for j in 10:
    line_index += 1
    add_text(" ")
    if line_index == 8:
        break
```

which only stops when `line_index` is **exactly** 8. A fourth name leaves it at
8 before the loop, the loop counts on to `lines[12]`, and a method call past
the end of a typed array takes the process down in the release build
(pitfall 23). Vanilla's `for i in 5` is, by accident or design, what keeps the
list at three.

So the override does two things: the rank walk becomes `range(1, 9)` (ranks
start at 1, so this is identical whenever only ranks 1-4 exist), and
`_mod_name_rows()` packs more than three names into the same three rows -
two per row for four to six names, three for seven - clipping each to
`MOD_NAME_CHARS` (10) the way the score screen clips. Three names or fewer
pass through untouched, so a 1-4 player session prints what vanilla prints.

The file is derived from the shipped `.gdc` (identical token stream,
whitespace differs from a GDRE decompile); on a game update re-derive it from
the new decompile like any other overlay file.

**Verified 2026-11-09** at 8 players with a temporary trace (not in `mod/`):
every peer received `winner=P2` and seven losers, printed
`rows=["P3, P1, P4", "P6, P8, P5", "P7"]`, and reached
`exit_session_after_end` - the sequence ran to its end on host and all seven
clients. **Whether three names fit the row's width with long Steam names has
not been looked at**; the harness names are `P1`-`P8`.

### 26. Synchronizer send-rate cap above four players - `game.gd`

**Reported 2026-11-10:** a player running the game on a Mac saw "visual bugs
and players teleporting", only with the mod. Machine Party has no macOS build,
so that is the Windows build under a translation layer; the mod contains no
platform checks and adds no per-frame work, so nothing in it could be "tuned
for Mac". What the report led to instead is a property of vanilla's netcode
that the mod makes expensive.

**The mechanism.** Every player object carries a `MultiplayerSynchronizer`
whose properties are in replication mode 1 (*always*) with
`replication_interval` unset - read from the shipped player scenes - so its
owner sends a state packet on **every rendered frame** and the host relays it
to every other peer. Traffic therefore scales with frame rate times the square
of the roster: a 240 Hz player sends four times what a 60 Hz player does, and
eight players are 56 relayed streams where four are 12. Payload varies by
minigame: Lethal Rebound's player syncs three properties, Spine Breaker's six
or more.

**The evidence** is the game's own log of a real six-player session on v1.5
(`%APPDATA%/Godot/app_userdata/Machine Party/logs/`, read from a client).
After each Spine Breaker round every other player's stray updates for the
freed scene numbered 6-11; **one peer's numbered 993, 993, 983 and 987** -
4,559 of the session's 4,932 failed lookups came from that one peer - and its
tail ran on until the next round started. In Lethal Rebound, with half the
payload, the same peer's excess was about 2.5x. Whether that peer was the Mac,
and whether the tail is a send backlog or a scene freed late, **could not be
established from one side of the session**; what the log does establish is
that one peer's update stream was far out of step with everyone else's, in
proportion to how much the minigame syncs.

**The change.** `_mod_on_node_added()` in `game.gd`, connected to
`SceneTree.node_added` for the life of the Game scene, sets
`replication_interval = MOD_SYNC_INTERVAL` (0.015 s) on every
`MultiplayerSynchronizer` entering the tree while the roster exceeds four. It
runs on every peer because a synchronizer is sent by its owner. 0.015 sits
just under a 60 Hz frame (16.7 ms), so a 60 FPS player still sends every frame
- a full 1/60 would skip alternate frames on timing jitter - and only faster
frame rates are thinned. No RPC and no scene edit; lobbies of four or fewer
are returned from before the property is touched (rule 3).

**Measured 2026-11-10**, six players in Spine Breaker over a 20 s steady-state
window, per-process socket bytes, frame rates 102-224 FPS in both runs:

| | host | each client |
|---|---|---|
| before | 113.9 KB/s | 28.2 KB/s |
| after | 50.0 KB/s | 14.4-17.9 KB/s |

A temporary trace (not in `mod/`) printed every synchronizer the hook saw: at
six players `capped ... interval=0.015` on host and all five clients and never
`left alone`; at four players `left alone ... interval=0.0` on all four peers
and never `capped`.

**Not verified:** that this cures the report. It bounds what each player sends
and halves what a slow machine has to process, which is the part of the
problem the mod can reach; the Mac player's renderer glitches, if they come
from the translation layer, are outside it. The untried test that would
settle the cause is his own log from a session, and whether capping his frame
rate (`--max-fps 60` as a Steam launch option) changes what others see.

### 27. How points work, shown in the game - `globals.gd`, `intermission_briefing_screen.gd`, `intermission_score_screen.gd`

**Reported 2026-11-13:** "the players don't understand how the points are
split, and why each player got what they got". The board showed a pot and
running totals and nothing else, and §24's roster scaling made the numbers
less guessable still. Two additions, both above four players only (rule 3: a
1-4 briefing has no extra page and a 1-4 board no tag, because neither is ever
created there).

**A POINTS page closes every minigame's briefing.**
`Globals.mod_points_page(identifier, roster, multiplier)` builds it and
`set_briefing_screen_info()` appends it after the minigame's own pages, on
every peer from the same roster, so no RPC. Every number is derived: the
multiplier is `game.gd`'s `score_multiplier` passed in, the survival ladder
goes through `mod_score_scale()` with `game.gd`'s rounding, and the
per-event lines mirror the scoring code of each minigame - **change a
minigame's scoring and its line here has to change with it**:

| Minigame | What the page says (session points) | From |
|---|---|---|
| the eight survival-order minigames (§24's list minus Wrong Way) | a place ladder for this roster - at eight `1st 340, 2nd 255, 3rd 213, 4th 170, 5th 128, 6th 85, 7th 43, 8th 0`; "out at the same time: same points" for all but Forklift Certified, which ranks every death on its own | k-th place holds raw `roster - k`, the winner `roster`, scaled |
| Wrong Way | top first 170, top 85 (unscaled, `player_scored`); +`340/roster` to everyone still climbing per fall, and to the last one climbing | `escalator_pit.gd` |
| Minefield | halfway 85, the van 85, first to the van +85, no lives lost +85 | `exploding_collar_race.gd` |
| Table Manners | halfway 85, finish 85, first to finish +85 | `green_pea.gd` |
| Firearm Factory | each gun built 85, each kill 85, last one alive 85 | `manufacture_gun.gd` |
| Inside Job | first to find the syringe 85, each player infected 85, not infected at the end 85 | `knife_at_the_office.gd` |
| Smoke Break | first to finish 170, 2nd and 3rd 85, everyone else 0 | `smoke_break.gd`, `round_end_state.gd` |
| Duck Hunt | ducks: the end 85, first there +85; hunter: each duck 85, every duck +85 | `duck_hunt.gd` |

Every page opens "Each round:" because the payout repeats per round. The
text is English only; the game's other briefing text goes through its
translation tables, which the mod cannot extend.

**Each score-screen row ends with what that player just earned and where it
placed them** - `+255 2nd`, ties sharing the better place (`3rd, 3rd, 5th`).
The tag is a duplicate of the row's own score label, so it shares its font,
size and scale; as the row's child it moves with every rank swap and hides
with the row. All tags share one column just past the widest name on the
board, measured with the label's font.

**Verified 2026-11-13** on a client of an eight-player FLOW run through The
Filter, from the game's own rendered frames (a scratch-only capture build,
never in `mod/`): the briefing showed `POINTS`, `Page 3/3`, the full ladder
inside the panel; the score screen showed `+553 1st`, `+510 2nd`,
`+383 3rd` twice, `+256 5th` twice, `+213 7th`, `+86 8th` beside the names,
each sum a valid pair of the match payouts.
