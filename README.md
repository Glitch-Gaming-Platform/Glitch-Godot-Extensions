# Glitch Godot Extension v3.0.0

The official [Glitch](https://glitch.fun) extension for **Godot 4.x**. Zero-code heartbeat payouts and DRM via Project Settings, with one-line GDScript calls for achievements, leaderboards, cloud saves, analytics, purchases, fingerprinting, and optional Steam-to-Glitch migration.

---

## Installation

1. Copy the `addons/glitch_aegis` folder into your project's `addons/` directory.
2. In Godot, go to **Project → Project Settings → Plugins** and enable **Glitch Aegis**.
3. The plugin adds a `Glitch` autoload singleton and a "Glitch Console" panel in the bottom dock.

**Requires Godot 4.0 or later.** The plugin uses Godot 4 features (typed signals, `await`, `JavaScriptBridge`, etc.) and is not compatible with Godot 3.x.

---

## Quick Start (3 Steps)

### Step 1: Get Your Credentials

1. Go to [glitch.fun](https://glitch.fun) → **My Games** → select your game.
2. Open the **Technical Integration** page.
3. Copy your **Title ID**, **Title Token**, and **Developer Test Install ID**.

### Step 2: Configure in Project Settings

Go to **Project → Project Settings → Glitch → Config** and fill in:

| Setting | What to Enter |
|---------|--------------|
| **Title ID** | Your UUID from the dashboard |
| **Title Token** | Your private API token |
| **Test Install ID** | Your dev test ID (for F5 playtesting) |
| **Game Version** | Your build version (e.g. "1.0.0") |

Toggle features ON/OFF:

| Setting | Default | What It Does |
|---------|---------|-------------|
| **Auto Start Heartbeat** | ✅ ON | Earns $0.10/hr payouts automatically |
| **Heartbeat Interval** | 60 | Seconds between heartbeat pings |
| **Require Validation** | ❌ OFF | Blocks game if license is invalid |
| **Enable Fingerprinting** | ✅ ON | Sends hardware fingerprint for attribution |
| **Enable Events** | ✅ ON | Enables track_event() |
| **Enable Cloud Saves** | ✅ ON | Enables upload_save() / list_saves() |
| **Enable Achievements** | ✅ ON | Auto-loads achievements on startup |
| **Enable Leaderboards** | ✅ ON | Enables submit_score() |
| **Enable Steam Bridge** | ❌ OFF | Enables steam_*() replacement functions |

### Step 3: Test the Connection

Open the **Glitch Console** panel at the bottom of the editor and click **Test API Connection**. You should see a green "Connected!" message with your game's name.

**That's it!** Heartbeat and DRM work with zero code.

---

## Achievements

### Dashboard Setup

Define achievements on the Glitch dashboard with an **API Key** (e.g. `boss_killed`) and an **Unlock Threshold** (e.g. `1`).

### GDScript Usage

```gdscript
# Player beat the first boss — one line:
Glitch.report_achievement("boss_killed", 1)

# Player collected their 50th coin (cumulative):
Glitch.report_achievement("coin_collector", 50)

# Check if an achievement is unlocked (instant, no network):
if Glitch.is_achievement_unlocked("boss_killed"):
    $Trophy.visible = true

# Get progress value:
var progress = Glitch.get_achievement_progress("coin_collector")
$ProgressBar.value = progress

# Force-reload from server:
await Glitch.refresh_achievements()
```

### Signals

```gdscript
func _ready():
    Glitch.achievement_unlocked.connect(_on_achievement_unlocked)
    Glitch.achievements_loaded.connect(_on_achievements_loaded)

func _on_achievement_unlocked(api_key: String):
    print("Trophy unlocked: ", api_key)

func _on_achievements_loaded(success: bool):
    if success:
        print("Achievement cache ready")
```

---

## Leaderboards

### Dashboard Setup

Define leaderboards on the dashboard with an **API Key** and **Sort Order**.

### GDScript Usage

```gdscript
# Submit a score:
Glitch.submit_score("high_score", 5000)

# Download leaderboard entries:
var entries = await Glitch.get_leaderboard("high_score")
for entry in entries:
    print("%s: %d" % [entry.get("user_name", ""), entry.get("score", 0)])
```

### Signals

```gdscript
Glitch.leaderboard_received.connect(func(board_key, entries):
    print("Leaderboard %s has %d entries" % [board_key, entries.size()])
)
```

---

## Cloud Saves

### Saving

```gdscript
# Save any Dictionary to a cloud slot (0-99):
var save_data = {
    "level": current_level,
    "hp": player.hp,
    "coins": Global.coins,
    "inventory": Global.inventory,
}
Glitch.upload_save(1, save_data)

# Listen for success:
Glitch.save_uploaded.connect(func(version):
    print("Saved! Version: ", version)
)
```

### Loading

```gdscript
# Download all cloud saves:
var saves = await Glitch.list_saves()
for save in saves:
    if save.get("slot_index") == 1:
        var payload_b64 = save.get("payload", "")
        var json_bytes = Marshalls.base64_to_raw(payload_b64)
        var data = JSON.parse_string(json_bytes.get_string_from_utf8())
        # Restore your game state from data
```

### Conflict Resolution

```gdscript
Glitch.save_conflict_detected.connect(func(conflict_id, server_ver):
    # Show UI asking player to choose
    var keep_server = await show_conflict_dialog()
    var choice = "keep_server" if keep_server else "use_client"
    Glitch.resolve_save_conflict(save_id, conflict_id, choice)
)
```

---

## Analytics Events

```gdscript
# Track what players do:
Glitch.track_event("boss_fight", "player_death", {"weapon": "sword"})
Glitch.track_event("tutorial", "completed")

# Batch events for mobile:
Glitch.track_events_bulk([
    {"step_key": "level_1", "action_key": "started"},
    {"step_key": "level_1", "action_key": "completed"},
])
```

---

## Purchases

```gdscript
Glitch.track_purchase({
    "purchase_type": "in_app",
    "purchase_amount": 4.99,
    "currency": "USD",
    "transaction_id": "txn_12345",
    "item_sku": "starter_pack",
    "item_name": "Starter Pack",
    "quantity": 1,
})
```

---

## Steam-to-Glitch Migration

If your game already uses a **Godot Steam plugin** (like GodotSteam), the Steam Bridge lets you redirect those calls to Glitch with minimal changes.

### Prerequisites

1. On the Glitch dashboard, create achievements and leaderboards with **the same API key names** you used on Steam.
2. Set **Enable Steam Bridge** to **ON** in Project Settings → Glitch → Config.

### Replace Your Steam Calls

```gdscript
# ─── BEFORE (GodotSteam) ────────────────────
# Steam.setAchievement("ACH_WIN_GAME")
# Steam.setStatInt("TotalKills", 150)
# Steam.storeStats()

# ─── AFTER (Glitch Bridge) ──────────────────
Glitch.steam_set_achievement("ACH_WIN_GAME")
Glitch.steam_set_stat_int("TotalKills", 150)
Glitch.steam_store_stats()   # Flushes everything to Glitch
```

### Leaderboards

```gdscript
# ─── BEFORE ──────────────────────────────────
# Steam.uploadLeaderboardScore(5000, "high_score")

# ─── AFTER ───────────────────────────────────
Glitch.steam_upload_score("high_score", 5000)
Glitch.steam_store_stats()
```

### Reading Achievements

```gdscript
if Glitch.steam_get_achievement("ACH_WIN_GAME"):
    show_trophy()
```

### Dual Build Switch

```gdscript
# At the top of your script:
const USE_GLITCH = true

# In your game logic:
if USE_GLITCH:
    Glitch.steam_set_achievement("ACH_WIN_GAME")
    Glitch.steam_store_stats()
else:
    Steam.setAchievement("ACH_WIN_GAME")
    Steam.storeStats()
```

### What the Bridge Handles

| GodotSteam Function | Glitch Bridge | Notes |
|---|---|---|
| `Steam.setAchievement(name)` | `Glitch.steam_set_achievement(name)` | Buffered |
| `Steam.getAchievement(name)` | `Glitch.steam_get_achievement(name)` | Local cache |
| `Steam.setStatInt(name, val)` | `Glitch.steam_set_stat_int(name, val)` | Buffered |
| `Steam.setStatFloat(name, val)` | `Glitch.steam_set_stat_float(name, val)` | Buffered |
| `Steam.uploadLeaderboardScore(score, board)` | `Glitch.steam_upload_score(board, score)` | Buffered |
| `Steam.storeStats()` | `Glitch.steam_store_stats()` | Flushes all |
| `Steam.requestCurrentStats()` | `Glitch.steam_request_stats()` | Refreshes cache |

---

## Function Reference

### Core

| Function | Description |
|----------|------------|
| `Glitch.initialize()` | Manual init (if auto_start is OFF) |
| `Glitch.start_heartbeat()` | Start the payout timer |
| `Glitch.stop_heartbeat()` | Pause the payout timer |
| `Glitch.is_heartbeat_active()` | Check if heartbeat is running |
| `Glitch.validate_session()` | Manual DRM check → returns Dictionary |

### Achievements

| Function | Description |
|----------|------------|
| `Glitch.report_achievement(key, value)` | Report progress (unlocks if threshold met) |
| `Glitch.is_achievement_unlocked(key)` | Check local cache (instant) |
| `Glitch.get_achievement_progress(key)` | Get progress value (local cache) |
| `Glitch.refresh_achievements()` | Force-reload from server |

### Leaderboards

| Function | Description |
|----------|------------|
| `Glitch.submit_score(board_key, score)` | Submit a score |
| `Glitch.get_leaderboard(board_key)` | Download entries → returns Array |

### Cloud Saves

| Function | Description |
|----------|------------|
| `Glitch.upload_save(slot, data, type, version)` | Upload a save Dictionary |
| `Glitch.list_saves()` | Download all slots → returns Array |
| `Glitch.resolve_save_conflict(save_id, conflict_id, choice)` | Resolve a 409 conflict |

### Analytics & Purchases

| Function | Description |
|----------|------------|
| `Glitch.track_event(step, action, metadata)` | Single analytics event |
| `Glitch.track_events_bulk(events_array)` | Batch analytics events |
| `Glitch.track_purchase(data)` | Record a purchase/revenue event |

### Signals

| Signal | When It Fires |
|--------|--------------|
| `handshake_succeeded(uuid)` | Session registered with Glitch |
| `handshake_failed(reason)` | Session registration failed |
| `validation_succeeded(user_name, license_type)` | DRM check passed |
| `validation_failed(reason)` | DRM check failed |
| `heartbeat_sent` | Heartbeat ping acknowledged |
| `save_uploaded(version)` | Cloud save succeeded |
| `save_conflict_detected(conflict_id, server_version)` | Save version conflict |
| `save_list_received(saves)` | Cloud saves downloaded |
| `achievements_loaded(success)` | Achievement cache populated |
| `achievement_unlocked(api_key)` | A new achievement was unlocked |
| `leaderboard_received(board_key, entries)` | Leaderboard data downloaded |

---

## Godot 3 Compatibility

This plugin is **Godot 4 only**. The codebase uses `@tool`, typed signals, `await`, `PackedStringArray`, `.instantiate()`, `JavaScriptBridge`, and `Time.*` — all Godot 4-specific features. A Godot 3 version would require rewriting nearly every line and is not currently supported. If you need Godot 3 support, please reach out on Discord.

---

## Troubleshooting

### "Title ID or Token is not set" warning

Go to **Project → Project Settings → Glitch → Config** and paste your credentials.

### No install_id found

Normal when running locally. Paste your **Test Install ID** in Project Settings.

### Achievements return HTTP 403

Player is a guest (not logged into Glitch). Show a "Log in to track progress" message.

### Cloud save returns HTTP 409

Version conflict — player saved on another device. Handle the `save_conflict_detected` signal.

### Web export: install_id not detected

The Glitch launcher adds `?install_id=UUID` to the URL. Make sure your HTML5 export is served through the Glitch platform.

---

## Support

- **Dashboard**: [glitch.fun/games/admin](https://glitch.fun/games/admin)
- **Discord**: [discord.gg/RPYU9KgEmU](https://discord.gg/RPYU9KgEmU)
