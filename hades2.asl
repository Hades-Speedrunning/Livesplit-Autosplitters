/*
    Credits
        Sebastien S. (SystemFailu.re) : Creating main script, reversing engine.
        ellomenop : Doing original splits, helping test & misc. bug fixes.
        Museus: Routed, midbiome, enter boss arena, overhaul of logic and sig scanning
        cgull: House splits + splits on boss kill, revamp for Hades II.
        iDeathHD: solved the 23 length string crisis of 2024
*/

state("Hades2")
{
    /*
        There's nothing here because I don't want to use static instance addresses..
        Please refer to `init` to see the signature scanning.
    */
}

startup
{
    vars.Log = (Action<object>)((output) => print("[Hades 2 ASL] " + output));
    vars.InitComplete = false;

    settings.Add("multiWep", false, "Multi Weapon Run");
    settings.Add("houseSplits", false, "Use Crossroads Splits", "multiWep");
    settings.Add("enterBossArena", false, "Split when entering boss arena");
    settings.Add("splitOnBossKill", false, "Split on Boss Kills");
    settings.Add("midbiome", false, "Split when exiting inter-biome");
    settings.Add("routed", false, "Routed (per chamber)");
}

init
{
    vars.InitComplete = false;
    vars.CancelSource = new CancellationTokenSource();
    vars.quick_restart_mod = false;

    System.Threading.Tasks.Task.Run(async () =>
    {
        task_start: try {
            while (true)
            {
                // DX = EngineWin64s.dll, VK = EngineWin64sv.dll
                // Have to use game.ModulesWow64Safe() because modules variable doesn't update inside Tasks
                var engine = game.ModulesWow64Safe().FirstOrDefault(x => x.ModuleName.StartsWith("Hades2"));
                if (engine == null){
                    vars.Log("Engine not loaded yet, trying again.");
                    await System.Threading.Tasks.Task.Delay(1000, vars.CancelSource.Token);
                    continue;
                }
                vars.Log("Found engine!");

                var signature_scanner = new SignatureScanner(game, engine.BaseAddress, engine.ModuleMemorySize);

                /* Signatures */
                var app_signature_target = new SigScanTarget(3, "48 8B 05 ?? ?? ?? ?? 48 8B B8 ?? ?? ?? ?? 48 8B 4F"); // rip = 7
                var world_signature_target = new SigScanTarget(3, "48 8B 05 ?? ?? ?? ?? 48 8D 8E ?? ?? ?? ?? 33 D2");
                var player_manager_signature_target = new SigScanTarget(3, "48 8B 15 ?? ?? ?? ?? 48 FF C3 E9 ?? ?? ?? ?? 0F 29 74 24");

                var signature_targets = new [] {
                    app_signature_target,
                    world_signature_target,
                    player_manager_signature_target,
                };

                foreach (var target in signature_targets) {
                    target.OnFound = (process, _, pointer) => process.ReadPointer(pointer + 0x4 + process.ReadValue<int>(pointer));
                }

                IntPtr app = signature_scanner.Scan(app_signature_target);
                vars.world = signature_scanner.Scan(world_signature_target);
                IntPtr player_manager = signature_scanner.Scan(player_manager_signature_target);

                vars.screen_manager = game.ReadPointer(app + 0x4F8); // 48 8B 8F ? ? ? ? E8 ? ? ? ? 48 8B D8 48 85 C0 0F 84 ? ? ? ? 48 8B 88
                vars.current_player = game.ReadPointer(game.ReadPointer(player_manager + 0x18));
                // vars.current_block_count = game.ReadValue<int>((IntPtr)vars.current_player + 0x50);

                vars.InitComplete = true;
                break;
            }

            vars.CancelSource.Cancel();
        }
        catch (ArgumentException) {
            // Hopefully will be fixed by https://github.com/LiveSplit/LiveSplit/pull/2203
            goto task_start;
        }
        catch (Exception ex) {
            vars.Log("Task abort.\n" + ex);
        }
    });

    current.run_time = "0:0.1";
    current.map = "";

    current.total_seconds = 0.5f;
    old.total_seconds = 0.5f;

    vars.time_split = current.run_time.Split(':', '.');
    vars.has_beat_final_boss = false;
    vars.boss_killed = false;
    vars.exit_to_chronos = false;
    vars.chronos_phased = false;

    vars.still_in_arena = false;

    vars.game_ui = IntPtr.Zero;
    vars.block_history = new string[4];

    // Chambers
    vars.HUB_PRE_RUN = "Hub_PreRun";

    // Openings
    vars.EREBUS_OPENING_01 = "F_Opening01";
    vars.EREBUS_OPENING_02 = "F_Opening02";
    vars.EREBUS_OPENING_03 = "F_Opening03";
    vars.EPHYRA_OPENING_01 = "N_Opening01";

    // MiniBosses
    vars.KING_VERMIN_ARENA = "G_MiniBoss02";
    vars.CHARYBDIS_ARENA = "O_MiniBoss01";
    vars.TALOS_ARENA = "P_MiniBoss01";

    // Bosses
    vars.HECATE_ARENA = "F_Boss01";
    vars.SIRENS_ARENA = "G_Boss01";
    vars.CERBERUS_ARENA = "H_Boss01";
    vars.CHRONOS_ARENA = "I_Boss01";
    vars.POLYPHEMUS_ARENA = "N_Boss01";
    vars.ERIS_ARENA = "O_Boss01";
    vars.PROMETHEUS_ARENA = "P_Boss01";

    // Post-Boss
    vars.HECATE_POST_BOSS = "F_PostBoss01";
    vars.SIRENS_POST_BOSS = "G_PostBoss01";
    vars.CERBERUS_POST_BOSS = "H_PostBoss01";
    vars.POLYPHEMUS_POST_BOSS = "N_PostBoss01";
    vars.ERIS_POST_BOSS = "O_PostBoss01";
    vars.PROMETHEUS_POST_BOSS = "P_PostBoss01";
}

