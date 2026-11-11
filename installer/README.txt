Machine Party - 8 Player Mod
============================

Raises the online player cap from 4 to 8.

Built for Machine Party v2.1.2. Works on Windows, Linux and macOS - it patches
whichever copy of the game you already own.

ON A MAC: Machine Party has no native macOS version on Steam. Mac players run
the Windows version through CrossOver or Whisky, and the mod works there
exactly as it does on Windows - the game file it patches is identical on every
platform. The installer looks inside CrossOver and Whisky bottles on its own;
see INSTALL below.


IMPORTANT
---------
Lobbies of 5-8 players need EVERYONE on this same mod release. Since v1.1
you can also play with unmodded friends: a lobby mixing modded
and unmodded players works automatically, caps at 4 players, and plays the
plain vanilla rotation. A 5th player trying to join a mixed lobby is refused
with the game's version-mismatch message rather than the game breaking halfway
through a session. Two different mod releases always refuse each other, so
modded friends should update together (e.g. v1.5 and v1.6-fork cannot connect).


INSTALL
-------
The installer sits in the same folder as this file:

  Windows      double-click WindowsInstall.bat - no Python install needed,
               the zip bundles its own runtime
  macOS/Linux  double-click install.sh (it opens a terminal itself), or run:
               python3 install.py

Already have Python? On any platform, run  python3 install.py  directly.

The installer finds your Steam copy automatically and patches your game files
directly. It keeps no backup of its own. If you run it again on a game that is
already patched it stops and tells you to restore the original first (see
UNINSTALL below) - that keeps it from building the mod on top of itself.

If it cannot find the game, point it at the folder yourself:

  python3 install.py --game-dir "C:\...\steamapps\common\party project\Machine Party_Windows"

On a Mac, open Terminal, go to this folder and run  sh install.sh  (macOS
offers to install Python the first time if it is missing). If the game lives
in a bottle the installer does not know about, the folder to point it at is
the Windows game folder inside that bottle, for example:

  python3 install.py --game-dir "$HOME/Library/Application Support/CrossOver/Bottles/<bottle>/drive_c/Program Files (x86)/Steam/steamapps/common/party project/Machine Party_Windows"

Quit the game (and Steam inside the bottle) before installing.

If the game stutters or looks wrong on a Mac, try a different graphics mode.
In Steam, right-click Machine Party -> Properties -> Launch Options and enter
one of these, one at a time (remove it again if the game will not start):

  --rendering-driver d3d12
  --rendering-method mobile
  --max-fps 60


DID IT WORK?
------------
Launch the game and look at the version in the corner of the main menu:

  fork by zip v2.1.2-8P-v1.6-fork    <- mod is active
  v2.1.2                             <- still the original

Or check without launching:

  python3 install.py --verify

That reports PATCHED, NOT PATCHED, or PARTIALLY PATCHED.


UNINSTALL
---------
Steam: Properties -> Installed Files -> Verify integrity of game files. That
puts the original game back, and it is the uninstall - the installer keeps no
backup to restore from.

  python3 install.py --uninstall

only tells you whether the mod is currently installed and points you at those
same steps. It does not change your game files.

Note that a Steam update will also overwrite the mod - simply run the
installer again afterwards.


WHAT CHANGED
------------
- Lobbies hold up to 8 players.
- All fifteen minigames in the rotation play at 8. None of them are skipped
  for having too many people in the lobby.
- Spawn points in 15 minigames rebuilt to seat 8.
- Three extra suit colours (orange, cyan, pink) so everyone is distinguishable.
- A plain text list of player names in the lobby corner, because eight floating
  nametags get hard to read once the characters are packed together.
- The score screen and the pre-game briefing screen show all 8 players. They
  previously showed only the top 4 and silently dropped the rest. The score
  screen shows one row per player, so five players get five readable rows
  rather than eight small ones.
