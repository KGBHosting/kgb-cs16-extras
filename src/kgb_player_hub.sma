// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 KGB Hosting
#include <amxmodx>
#include <amxmisc>
#include <cstrike>

#define VERSION "0.1.0"
#define MAX_CLIENTS 32
#define TASK_HINT 41900
#define TASK_VOTE_END 41940
#define TASK_MAP_CHANGE 41941
#define TASK_MAP_EXPIRY 41942

enum HubMode { MODE_OFF, MODE_PUBLIC, MODE_CLAN_WAR, MODE_DEATHMATCH, MODE_GUNGAME, MODE_ZOMBIE }
new g_enabled, g_mode, g_join_hint, g_maxplayers
new g_hint_userid[MAX_CLIENTS + 1]
new g_owned_menu[MAX_CLIENTS + 1], g_menu_userid[MAX_CLIENTS + 1]
new bool:g_menu_ballot[MAX_CLIENTS + 1]

#include "include/hub_votes.inc"

public plugin_init()
{
    register_plugin("KGB Player Hub", VERSION, "KGB Hosting")
    register_cvar("kgb_hub_version", VERSION, FCVAR_SERVER | FCVAR_SPONLY)
    g_enabled = register_cvar("kgb_hub_enabled", "1")
    // Fail closed until a recipe or owner explicitly selects its mode.
    g_mode = register_cvar("kgb_extras_mode", "off")
    g_join_hint = register_cvar("kgb_hub_join_hint", "1")
    g_maxplayers = get_maxplayers()
    for (new id = 0; id <= MAX_CLIENTS; id++) g_owned_menu[id] = -1
    register_clcmd("say /menu", "command_hub")
    register_clcmd("say_team /menu", "command_hub")
    register_clcmd("say /help", "command_help")
    register_clcmd("say_team /help", "command_help")
    register_clcmd("say /standings", "command_standings")
    register_clcmd("say_team /standings", "command_standings")
    register_srvcmd("kgb_hub_status", "command_status")
    votes_init()
}

public plugin_cfg()
{
    new dir[128]
    get_configsdir(dir, charsmax(dir))
    server_cmd("exec %s/kgb_player_hub.cfg", dir)
    server_exec()
    votes_load_cycle()
}

public client_putinserver(id)
{
    hub_close_menu(id)
    votes_reset_client(id)
    g_hint_userid[id] = get_user_userid(id)
    remove_task(TASK_HINT + id)
    set_task(20.0, "task_hint", TASK_HINT + id)
}

#if AMXX_VERSION_NUM < 183
public client_disconnect(id) { cleanup_client(id); }
#else
public client_disconnected(id) { cleanup_client(id); }
#endif

stock cleanup_client(id)
{
    hub_close_menu(id)
    remove_task(TASK_HINT + id)
    g_hint_userid[id] = 0
    votes_reset_client(id)
}

public plugin_end()
{
    for (new id = 1; id <= g_maxplayers; id++)
    {
        hub_close_menu(id)
        remove_task(TASK_HINT + id)
    }
    remove_task(TASK_VOTE_END)
    remove_task(TASK_MAP_CHANGE)
    remove_task(TASK_MAP_EXPIRY)
}

public task_hint(task)
{
    new id = task - TASK_HINT
    if (hub_player(id) && get_pcvar_num(g_join_hint) && get_user_userid(id) == g_hint_userid[id])
        client_print(id, print_chat, "[Server] Type /menu for player options and /help for this mode's rules.")
}

stock HubMode:hub_mode()
{
    if (!get_pcvar_num(g_enabled)) return MODE_OFF
    new mode[24]
    get_pcvar_string(g_mode, mode, charsmax(mode))
    if (equal(mode, "public")) return MODE_PUBLIC
    if (equal(mode, "clan-war")) return MODE_CLAN_WAR
    if (equal(mode, "deathmatch")) return MODE_DEATHMATCH
    if (equal(mode, "gungame")) return MODE_GUNGAME
    if (equal(mode, "zombie-infection")) return MODE_ZOMBIE
    return MODE_OFF
}

