// SPDX-License-Identifier: GPL-3.0-or-later
// Original KGB Hosting map voting; only validated installed mapcycle entries.
#define HUB_MAX_MAPS 64
#define HUB_VOTE_CHOICES 5
new g_maps[HUB_MAX_MAPS][32], g_map_count
new g_votes_enabled, g_vote_fraction, g_vote_min_players, g_vote_wait, g_vote_duration, g_map_wait
new bool:g_rtv[MAX_CLIENTS + 1], g_nomination[MAX_CLIENTS + 1]
new bool:g_vote_active, bool:g_map_pending
new g_vote_epoch, g_vote_eligible, g_vote_choices[HUB_VOTE_CHOICES], g_choice_count
new g_ballot_userid[MAX_CLIENTS + 1], g_ballot[MAX_CLIENTS + 1]
new g_pending_index, HubMode:g_pending_mode
new Float:g_vote_after

stock votes_init()
{
    g_votes_enabled = register_cvar("kgb_hub_map_votes", "1")
    g_vote_fraction = register_cvar("kgb_hub_rtv_fraction", "0.60")
    g_vote_min_players = register_cvar("kgb_hub_rtv_min_players", "2")
    g_vote_wait = register_cvar("kgb_hub_rtv_wait", "180")
    g_vote_duration = register_cvar("kgb_hub_vote_duration", "15")
    g_map_wait = register_cvar("kgb_hub_map_wait", "900")
    register_clcmd("say /rtv", "command_rtv")
    register_clcmd("say_team /rtv", "command_rtv")
    register_clcmd("say /nominate", "command_nominate")
    register_clcmd("say_team /nominate", "command_nominate")
    register_clcmd("say /vote", "command_vote")
    register_clcmd("say_team /vote", "command_vote")
    register_logevent("hub_round_end", 2, "1=Round_End")
    for (new id = 0; id <= MAX_CLIENTS; id++) votes_reset_client(id)
}

stock bool:votes_allowed()
{
    new HubMode:mode = hub_mode()
    return get_pcvar_num(g_votes_enabled) != 0
        && (mode == MODE_PUBLIC || mode == MODE_DEATHMATCH || mode == MODE_ZOMBIE)
}

stock votes_reset_client(id)
{
    g_rtv[id] = false
    g_nomination[id] = -1
    g_ballot_userid[id] = 0
    g_ballot[id] = -1
}

stock bool:map_token_safe(const name[])
{
    new length = strlen(name)
    if (!length || length > 31) return false
    for (new i = 0; i < length; i++)
        if (!((name[i] >= 'a' && name[i] <= 'z') || (name[i] >= 'A' && name[i] <= 'Z')
            || (name[i] >= '0' && name[i] <= '9') || name[i] == '_' || name[i] == '-')) return false
    return true
}

stock bool:cycle_filename_safe(const name[])
{
    new length = strlen(name)
    if (length < 5 || length > 63 || contain(name, "..") != -1 || !equal(name[length - 4], ".txt")) return false
    for (new i = 0; i < length; i++)
        if (!((name[i] >= 'a' && name[i] <= 'z') || (name[i] >= 'A' && name[i] <= 'Z')
            || (name[i] >= '0' && name[i] <= '9') || name[i] == '_' || name[i] == '-' || name[i] == '.')) return false
    return true
}

// Read the entire first token before accepting it: never accept a truncated
// prefix of a longer map name. Engine mapcycles accept spaces and tabs.
stock cycle_map_token(const line[], token[], limit)
{
    if (limit < 1 || limit > 31) return 0
    new length = 0
    while (line[length] && line[length] != 32 && line[length] != 9)
    {
        if (length >= limit) { token[0] = 0; return 0; }
        token[length] = line[length]
        length++
    }
    token[length] = 0
    return length
}

stock votes_load_cycle()
{
    g_vote_after = get_gametime() + float(clamp(get_pcvar_num(g_vote_wait), 0, 3600))
    new filename[128], line[128], token[32], current[32]
    get_cvar_string("mapcyclefile", filename, charsmax(filename))
    if (!cycle_filename_safe(filename)) { log_amx("Map voting disabled: mapcyclefile must be a root .txt filename."); return; }
    new file = fopen(filename, "rt")
    if (!file) return
    get_mapname(current, charsmax(current))
    new lines
    while (!feof(file) && g_map_count < HUB_MAX_MAPS && lines++ < 512)
    {
        fgets(file, line, charsmax(line))
        if (strlen(line) >= charsmax(line)) { g_map_count = 0; break; }
        trim(line)
        if (!line[0] || line[0] == ';' || line[0] == '#' || line[0] == '/') continue
        if (!cycle_map_token(line, token, charsmax(token)) || !map_token_safe(token) || !is_map_valid(token) || equali(token, current)) continue
        new bool:duplicate
        for (new i = 0; i < g_map_count; i++) if (equali(g_maps[i], token)) duplicate = true
        if (!duplicate) copy(g_maps[g_map_count++], charsmax(g_maps[]), token)
    }
    fclose(file)
}

