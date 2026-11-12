# CS1.6 player extras

Original GPL-3.0-or-later AMX Mod X plugins for Counter-Strike 1.6. Version
0.1.0 is a development candidate. Compilation and policy tests do not establish
live gameplay acceptance. No customer files or client media are included.

## Player hub

`/menu`, `/help` and `/standings` provide a common entry point and current-map
scores. Clan War shortcuts call the existing `/ready`, `/notready`, `/readylist`
and `/score` commands; match administration requires `ADMIN_CFG` in both the
menu and its handler. Deathmatch and Zombie shortcuts open `/guns`; GunGame
shortcuts open `/level` and `/ggtop`. The corresponding mode plugin is separate.

Set `kgb_extras_mode` explicitly to `public`, `clan-war`, `deathmatch`, `gungame`
or `zombie-infection`. Its default `off` disables all hub behavior. Managed
recipes select it; standalone operators set it in server.cfg. The remaining
controls are in `configs/kgb_player_hub.cfg`.

Public, Deathmatch and Zombie support `/nominate`, `/rtv` and `/vote`. Alternatives
come only from valid installed maps in the configured root `.txt` mapcycle;
at most 64 alternatives and 512 lines are read. Invalid or overlong names are
rejected, never truncated. Nominations rank up to five alternatives. Each human
connection can request and cast once. Bots and HLTV are excluded; spectators
count as humans. A vote snapshots connection userids and the electorate.
Departures cannot reduce its majority; late joins cannot vote. A majority of
that electorate must choose a change, and one map must uniquely beat both the
other maps and the keep-current option. Ties and abstention keep the current map.

Public/Zombie changes wait for the actual round end. If no round ends within
`kgb_hub_map_wait` seconds (default 900, bounded 30–1800), the pending result is
cancelled and voting reopens. Waiting/infinite rounds are never cut short. Deathmatch announces a
five-second delay. Clan War and GunGame never enable map voting. The hub does
not disable the server's own mapchooser or another community vote plugin:
owners should run only one map-vote system. Automatic menus avoid existing UI;
explicit player commands may replace it. Cleanup clears only the exact owned
menu, so other plugins' menus are preserved.

## Deathmatch loadouts

Requires the hub mode `deathmatch`, ReGameDLL `mp_freeforall 1` and a positive
`mp_forcerespawn`. It fails closed on a mismatch. `/guns` offers stock M4/USP,
AK/Deagle, MP5/USP, M3/Deagle, Scout/USP and optional AWP/Deagle. A choice is
remembered for this connection and equipped after spawn. The first selection
can replace this life's loadout once; further selections apply next spawn.
It never refreshes health or armor. No Steam ID, file or database is used.

`configs/kgb_deathmatch_loadout.cfg` controls the automatic menu, AWP (off), kill
healing (off, at most 25 HP and a 100 HP cap), and headshot-only bullet training
(off). The bullet filter applies to bots and humans. Knives and grenades retain
their normal damage. These settings do not apply in another hub mode.

## Install and owner settings

Requires AMX Mod X with CStrike; Deathmatch additionally uses Fun, Fakemeta and
Ham Sandwich. CI compiles against pinned 1.8.2, 1.9 and 1.10 compilers. KGB's
development candidate uses the pinned 1.8.2 build on the canonical 1.9 ReHLDS runtime.

1. Build with `AMXX_VERSION=1.9 ./scripts/build.sh`.
2. Copy the desired `compiled/*.amxx` to `addons/amxmodx/plugins/` and add each
   filename once to `addons/amxmodx/configs/plugins.ini`.
3. Copy its configuration to `addons/amxmodx/configs/` **only if absent**. Existing
   owner files take precedence. Plugin configs run in `plugin_cfg`; put optional
   feature settings in those files, not in an earlier server.cfg command.
4. Select the mode explicitly in server.cfg and restart. Check `amxx plugins`,
   `kgb_hub_status` and (for Deathmatch) `kgb_dm_loadout_status`.

Do not install the Deathmatch plugin in another core mode. For removal, stop the
server, remove only its plugin entry/binary and unedited owned config; retain
owner edits. The Platform installer handles ownership tracking separately.

## Reproducible checks

`python3 -m unittest discover -s tests -v` executes the actual integer vote
policy and map token parser through a documented C subset translation, with
negative mutations. It does not emulate GoldSrc. `scripts/build.sh` verifies
official compiler downloads by SHA256 and builds in a pinned, read-only,
network-disabled container. Any compiler warning fails. `scripts/package.py`
creates a deterministic ZIP with source, config and license.

Live acceptance remains required: rendering/cancellation, reconnect and slot
reuse, admin denial, stale ballots, real map boundaries, competing-menu cleanup,
Deathmatch inventory/damage/healing, and switching/removal across all five modes.