stock bool:hub_player(id)
{
    return id >= 1 && id <= g_maxplayers && is_user_connected(id)
        && !is_user_bot(id) && !is_user_hltv(id) && hub_mode() != MODE_OFF
}

public command_hub(id)
{
    if (!hub_player(id)) return PLUGIN_CONTINUE
    new menu = menu_create("Player options", "hub_handler")
    menu_additem(menu, "How to play / commands", "help")
    menu_additem(menu, "Current-map standings", "standings")
    switch (hub_mode())
    {
        case MODE_CLAN_WAR:
        {
            menu_additem(menu, "Mark ready", "ready")
            menu_additem(menu, "Mark not ready", "notready")
            menu_additem(menu, "View ready list", "readylist")
            menu_additem(menu, "Match score and phase", "score")
            if (get_user_flags(id) & ADMIN_CFG) menu_additem(menu, "Admin: match controls", "matchadmin")
        }
        case MODE_DEATHMATCH: menu_additem(menu, "Choose / remember weapon loadout", "guns")
        case MODE_GUNGAME:
        {
            menu_additem(menu, "My weapon level", "level")
            menu_additem(menu, "GunGame ladder standings", "ladder")
        }
        case MODE_ZOMBIE:
        {
            menu_additem(menu, "Human weapon selection", "guns")
            menu_additem(menu, "Infection phase and role", "zombie")
        }
    }
    if (votes_allowed())
    {
        menu_additem(menu, "Nominate an installed map", "nominate")
        menu_additem(menu, "Rock the vote", "rtv")
        if (g_vote_active) menu_additem(menu, "Cast map ballot", "vote")
    }
    hub_show_menu(id, menu)
    return PLUGIN_HANDLED
}

public hub_handler(id, menu, item)
{
    if (!hub_owns_menu(id, menu)) return PLUGIN_HANDLED
    if (item == MENU_EXIT || !hub_player(id)) { hub_release_menu(id, menu); return PLUGIN_HANDLED; }
    new info[24], name[1], access, callback
    menu_item_getinfo(menu, item, access, info, charsmax(info), name, 0, callback)
    hub_release_menu(id, menu)
    if (equal(info, "help")) command_help(id)
    else if (equal(info, "standings")) command_standings(id)
    else if (equal(info, "nominate")) command_nominate(id)
    else if (equal(info, "rtv")) command_rtv(id)
    else if (equal(info, "vote")) command_vote(id)
    else if (hub_mode() == MODE_CLAN_WAR)
    {
        if (equal(info, "ready")) client_cmd(id, "say /ready")
        else if (equal(info, "notready")) client_cmd(id, "say /notready")
        else if (equal(info, "readylist")) client_cmd(id, "say /readylist")
        else if (equal(info, "score")) client_cmd(id, "say /score")
        else if (equal(info, "matchadmin") && (get_user_flags(id) & ADMIN_CFG)) client_cmd(id, "amx_cw_menu")
    }
    else if (hub_mode() == MODE_DEATHMATCH || hub_mode() == MODE_ZOMBIE)
    {
        if (equal(info, "guns")) client_cmd(id, "say /guns")
        else if (equal(info, "zombie") && hub_mode() == MODE_ZOMBIE) client_cmd(id, "say /zombie")
    }
    else if (hub_mode() == MODE_GUNGAME)
    {
        if (equal(info, "level")) client_cmd(id, "say /level")
        else if (equal(info, "ladder")) client_cmd(id, "say /ggtop")
    }
    return PLUGIN_HANDLED
}