public command_nominate(id)
{
    if (!hub_player(id) || !votes_allowed()) return PLUGIN_CONTINUE
    if (!g_map_count || g_vote_active || g_map_pending)
    { client_print(id, print_chat, "[Maps] Nominations are unavailable while a vote/map change is pending, or no alternative maps are installed."); return PLUGIN_HANDLED; }
    new menu = menu_create("Nominate an installed map", "nomination_handler")
    for (new i = 0; i < g_map_count; i++)
    {
        new info[12]
        num_to_str(i, info, charsmax(info))
        menu_additem(menu, g_maps[i], info)
    }
    hub_show_menu(id, menu)
    return PLUGIN_HANDLED
}

public nomination_handler(id, menu, item)
{
    if (!hub_owns_menu(id, menu)) return PLUGIN_HANDLED
    if (item == MENU_EXIT) { hub_release_menu(id, menu); return PLUGIN_HANDLED; }
    new info[12], name[1], access, callback
    menu_item_getinfo(menu, item, access, info, charsmax(info), name, 0, callback)
    hub_release_menu(id, menu)
    new index = str_to_num(info)
    if (!hub_player(id) || !votes_allowed() || g_vote_active || g_map_pending || index < 0 || index >= g_map_count || !is_map_valid(g_maps[index])) return PLUGIN_HANDLED
    g_nomination[id] = index
    client_print(id, print_chat, "[Maps] Nominated %s. Your latest choice replaces your previous nomination.", g_maps[index])
    return PLUGIN_HANDLED
}

public command_rtv(id)
{
    if (!hub_player(id) || !votes_allowed()) return PLUGIN_CONTINUE
    if (g_vote_active) return command_vote(id)
    if (g_map_pending || !g_map_count) { client_print(id, print_chat, "[Maps] A map change is pending or no alternative installed maps are available."); return PLUGIN_HANDLED; }
    if (get_gametime() < g_vote_after)
    { client_print(id, print_chat, "[Maps] Rock the vote opens in %d seconds.", floatround(g_vote_after - get_gametime(), floatround_ceil)); return PLUGIN_HANDLED; }
    new count, requests
    for (new p = 1; p <= g_maxplayers; p++)
        if (hub_player(p)) { count++; if (g_rtv[p]) requests++; }
    new minimum = clamp(get_pcvar_num(g_vote_min_players), 2, MAX_CLIENTS)
    if (count < minimum) { client_print(id, print_chat, "[Maps] At least %d human players are required.", minimum); return PLUGIN_HANDLED; }
    if (!g_rtv[id]) { g_rtv[id] = true; requests++; }
    new Float:fraction = get_pcvar_float(g_vote_fraction)
    if (!(fraction >= 0.50 && fraction <= 1.0)) fraction = 0.60
    new required = floatround(float(count) * fraction, floatround_ceil)
    client_print(id, print_chat, "[Maps] %d of %d required players requested a vote.", requests, required)
    if (requests >= required) votes_start()
    return PLUGIN_HANDLED
}

stock votes_start()
{
    if (!votes_allowed() || g_vote_active || g_map_pending) return
    new nomination_count[HUB_MAX_MAPS], chosen[HUB_MAX_MAPS]
    for (new id = 1; id <= g_maxplayers; id++)
        if (hub_player(id) && g_nomination[id] >= 0 && g_nomination[id] < g_map_count) nomination_count[g_nomination[id]]++
    g_choice_count = 0
    for (new c = 0; c < min(g_map_count, HUB_VOTE_CHOICES); c++)
    {
        new best = -1
        for (new m = 0; m < g_map_count; m++)
            if (!chosen[m] && is_map_valid(g_maps[m]) && (best < 0 || nomination_count[m] > nomination_count[best])) best = m
        if (best < 0) break
        chosen[best] = 1
        g_vote_choices[g_choice_count++] = best
    }
    if (!g_choice_count) return
    g_vote_epoch++
    g_vote_active = true
    g_pending_mode = hub_mode()
    g_vote_eligible = 0
    for (new id = 1; id <= g_maxplayers; id++)
    {
        g_rtv[id] = false
        g_ballot[id] = -1
        g_ballot_userid[id] = hub_player(id) ? get_user_userid(id) : 0
        if (g_ballot_userid[id]) g_vote_eligible++
    }
    client_print(0, print_chat, "[Maps] Map vote started. Type /vote to choose a map or keep playing this one. A majority of eligible humans must vote for a change.")
    for (new id = 1; id <= g_maxplayers; id++)
    {
        new old_menu, new_menu
        if (g_ballot_userid[id] && !player_menu_info(id, old_menu, new_menu)) command_vote(id)
    }
    set_task(float(clamp(get_pcvar_num(g_vote_duration), 10, 30)), "votes_finish", TASK_VOTE_END)
}