update
{
    if (!(vars.InitComplete))
        return false;


    IntPtr hash_table = game.ReadPointer((IntPtr) vars.current_player + 0x48);
    for(int i = 0; i < 4; i++)
    {
        IntPtr block = game.ReadPointer(hash_table + 0x8 * i);
        if(block == IntPtr.Zero)
            continue;

        string block_name = "";

        bool isSSOString = (game.ReadValue<byte>(block + 23) & 0x80) == 0;
        if (isSSOString)
        {
            block_name = game.ReadString(block, 24);

            if (block_name == null)
                continue;

            //vars.Log("(update) sso block_name: " + block_name);
        }
        else
        {
            block = game.ReadPointer(block);
            block_name = game.ReadString(block, 128);
            
            if (block_name == null)
                continue;

            //vars.Log("(update) block_name: " + block_name);
        }

        /*
        Ugly, but this reduces some duplicate blocks from detecting & showing in the logs.
        There are still some duplicates, but much better than without.
        */
        // Ignore 3 in a row
        if (block_name == vars.block_history[0] && block_name == vars.block_history[1])
            continue;

        // Ignore when it starts to alternate - ABAB -> A dissallowed
        if (block_name == vars.block_history[1] && block_name == vars.block_history[3] &&
            vars.block_history[0] == vars.block_history[2])
            continue;

        // Ignore when it starts to alternate-ish - ABAB -> B dissallowed
        if (block_name == vars.block_history[0] && block_name == vars.block_history[2] &&
            vars.block_history[1] == vars.block_history[3])
            continue;

        // Update history
        vars.block_history[3] = vars.block_history[2];
        vars.block_history[2] = vars.block_history[1];
        vars.block_history[1] = vars.block_history[0];
        vars.block_history[0] = block_name;

        vars.Log("(update) Encountered block: " + block_name);

        var boss_killed_block = block_name == "GenericBossKillPresentation" || block_name == "HecateKillPresentation";
        var ignored_boss_map = (
            current.map == vars.KING_VERMIN_ARENA ||
            current.map == vars.CHARYBDIS_ARENA ||
            current.map == vars.TALOS_ARENA ||
            current.map == vars.CHRONOS_ARENA ||
            current.map == vars.PROMETHEUS_ARENA
        );

        // Ignore mini-bosses that trigger GenericBossKillPresentation, and Chronos/Prometheus
        if (!vars.boss_killed && boss_killed_block && !ignored_boss_map)
        {
            vars.Log("(update) Detected boss kill");
            vars.boss_killed = true;
        }

        if (!vars.chronos_phased && block_name == "ChronosPhaseTransition")
        {
            vars.Log("(update) Detected chronos phased");
            vars.chronos_phased = true;
        }

        if (!vars.has_beat_final_boss && 
            (block_name == "PlayTextLines" && vars.chronos_phased || block_name == "PrometheusKillPresentation"))
        {
            vars.Log("(update) Detected Chronos/Prometheus kill");
            vars.has_beat_final_boss = true;
        }

        if (!vars.exit_to_chronos && block_name == "LeaveRoomIPreBossPresentation")
        {
            vars.Log("(update) Detected sand dive");
            vars.exit_to_chronos = true;
        }
    }


    // Get the array of screen IntPtrs and iterate to find InGameUI screen
    if (vars.screen_manager != IntPtr.Zero)
    {
        IntPtr screen_vector_begin = game.ReadPointer((IntPtr)vars.screen_manager + 0x48);
        IntPtr screen_vector_end = game.ReadPointer((IntPtr)vars.screen_manager + 0x50);

        // 64-bit IntPtr are 8 bytes each, so divide by 8 to get number of screens
        var num_screens = (screen_vector_end.ToInt64() - screen_vector_begin.ToInt64()) / 8;

        // Maybe only loop once to find game_ui, not sure if pointer is destructed anytime.
        for (int i = 0; i < num_screens; i++)
        {
            IntPtr current_screen = game.ReadPointer(screen_vector_begin + 0x8 * i);
            if (current_screen == IntPtr.Zero)
                continue;

            IntPtr screen_vtable = game.ReadPointer(current_screen); // Deref to get vtable
            IntPtr get_type_method = game.ReadPointer(screen_vtable + 0x50); // Unlikely to change <--- I lied

            int screen_type = game.ReadValue<int>(get_type_method + 0x1);

            // InGameUI is screen type 7
            if ((screen_type & 0x7) == 7) {
                vars.game_ui = current_screen;
                break;
            }
        }
    }


    /* Get our current run time */
    if (vars.game_ui != IntPtr.Zero)
    {
        IntPtr runtime_component = game.ReadPointer((IntPtr)vars.game_ui + 0x2F8); // Possible to change if they adjust the UI class
        if (runtime_component != IntPtr.Zero)
        {
            /* This might break if the run goes over 99 minutes T_T */
            current.run_time = game.ReadString(game.ReadPointer(runtime_component + 0x6A8), 0x8); // 48 8D 8E ? ? ? ? 48 8D 05 ? ? ? ? 4C 8B C0 66 0F 1F 44 00
            if (current.run_time == "PauseScr")
                current.run_time = "0:0.10";
        }
    }

    /* Get our current map name */
    if(vars.world != IntPtr.Zero)
    {
        IntPtr map_data = game.ReadPointer((IntPtr)vars.world + 0x90); // 0x70 + 0x20
        if(map_data != IntPtr.Zero)
            current.map = game.ReadString(map_data, 0x10);
            if (current.map != old.map)
                vars.Log("(update) Map change: " + old.map + " -> " + current.map);

            if (vars.still_in_arena && current.map != old.map)
            {
                vars.still_in_arena = false;
                vars.boss_killed = false;
                vars.has_beat_final_boss = false;
                vars.exit_to_chronos = false;
            }
    }

    vars.time_split = current.run_time.Split(':', '.');
    /* Convert the string time to singles */
    current.total_seconds =
        int.Parse(vars.time_split[0]) * 60 +
        int.Parse(vars.time_split[1]) +
        float.Parse(vars.time_split[2]) / 100;
}

