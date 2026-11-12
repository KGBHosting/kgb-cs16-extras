// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 KGB Hosting
#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fun>
#include <fakemeta>
#include <hamsandwich>

#define VERSION "0.1.0"
#define TASK_LOADOUT 42300
#define MAX_CLIENTS 32
#define NO_MENU -1

new const LOADOUT_LABELS[][] = { "M4A1 + USP", "AK-47 + Desert Eagle", "MP5 Navy + USP", "M3 + Desert Eagle", "Scout + USP", "AWP + Desert Eagle" }
new const PRIMARY_ENTITIES[][] = { "weapon_m4a1", "weapon_ak47", "weapon_mp5navy", "weapon_m3", "weapon_scout", "weapon_awp" }
new const SECONDARY_ENTITIES[][] = { "weapon_usp", "weapon_deagle", "weapon_usp", "weapon_deagle", "weapon_usp", "weapon_deagle" }
new const PRIMARY_IDS[] = { CSW_M4A1, CSW_AK47, CSW_MP5NAVY, CSW_M3, CSW_SCOUT, CSW_AWP }
new const SECONDARY_IDS[] = { CSW_USP, CSW_DEAGLE, CSW_USP, CSW_DEAGLE, CSW_USP, CSW_DEAGLE }

new g_enabled, g_allow_awp, g_heal, g_headshots, g_auto_menu
new g_mode_pointer, g_maxplayers
new g_choice[MAX_CLIENTS + 1], bool:g_has_choice[MAX_CLIENTS + 1], bool:g_equipped[MAX_CLIENTS + 1]
new g_life[MAX_CLIENTS + 1], g_task_life[MAX_CLIENTS + 1], g_task_userid[MAX_CLIENTS + 1]
new g_menu[MAX_CLIENTS + 1], g_menu_life[MAX_CLIENTS + 1], g_menu_userid[MAX_CLIENTS + 1]

public plugin_init()
{
    register_plugin("KGB Deathmatch Loadouts", VERSION, "KGB Hosting")
    register_cvar("kgb_dm_loadout_version", VERSION, FCVAR_SERVER | FCVAR_SPONLY)
    g_enabled = register_cvar("kgb_dm_loadouts", "1")
    g_allow_awp = register_cvar("kgb_dm_allow_awp", "0")
    g_heal = register_cvar("kgb_dm_kill_heal", "0")
    g_headshots = register_cvar("kgb_dm_headshots_only", "0")
    g_auto_menu = register_cvar("kgb_dm_auto_menu", "1")
    g_maxplayers = get_maxplayers()
    for (new id = 0; id <= MAX_CLIENTS; id++) g_menu[id] = NO_MENU
    register_clcmd("say /guns", "command_guns")
    register_clcmd("say_team /guns", "command_guns")
    register_event("DeathMsg", "on_death", "a")
    RegisterHam(Ham_Spawn, "player", "on_spawn", 1)
    RegisterHam(Ham_TraceAttack, "player", "on_trace_attack")
    register_srvcmd("kgb_dm_loadout_status", "command_status")
}

public plugin_cfg()
{
    g_mode_pointer = get_cvar_pointer("kgb_extras_mode")
    new dir[128]
    get_configsdir(dir, charsmax(dir))
    server_cmd("exec %s/kgb_deathmatch_loadout.cfg", dir)
    server_exec()
}

stock bool:dm_active()
{
    if (!g_mode_pointer || !get_pcvar_num(g_enabled)) return false
    new mode[24]
    get_pcvar_string(g_mode_pointer, mode, charsmax(mode))
    if (!equal(mode, "deathmatch")) return false
    // Refuse a configuration mismatch instead of arming another core mode.
    return get_cvar_num("mp_freeforall") == 1 && get_cvar_float("mp_forcerespawn") > 0.0
}

stock bool:human_player(id)
{
    return combat_player(id) && !is_user_bot(id)
}

stock bool:combat_player(id)
{
    if (id < 1 || id > g_maxplayers || !is_user_connected(id) || is_user_hltv(id)) return false
    new CsTeams:team = cs_get_user_team(id)
    return team == CS_TEAM_T || team == CS_TEAM_CT
}

public client_putinserver(id) { reset_client(id); }
#if AMXX_VERSION_NUM < 183
public client_disconnect(id) { reset_client(id); }
#else
public client_disconnected(id) { reset_client(id); }
#endif

public plugin_end()
{
    for (new id = 1; id <= g_maxplayers; id++)
    {
        close_loadout_menu(id)
        remove_task(TASK_LOADOUT + id)
    }
}

stock reset_client(id)
{
    remove_task(TASK_LOADOUT + id)
    close_loadout_menu(id)
    g_choice[id] = 0
    g_has_choice[id] = false
    g_equipped[id] = false
    g_life[id]++
    g_task_userid[id] = 0
}

public on_spawn(id)
{
    remove_task(TASK_LOADOUT + id)
    close_loadout_menu(id)
    g_life[id]++
    g_equipped[id] = false
    if (!dm_active() || !human_player(id) || !is_user_alive(id)) return
    g_task_life[id] = g_life[id]
    g_task_userid[id] = get_user_userid(id)
    set_task(0.3, "task_loadout", TASK_LOADOUT + id)
}