- POINTS in lobbies of 5-8: the last-one-standing minigames (Lethal Rebound,
  Spine Breaker, Stable Footing, Debris Platforms, Tunnel Hazard, Forklift
  Certified, The Filter, Chisel Gauntlet, and the survival points in Wrong Way)
  pay on the same scale as a 4-player game - 0 for first out, 340 for the
  winner, evenly spaced in between. They used to pay by lobby size, so a win
  was worth 680 at eight players and dying fifth beat winning Table Manners.
  Players eliminated at the same instant now score the same.
- The end-of-session results screen lists everyone. It used to drop whoever
  finished fifth or lower.
- In lobbies of 5-8, each player's position updates are limited to about 60 a
  second. The game normally sends one per frame drawn, so a player on a fast
  monitor sent several times more than everyone else, and with more players
  that added up. This is meant to cut down on players appearing to teleport.
- CHISEL GAUNTLET: four more carving stations, and split-screen extended to 8.
- WRONG WAY: each of the four troughs split into two sets of stairs - eight
  lanes, one player each - with eight screens and eight input arrows.
- TABLE MANNERS: eight chairs, with the camera pulled back and widened.
- SMOKE BREAK: eight seats, with two crates added at the ends of the bench.
- FORKLIFT CERTIFIED: four more delivery zones, so eight players fit in the
  yard instead of crowding the original four.
- THE FILTER: a second, identical room. Players are split between the two
  rooms so nobody is left on their own, and scoring is shared across both.
- FIREARM FACTORY: eight workstations instead of four, and more ingredients to
  go round - previously the same fixed amount was shared however many people
  were playing.
- DEBRIS PLATFORMS: above four players the level becomes a ring of six or
  eight platforms, so everyone has a platform - and a debris stream - of their
  own. It used to seat two players on each of the four platforms, which also
  doubled the debris falling on them.
- MINEFIELD, TUNNEL HAZARD, LETHAL REBOUND, STABLE FOOTING: seat eight, no
  other changes needed.
- INSIDE JOB: fixed a bug where, at 6 or more players, the syringe could never
  be found and the round would never end. The hunt display now shows all 8.
- SPINE BREAKER: the spider kills faster in bigger lobbies, so an 8-player
  round does not run two and a half times as long as a 4-player one. Timing is
  unchanged at 1-4.
- DUCK HUNT: now plays with up to 8. One player hunts and everyone else runs,
  so the hunter faces up to 7 ducks; extra starting positions were added and
  the rifle's magazine grows to match. An 8-player session runs 8 hunting
  turns, not 16.

Removed on purpose:

- The wheat-field cutscene no longer appears. It scored nothing and broke up
  the pace. This is the only change that also affects 1-4 player games.

Apart from the cutscene, a 1-4 player game plays exactly as it did before.
That is deliberate: the extra seating and layout changes only switch on above
four players.


KNOWN ROUGH EDGES
-----------------
- SMOKE BREAK: the four players on the left of the bench can clip into each
  other. It is a cosmetic overlap caused by the angle those seats face, and it
  does not affect play.
- SPINE BREAKER at 7-8 players: you get less time to throw the spider onto
  somebody else before it kills you - roughly 9 seconds at 8 players against
  20 at 4. That is the trade for a round that does not drag.
- DEBRIS PLATFORMS: the ring of platforms for 5-8 players is new. It has been
  watched in a test session but not yet played by a full lobby. If a platform
  looks misplaced, is cut off by the edge of the screen, or its press comes
  down in the wrong spot, that is worth reporting.
- In a full lobby, players can spawn touching and visibly push apart for an
  instant at the start of a minigame. It settles immediately.
- The lobby's 8 character previews have been tested for loading but never seen
  in a real Steam lobby with 8 people in it. If they look wrong, say so.
- ARCADE mode (new in game v1.5.0) is expected to work - the mod applies the
  same player-count handling to it - but it has never actually been run with
  the mod, because it cannot be reached in local testing. Reports welcome.
- Nobody has yet played a real 8-player session with eight actual people, so
  scoring and win conditions at 8 are less proven than everything else. If a
  round ends with the wrong winner or fails to end, that is worth reporting.

If anything else looks off at 8 players, please report it.