public command_vote(id)
{
    if (!hub_player(id) || !votes_allowed()) return PLUGIN_CONTINUE
    if (!g_vote_active || g_pending_mode != hub_mode() || g_ballot_userid[id] != get_user_userid(id) || g_ballot[id] >= 0)
    { client_print(id, print_chat, "[Maps] No eligible ballot is available, or you already voted."); return PLUGIN_HANDLED; }
    new menu = menu_create("Choose next map", "ballot_handler"), info[24]
    for (new c = 0; c < g_choice_count; c++)
    {
        formatex(info, charsmax(info), "%d %d", g_vote_epoch, c)
        menu_additem(menu, g_maps[g_vote_choices[c]], info)
    }
    formatex(info, charsmax(info), "%d %d", g_vote_epoch, g_choice_count)
    menu_additem(menu, "Keep playing this map", info)
    hub_show_menu(id, menu, true)
    return PLUGIN_HANDLED
}

public ballot_handler(id, menu, item)
{
    if (!hub_owns_menu(id, menu)) return PLUGIN_HANDLED
    if (item == MENU_EXIT) { hub_release_menu(id, menu); return PLUGIN_HANDLED; }
    new info[24], name[1], access, callback, epoch[12], choice[12]
    menu_item_getinfo(menu, item, access, info, charsmax(info), name, 0, callback)
    hub_release_menu(id, menu)
    parse(info, epoch, charsmax(epoch), choice, charsmax(choice))
    new selected = str_to_num(choice)
    if (!hub_player(id) || !votes_allowed() || !g_vote_active || g_pending_mode != hub_mode()
        || str_to_num(epoch) != g_vote_epoch || g_ballot_userid[id] != get_user_userid(id)
        || g_ballot[id] >= 0 || selected < 0 || selected > g_choice_count) return PLUGIN_HANDLED
    g_ballot[id] = selected
    client_print(id, print_chat, "[Maps] Your ballot is recorded.")
    return PLUGIN_HANDLED
}

public votes_finish()
{
    if (!g_vote_active) return
    g_vote_active = false
    for (new id = 1; id <= g_maxplayers; id++) if (g_menu_ballot[id]) hub_close_menu(id)
    g_vote_after = get_gametime() + float(max(30, clamp(get_pcvar_num(g_vote_wait), 0, 3600)))
    if (!votes_allowed() || hub_mode() != g_pending_mode) return
    new totals[HUB_VOTE_CHOICES + 1]
    for (new id = 1; id <= g_maxplayers; id++)
        if (hub_player(id) && g_ballot_userid[id] == get_user_userid(id) && g_ballot[id] >= 0 && g_ballot[id] <= g_choice_count)
        totals[g_ballot[id]]++
    new best = approved_map_choice(totals, g_choice_count, g_vote_eligible)
    if (best < 0)
    { client_print(0, print_chat, "[Maps] No change approved. This map continues."); return; }
    g_pending_index = g_vote_choices[best]
    if (!is_map_valid(g_maps[g_pending_index])) return
    g_map_pending = true
    if (g_pending_mode == MODE_DEATHMATCH)
    {
        client_print(0, print_chat, "[Maps] %s won. Changing in five seconds.", g_maps[g_pending_index])
        set_task(5.0, "votes_change_map", TASK_MAP_CHANGE)
    }
    else
    {
        // Waiting/infinite rounds must never lock future nominations forever.
        // Never cut a live round merely because this deadline elapsed.
        new wait = clamp(get_pcvar_num(g_map_wait), 30, 1800)
        set_task(float(wait), "votes_pending_expired", TASK_MAP_EXPIRY)
        client_print(0, print_chat, "[Maps] %s won. Changing at round end; cancelled if no round ends within %d seconds.", g_maps[g_pending_index], wait)
    }
}

// Pure tally policy, shared with executable source-extraction regression tests.
stock approved_map_choice(const totals[], choices, electorate)
{
    if (choices < 1 || choices > HUB_VOTE_CHOICES || electorate < 2 || electorate > MAX_CLIENTS) return -1
    new cast = 0, best = 0
    for (new c = 0; c <= choices; c++)
    {
        if (totals[c] < 0) return -1
        cast += totals[c]
        if (totals[c] > totals[best]) best = c
    }
    // Fixed start-of-vote electorate: departures cannot lower the majority.
    if (cast > electorate || cast - totals[choices] <= electorate / 2 || best == choices || !totals[best] || totals[best] <= totals[choices]) return -1
    // A tied map result fails closed rather than favoring mapcycle order.
    for (new c = 0; c < choices; c++) if (c != best && totals[c] == totals[best]) return -1
    return best
}

public hub_round_end()
{
    // Queue at the real boundary; a fixed delay could cut into the next round.
    if (g_map_pending && g_pending_mode != MODE_DEATHMATCH) votes_change_map()
}

public votes_pending_expired()
{
    if (!g_map_pending) return
    g_map_pending = false
    client_print(0, print_chat, "[Maps] No round ended before the map-vote deadline. This map continues; normal nomination and voting cooldown rules apply.")
}

public votes_change_map()
{
    remove_task(TASK_MAP_EXPIRY)
    if (!g_map_pending || !votes_allowed() || hub_mode() != g_pending_mode) { g_map_pending = false; return; }
    g_map_pending = false
    if (g_pending_index >= 0 && g_pending_index < g_map_count && map_token_safe(g_maps[g_pending_index]) && is_map_valid(g_maps[g_pending_index]))
        server_cmd("changelevel %s", g_maps[g_pending_index])
}