public command_help(id)
{
    if (!hub_player(id)) return PLUGIN_CONTINUE
    client_print(id, print_chat, "[Server] /menu opens player options. /standings shows map scores.")
    client_print(id, print_chat, "[Server] Scores are for this map, with no persistent player tracking.")
    switch (hub_mode())
    {
        case MODE_PUBLIC:
        {
            client_print(id, print_chat, "[Public] Play the map objective with your team.")
            client_print(id, print_chat, "[Public] /nominate picks a map. /rtv requests a map vote.")
        }
        case MODE_CLAN_WAR:
        {
            client_print(id, print_chat, "[Clan War] /ready, /notready, /readylist and /score.")
            client_print(id, print_chat, "[Clan War] Match admins control warmup, knife rounds and setup.")
        }
        case MODE_DEATHMATCH:
        {
            client_print(id, print_chat, "[Deathmatch] Every player is an opponent. /guns picks your stock loadout.")
            client_print(id, print_chat, "[Deathmatch] Your choice is remembered; later changes apply next spawn.")
        }
        case MODE_GUNGAME:
        {
            client_print(id, print_chat, "[GunGame] Kill with your assigned weapon to advance.")
            client_print(id, print_chat, "[GunGame] Finish with a grenade and knife. /level and /ggtop show progress.")
        }
        case MODE_ZOMBIE:
        {
            client_print(id, print_chat, "[Zombie Infection] Humans survive the timer. Zombie knife hits infect.")
            client_print(id, print_chat, "[Zombie Infection] Choose human weapons with /guns before infection.")
            client_print(id, print_chat, "[Zombie Infection] Zombies: press N for night vision.")
        }
    }
    return PLUGIN_HANDLED
}

public command_standings(id)
{
    if (!hub_player(id)) return PLUGIN_CONTINUE
    new players[32], count
    get_players(players, count, "ch")
    // Bounded in-map standings; no auth IDs, files, SQL or lifetime ranking.
    for (new a = 0; a < count; a++)
        for (new b = a + 1; b < count; b++)
            if (get_user_frags(players[b]) > get_user_frags(players[a])
                || (get_user_frags(players[b]) == get_user_frags(players[a]) && get_user_deaths(players[b]) < get_user_deaths(players[a])))
            { new swap = players[a]; players[a] = players[b]; players[b] = swap; }
    new menu = menu_create("Current map: kills / deaths", "readonly_handler")
    for (new i = 0; i < min(count, 10); i++)
    {
        new name[32], line[96]
        safe_player_name(players[i], name, charsmax(name))
        formatex(line, charsmax(line), "%d. %s: %d / %d", i + 1, name, get_user_frags(players[i]), get_user_deaths(players[i]))
        menu_additem(menu, line)
    }
    if (!count) menu_additem(menu, "No human players connected")
    hub_show_menu(id, menu)
    return PLUGIN_HANDLED
}

public readonly_handler(id, menu, item)
{
    hub_release_menu(id, menu)
    return PLUGIN_HANDLED
}

stock bool:hub_owns_menu(id, menu)
{
    return id >= 1 && id <= g_maxplayers && g_owned_menu[id] == menu
        && is_user_connected(id) && g_menu_userid[id] == get_user_userid(id)
}

stock hub_release_menu(id, menu)
{
    if (id >= 1 && id <= g_maxplayers && g_owned_menu[id] == menu)
    {
        g_owned_menu[id] = -1
        g_menu_userid[id] = 0
        g_menu_ballot[id] = false
        menu_destroy(menu)
    }
}

stock hub_close_menu(id)
{
    if (g_owned_menu[id] < 0) return
    new owned = g_owned_menu[id], old_menu, current_menu
    g_owned_menu[id] = -1
    g_menu_userid[id] = 0
    g_menu_ballot[id] = false
    if (is_user_connected(id))
    {
        if (player_menu_info(id, old_menu, current_menu) && current_menu == owned)
        {
            menu_cancel(id)
            show_menu(id, 0, "^n", 1)
        }
    }
    menu_destroy(owned)
}

stock hub_show_menu(id, menu, bool:ballot = false)
{
    hub_close_menu(id)
    g_owned_menu[id] = menu
    g_menu_userid[id] = get_user_userid(id)
    g_menu_ballot[id] = ballot
    menu_display(id, menu)
}

stock safe_player_name(id, output[], length)
{
    get_user_name(id, output, length)
    for (new i = 0; output[i]; i++)
        if (output[i] < 32 || output[i] > 126 || output[i] == 92 || output[i] == '%' || output[i] == 94) output[i] = '_'
}

public command_status()
{
    server_print("KGB Player Hub %s: mode=%d maps=%d vote=%d pending=%d", VERSION, hub_mode(), g_map_count, g_vote_active, g_map_pending)
}