onStart
{
    vars.boss_killed = false;
    vars.has_beat_final_boss = false;
    vars.exit_to_chronos = false;
    vars.still_in_arena = false;
}

start
{
    // Start the timer if in the first room and the old timer is greater than the new (memory address holds the value from the previous run)
    // Apparently we can't use .Contains in ASL
    var is_opening_chamber = (
        current.map == vars.EREBUS_OPENING_01 ||
        current.map == vars.EREBUS_OPENING_02 ||
        current.map == vars.EREBUS_OPENING_03 ||
        current.map == vars.EPHYRA_OPENING_01
    );
    if (old.total_seconds > current.total_seconds && is_opening_chamber)
    {
        return true;
    }
}

onSplit
{
    vars.boss_killed = false;
    vars.has_beat_final_boss = false;
    vars.chronos_phased = false;
    vars.exit_to_chronos = false;
}

split
{
    // Split on Chronos/Prometheus Kill
    if (!vars.still_in_arena && vars.has_beat_final_boss)
    {
        vars.Log("(split) Splitting for Chronos/Prometheus kill");

        // Disable boss kill detection until we leave the boss arena
        vars.still_in_arena = true;
        vars.Log(current.run_time + " (split) Splitting for Chronos/Prometheus kill");
        return true;
    }

    var entered_new_room = current.map != old.map;

    // Split on Boss Kill
    if (settings["splitOnBossKill"] && !vars.still_in_arena && (vars.boss_killed || vars.exit_to_chronos))
    {
        // Disable boss kill detection until we leave the boss arena
        vars.still_in_arena = true;

        vars.Log(current.run_time + " (splitOnBossKill) Splitting for sand dive or boss kill");
        return true;
    }

    // Split on run start if Crossroads Splits are enabled
    if (settings["multiWep"] && settings["houseSplits"] && current.map == vars.HUB_PRE_RUN && (old.total_seconds > current.total_seconds))
    {
        vars.Log(current.run_time + " (multiWep && houseSplits) Splitting for house split");
        return true;
    }

    if (entered_new_room)
    {
        // Split every chamber if Routed is enabled
        if (settings["routed"])
        {
            vars.Log(current.run_time +" (routed) Splitting for chamber transition: " + old.map + " -> " + current.map);
            return true;
        }

        // Split on room transition
        var in_post_boss_room = (
            current.map == vars.HECATE_POST_BOSS ||
            current.map == vars.SIRENS_POST_BOSS ||
            current.map == vars.CERBERUS_POST_BOSS ||
            current.map == vars.POLYPHEMUS_POST_BOSS ||
            current.map == vars.ERIS_POST_BOSS ||
            current.map == vars.PROMETHEUS_POST_BOSS
        );

        if (!settings["splitOnBossKill"] && current.map == vars.CHRONOS_ARENA || in_post_boss_room)
        {
            // ?
            vars.Log(current.run_time + " (!splitOnBossKill) Splitting for chamber transition: " + current.map);
            return true;
        }

        // Split when leaving interbiome
        var left_post_boss_room = (
            old.map == vars.HECATE_POST_BOSS ||
            old.map == vars.SIRENS_POST_BOSS ||
            old.map == vars.CERBERUS_POST_BOSS ||
            old.map == vars.POLYPHEMUS_POST_BOSS ||
            old.map == vars.ERIS_POST_BOSS ||
            old.map == vars.PROMETHEUS_POST_BOSS
        );

        if (settings["midbiome"] && left_post_boss_room)
        {
            vars.Log(current.run_time + " (midbiome) Splitting for leaving interbiome: " + old.map);
            return true;
        }

        // Split on entering boss arena
        var in_boss_arena = (
            current.map == vars.HECATE_ARENA ||
            current.map == vars.SIRENS_ARENA ||
            current.map == vars.CERBERUS_ARENA ||
            current.map == vars.POLYPHEMUS_ARENA ||
            current.map == vars.ERIS_ARENA ||
            current.map == vars.PROMETHEUS_ARENA
        );

        if (settings["enterBossArena"] && in_boss_arena)
        {
            vars.Log(current.run_time + " (enterBossArena) Splitting for entering boss arena: " + current.map);
            return true;
        }
    }
}

onReset
{
    vars.time_split = "0:0.1".Split(':', '.');
    current.total_seconds = 0.5f;
    old.total_seconds = 0.5f;

    vars.has_beat_hades = false;
    vars.boss_killed = false;
    vars.still_in_arena = false;
}

reset
{
    // Reset and clear state if Mel is currently in the courtyard.  Don't reset in multiweapon runs
    if(!settings["multiWep"] && current.map == vars.HUB_PRE_RUN)
    {
        vars.Log("(reset) Resetting for courtyard");
        return true;
    }
}

gameTime
{
    return TimeSpan.FromSeconds(current.total_seconds);
}

isLoading
{
    /*
    Because we just override the gameTime constantly with in-game timer, we
    don't need a fancy load sensor. For a Loadless RTA setting, this will need
    to be actually evaluated, but for now just pretend we are always loading.
    */
    return true;
}

exit
{
    vars.CancelSource.Cancel();
    vars.InitComplete = false;
}

shutdown
{
    vars.CancelSource.Cancel();
}