public task_loadout(task)
{
    new id = task - TASK_LOADOUT
    if (!dm_active() || !human_player(id) || !is_user_alive(id) || g_task_life[id] != g_life[id] || g_task_userid[id] != get_user_userid(id)) return
    if (g_has_choice[id]) equip_loadout(id)
    else if (get_pcvar_num(g_auto_menu))
    {
        new old_menu, new_menu
        if (!player_menu_info(id, old_menu, new_menu)) command_guns(id)
        else client_print(id, print_chat, "[Deathmatch] Type /guns to choose and remember a loadout.")
    }
}

public command_guns(id)
{
    if (!dm_active() || !human_player(id)) return PLUGIN_CONTINUE
    new title[128]
    formatex(title, charsmax(title), "Deathmatch loadout^n%s", g_equipped[id] || !is_user_alive(id) ? "Your choice applies on the next spawn" : "Choose once for this life; remembers until disconnect")
    new menu = menu_create(title, "loadout_handler")
    for (new i = 0; i < sizeof PRIMARY_IDS; i++)
    {
        if (i == sizeof PRIMARY_IDS - 1 && !get_pcvar_num(g_allow_awp)) continue
        new info[8]
        num_to_str(i, info, charsmax(info))
        menu_additem(menu, LOADOUT_LABELS[i], info)
    }
    close_loadout_menu(id)
    g_menu[id] = menu
    g_menu_life[id] = g_life[id]
    g_menu_userid[id] = get_user_userid(id)
    menu_display(id, menu)
    return PLUGIN_HANDLED
}

public loadout_handler(id, menu, item)
{
    if (g_menu[id] != menu) return PLUGIN_HANDLED
    new bool:valid = is_user_connected(id) && g_menu_userid[id] == get_user_userid(id) && g_menu_life[id] == g_life[id]
    new info[8], name[1], access, callback
    if (item != MENU_EXIT) menu_item_getinfo(menu, item, access, info, charsmax(info), name, 0, callback)
    g_menu[id] = NO_MENU
    menu_destroy(menu)
    if (item == MENU_EXIT || !valid || !dm_active() || !human_player(id)) return PLUGIN_HANDLED
    new choice = str_to_num(info)
    if (choice < 0 || choice >= sizeof PRIMARY_IDS || (choice == sizeof PRIMARY_IDS - 1 && !get_pcvar_num(g_allow_awp))) return PLUGIN_HANDLED
    g_choice[id] = choice
    g_has_choice[id] = true
    if (!g_equipped[id] && is_user_alive(id)) equip_loadout(id)
    else client_print(id, print_chat, "[Deathmatch] Loadout remembered for your next spawn.")
    return PLUGIN_HANDLED
}

stock close_loadout_menu(id)
{
    if (g_menu[id] == NO_MENU) return
    new menu = g_menu[id], old_menu, current
    g_menu[id] = NO_MENU
    if (is_user_connected(id))
    {
        if (player_menu_info(id, old_menu, current) && current == menu)
        {
            menu_cancel(id)
            show_menu(id, 0, "^n", 1)
        }
    }
    menu_destroy(menu)
}

stock equip_loadout(id)
{
    if (!dm_active() || !human_player(id) || !is_user_alive(id) || g_equipped[id]) return
    new choice = clamp(g_choice[id], 0, sizeof PRIMARY_IDS - 1)
    if (choice == sizeof PRIMARY_IDS - 1 && !get_pcvar_num(g_allow_awp)) { choice = 0; g_choice[id] = 0; }
    strip_user_weapons(id)
    give_item(id, "weapon_knife")
    give_item(id, PRIMARY_ENTITIES[choice])
    give_item(id, SECONDARY_ENTITIES[choice])
    cs_set_user_bpammo(id, PRIMARY_IDS[choice], 200)
    cs_set_user_bpammo(id, SECONDARY_IDS[choice], 200)
    g_equipped[id] = true
}

public on_death()
{
    new victim = read_data(2)
    if (victim >= 1 && victim <= g_maxplayers)
    {
        remove_task(TASK_LOADOUT + victim)
        close_loadout_menu(victim)
        g_life[victim]++
    }
    new killer = read_data(1), heal = clamp(get_pcvar_num(g_heal), 0, 25)
    if (!heal || !dm_active() || killer == victim || !human_player(killer) || !is_user_alive(killer)) return
    new health = get_user_health(killer)
    if (health < 100) set_user_health(killer, min(100, health + heal))
}

public on_trace_attack(victim, attacker, Float:damage, Float:direction[3], trace, damage_bits)
{
    if (!dm_active() || !get_pcvar_num(g_headshots) || victim == attacker || !combat_player(attacker)
        || !is_user_alive(attacker) || !(damage_bits & DMG_BULLET) || get_user_weapon(attacker) == CSW_KNIFE) return HAM_IGNORED
    return get_tr2(trace, TR_iHitgroup) == HIT_HEAD ? HAM_IGNORED : HAM_SUPERCEDE
}

public command_status()
{
    server_print("KGB Deathmatch Loadouts %s: active=%d awp=%d kill_heal=%d headshot_bullets=%d", VERSION, dm_active(), get_pcvar_num(g_allow_awp) != 0, clamp(get_pcvar_num(g_heal), 0, 25), get_pcvar_num(g_headshots) != 0)
}
