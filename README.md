# 🎮 Glitch Aegis for Godot

The **official Godot addon** for the [Glitch Gaming Platform](https://www.glitch.fun).  
Connect your game to Glitch in minutes — earn **$0.10 per hour** of playtime, protect your game with DRM, track player analytics, sync cloud saves, and more. **No server setup required.**

---

## 📋 Table of Contents

1. [What Does This Do?](#what-does-this-do)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [Configuration (Project Settings)](#configuration-project-settings)
5. [Quick Start — Zero Code Setup](#quick-start--zero-code-setup)
6. [Testing Locally (Dev Mode)](#testing-locally-dev-mode)
7. [Advanced Features](#advanced-features)
   - [Tracking Gameplay Events](#tracking-gameplay-events)
   - [Bulk Event Tracking](#bulk-event-tracking)
   - [Cloud Saves](#cloud-saves)
   - [Tracking Purchases](#tracking-purchases)
   - [Manual Validation](#manual-validation)
   - [Toggling the Heartbeat at Runtime](#toggling-the-heartbeat-at-runtime)
   - [Reacting to Signals](#reacting-to-signals)
8. [Access Denied Screen](#access-denied-screen)
9. [Editor Console](#editor-console)
10. [All Project Settings Reference](#all-project-settings-reference)
11. [Frequently Asked Questions](#frequently-asked-questions)
12. [Support](#support)

---

## What Does This Do?

| Feature | What it means for you |
|---|---|
| **Payout Heartbeat** | Automatically pings Glitch every 60 s so you earn money while people play |
| **DRM Validation** | Optionally blocks the game if the player doesn't have a valid license |
| **Event Tracking** | Record what players do inside your game (level completions, deaths, etc.) |
| **Cloud Saves** | Store and sync player progress — works across devices |
| **Purchase Tracking** | Record in-game purchases and revenue events |
| **Fingerprinting** | Helps Glitch attribute installs back to the correct ad or influencer |
| **Editor Console** | Test your API connection without leaving Godot |

---

## Requirements

- **Godot 4.1 or later** (4.2+ recommended)
- A free developer account on [glitch.fun](https://www.glitch.fun)
- Your **Title ID** and **Title Token** from the Glitch dashboard

> ⚠️ **Godot 3.x is not supported** by this addon. The API uses Godot 4 features  
> (`JavaScriptBridge`, `@tool`, `await`, `PackedByteArray`, etc.). If you are on Godot 3, please use the [manual integration guide](https://docs.glitch.fun) and the raw HTTP examples.

---

## Installation

### Option A — Copy the folder (recommended for beginners)

1. Download or clone this repository.
2. In your file manager, **copy the `addons/glitch_aegis` folder** into your Godot project's `res://addons/` directory.  
   After copying, your project should look like this:
   ```
   MyGame/
   ├── addons/
   │   └── glitch_aegis/
   │       ├── plugin.cfg
   │       ├── glitch_plugin.gd
   │       ├── glitch_singleton.gd
   │       ├── glitch_dock.gd
   │       └── glitch_dock.tscn
   ├── scenes/
   └── ...
   ```
3. Open your project in Godot.
4. Go to **Project → Project Settings → Plugins** tab.
5. Find **Glitch Aegis** in the list and click the **Enable** checkbox.

You should see a new **"Glitch Console"** panel appear at the bottom of the editor.

### Option B — Git submodule (for advanced users)

```bash
git submodule add https://github.com/Glitch-Gaming-Platform/Glitch-Godot-Extensions.git addons/glitch_aegis_src
# Then symlink or copy the addons/glitch_aegis folder into your project
```

---

## Configuration (Project Settings)

After enabling the plugin, all settings are found in one place:

1. Go to **Project → Project Settings**
2. In the left sidebar, scroll to the very bottom
3. Click **Glitch → Config**

You will see these fields:

| Setting | What to put here |
|---|---|
| **Title ID** | Your game's UUID from the Glitch dashboard (e.g. `a1b2c3d4-...`) |
| **Title Token** | Your secret API key from the Tokens tab on the dashboard |
| **Auto Start Heartbeat** | ✅ Keep this ON to earn payouts automatically |
| **Heartbeat Interval** | How often (in seconds) to ping Glitch. Default: `60` |
| **Require Validation** | If ON, players without a valid license see an error screen |
| **Test Install ID** | Paste your dev test ID here to test locally (see below) |
| **Game Version** | Your game's version string, e.g. `1.0.3` |
| **Enable Fingerprinting** | ✅ Recommended ON — helps attribute installs to ads |
| **Enable Events** | ✅ Recommended ON — enables funnel analytics |
| **Enable Cloud Saves** | ✅ Recommended ON — enables cloud save system |

> 📌 **Where do I find my Title ID and Token?**  
> Log into [glitch.fun](https://www.glitch.fun), open your game's dashboard, and go to the **Technical** or **Tokens** tab.

---

## Quick Start — Zero Code Setup

If you just want payouts and basic DRM **without writing any code**:

1. Complete the [Configuration](#configuration-project-settings) section above.
2. Make sure **Auto Start Heartbeat** is `true`.
3. Export and deploy your game via the Glitch Deploy page.

**That's it.** When a player launches your game through Glitch, the plugin will:
- Automatically read the `install_id` from the URL.
- Register the session with Glitch.
- Send a heartbeat every 60 seconds to earn you $0.10/hr.

---

## Testing Locally (Dev Mode)

When you run your game inside the Godot editor or export it yourself (without going through the Glitch launcher), there is no `install_id` in the URL. To test the integration locally:

1. Go to your Glitch dashboard → **Technical** tab.
2. Copy your **Developer Test Install ID** (it looks like a UUID).
3. Paste it into **Project Settings → Glitch → Config → Test Install ID**.

Now when you press **Play** in the editor:
- The plugin sees no URL parameter, so it falls back to the Test Install ID.
- You can test heartbeats, cloud saves, and events against the real API.
- This install ID is anchored to your developer account, so test data is easy to identify.

> ✅ The Test Install ID is only used when no `install_id` is found in the URL or command line. It will **not** override a real session when the game is launched by the Glitch platform.

---

## Advanced Features

All features are accessed through the global `Glitch` singleton. You can call it from any script in your project.

---

### Tracking Gameplay Events

Use events to understand what players do inside your game. This powers the **Funnel Analysis** feature on your dashboard.

Think of events as two parts:
- **step_key** — *Where* in the game the player is (e.g. `"level_1"`, `"main_menu"`, `"tutorial"`)
- **action_key** — *What* the player did (e.g. `"completed"`, `"died"`, `"clicked_skip"`)

```gdscript
# Track a single event
func _on_tutorial_finished():
    Glitch.track_event("tutorial", "completed", {"time_seconds": 45})

func _on_player_died():
    Glitch.track_event("level_1", "player_death", {"enemy_type": "boss", "player_hp": 0})

func _on_shop_opened():
    Glitch.track_event("shop", "opened")
```

**Common event patterns:**

```gdscript
# Onboarding funnel
Glitch.track_event("onboarding", "start")
Glitch.track_event("onboarding", "tutorial_complete")
Glitch.track_event("onboarding", "first_level_start")

# Economy funnel
Glitch.track_event("shop", "opened")
Glitch.track_event("shop", "item_viewed", {"item": "sword_of_doom"})
Glitch.track_event("shop", "purchase_started", {"item": "sword_of_doom", "price": 4.99})
```

---

### Bulk Event Tracking

If you track many events quickly (e.g. every few seconds), send them in batches to save battery and bandwidth:

```gdscript
var event_queue: Array = []

func _on_something_happened(step: String, action: String):
    event_queue.append({
        "step_key": step,
        "action_key": action,
        "event_timestamp": Time.get_datetime_string_from_system(true)
    })

# Call this every 60 seconds or when the player leaves a scene
func flush_events():
    if event_queue.is_empty():
        return
    Glitch.track_events_bulk(event_queue)
    event_queue.clear()
```

---

### Cloud Saves

Store and retrieve player progress in the cloud. Players can pick up where they left off on any device.

#### Saving

```gdscript
func save_game():
    var save_data = {
        "player_level": 12,
        "gold": 500,
        "inventory": ["sword", "shield"],
        "position": {"x": 100, "y": 200}
    }
    # Slot 1, manual save
    # The plugin tracks the version automatically — just pass 0 for a brand-new save
    Glitch.upload_save(1, save_data, "manual")

# For auto-saves (called frequently, e.g. on scene change):
func auto_save():
    Glitch.upload_save(0, current_save_data, "auto")
```

#### Loading

```gdscript
func load_game():
    var saves: Array = await Glitch.list_saves()
    if saves.is_empty():
        print("No cloud saves found.")
        return

    # Find slot 1
    for save in saves:
        if save["slot_index"] == 1:
            var raw_bytes: PackedByteArray = Marshalls.base64_to_raw(save["payload"])
            var json_str: String = raw_bytes.get_string_from_utf8()
            var data: Dictionary = JSON.parse_string(json_str)
            print("Loaded! Player level: ", data["player_level"])
            break
```

#### Handling Save Conflicts

A conflict happens when the same slot has been saved on two different devices while offline. The plugin emits a signal when this occurs:

```gdscript
func _ready():
    Glitch.save_conflict_detected.connect(_on_save_conflict)
    Glitch.save_uploaded.connect(_on_save_ok)

func _on_save_ok(new_version: int):
    print("Save successful! Version: ", new_version)

func _on_save_conflict(conflict_id: String, server_version: int):
    print("Conflict! Server has version ", server_version)
    # Show a dialog asking the player which version to keep:
    # "Keep Cloud Save" or "Keep Local Save"

func _on_player_chose_cloud(save_id: String, conflict_id: String):
    await Glitch.resolve_save_conflict(save_id, conflict_id, "keep_server")

func _on_player_chose_local(save_id: String, conflict_id: String):
    await Glitch.resolve_save_conflict(save_id, conflict_id, "use_client")
```

---

### Tracking Purchases

Record when players make purchases (in-app, store, etc.) to track revenue in your Glitch dashboard:

```gdscript
func _on_purchase_completed(item_name: String, price: float, transaction_id: String):
    Glitch.track_purchase({
        "purchase_type": "in_app",
        "purchase_amount": price,
        "currency": "USD",
        "transaction_id": transaction_id,
        "item_sku": item_name.to_lower().replace(" ", "_"),
        "item_name": item_name,
        "quantity": 1,
    })
```

---

### Manual Validation

If you want to check the player's license yourself (for example, to gate specific content):

```gdscript
func _on_premium_content_requested():
    var result: Dictionary = await Glitch.validate_session()
    if result.get("valid", false):
        var license: String = result.get("license_type", "")
        if license == "premium":
            show_premium_content()
        else:
            show_upgrade_prompt()
    else:
        show_purchase_required_screen()
```

---

### Toggling the Heartbeat at Runtime

You can turn the payout heartbeat on and off from code:

```gdscript
# Pause payouts when the game is paused
func _on_game_paused():
    Glitch.stop_heartbeat()

# Resume payouts when the game resumes
func _on_game_resumed():
    Glitch.start_heartbeat()

# Check if it's currently running
func check_payout_status():
    if Glitch.is_heartbeat_active():
        print("Payouts: active")
    else:
        print("Payouts: paused")
```

---

### Reacting to Signals

Connect to these signals in any script to respond to Glitch events:

```gdscript
func _ready():
    # Fired when the player's install is registered successfully
    Glitch.handshake_succeeded.connect(_on_handshake_ok)

    # Fired if the initial registration fails (no internet, bad token, etc.)
    Glitch.handshake_failed.connect(_on_handshake_failed)

    # Fired when license validation passes (only if require_validation is ON)
    Glitch.validation_succeeded.connect(_on_valid)

    # Fired when license validation fails
    Glitch.validation_failed.connect(_on_invalid)

    # Fired every time a heartbeat is sent successfully
    Glitch.heartbeat_sent.connect(_on_heartbeat)

    # Fired when a save uploads successfully
    Glitch.save_uploaded.connect(_on_save_uploaded)

    # Fired when a save conflict is detected
    Glitch.save_conflict_detected.connect(_on_conflict)

    # Fired when list_saves() returns results
    Glitch.save_list_received.connect(_on_saves_loaded)


func _on_handshake_ok(install_uuid: String):
    print("Session active! UUID: ", install_uuid)

func _on_handshake_failed(reason: String):
    print("Could not connect to Glitch: ", reason)

func _on_valid(user_name: String, license_type: String):
    print("Welcome %s! License: %s" % [user_name, license_type])

func _on_invalid(reason: String):
    print("License invalid: ", reason)

func _on_heartbeat():
    pass   # Called every ~60 seconds — useful for UI indicators

func _on_save_uploaded(new_version: int):
    print("Save synced to cloud (version %d)" % new_version)

func _on_conflict(conflict_id: String, server_version: int):
    print("Save conflict! Server version: %d" % server_version)

func _on_saves_loaded(saves: Array):
    print("Found %d save slots" % saves.size())
```

---

## Access Denied Screen

When **Require Validation** is turned ON in Project Settings, the plugin automatically shows a full-screen error overlay if:

- The player's license has expired or they don't have one.
- No `install_id` is present (they didn't launch through Glitch).
- The validation API call returns a 403 error.
- A heartbeat returns 403 (license revoked while playing).

The overlay:
- Renders on top of everything (works for both 2D and 3D games).
- Pauses the game tree so nothing runs underneath.
- Shows a message and a **"Visit Glitch Store"** button.
- Opens `https://glitch.fun/games/<your-title-id>` in the browser.

**Customizing the message** — you can trigger the screen manually too:

```gdscript
# Show it manually with a custom message
Glitch.show_access_denied("Your trial has ended!\nUpgrade to keep playing.")

# Hide it (e.g. if the player successfully purchases and you want to resume)
Glitch.hide_access_denied()
get_tree().paused = false   # Don't forget to unpause!
```

> 💡 If you want to build your own custom UI instead of using the built-in overlay, set **Require Validation** to `false` and handle the `validation_failed` signal yourself.

---

## Editor Console

After enabling the plugin, look for the **"Glitch Console"** tab at the bottom of the Godot editor (same area as the Output and Debugger tabs).

From here you can:

| Button | What it does |
|---|---|
| **Test API Connection** | Pings the Glitch API with your current Title ID and Token to confirm they work |
| **Refresh Settings** | Re-reads Project Settings and updates the display |
| **Open Docs ↗** | Opens the Glitch developer documentation in your browser |

The panel also shows a summary of your current configuration so you can see at a glance whether everything is set up correctly.

---

## All Project Settings Reference

Find these under **Project → Project Settings → Glitch → Config**:

| Key | Type | Default | Description |
|---|---|---|---|
| `glitch/config/title_id` | String | `""` | **Required.** Your game's UUID from the Glitch dashboard. |
| `glitch/config/title_token` | String | `""` | **Required.** Your secret API key from the Tokens tab. |
| `glitch/config/auto_start_heartbeat` | Bool | `true` | If true, payouts start automatically when the game loads. |
| `glitch/config/heartbeat_interval` | Int | `60` | Seconds between payout pings. Minimum recommended: 30. |
| `glitch/config/require_validation` | Bool | `false` | If true, players without a valid license see an error screen and cannot play. |
| `glitch/config/test_install_id` | String | `""` | Paste your developer test UUID here for local testing. Only used when no URL install_id is found. |
| `glitch/config/game_version` | String | `"1.0.0"` | Your game's version string, sent with every heartbeat. |
| `glitch/config/enable_fingerprinting` | Bool | `true` | Send device info to help attribute installs to ads. |
| `glitch/config/enable_events` | Bool | `true` | Enable the event / funnel tracking system. |
| `glitch/config/enable_cloud_saves` | Bool | `true` | Enable the cloud save system. |

---

## Frequently Asked Questions

**Q: Will the plugin break my game if the player has no internet?**  
A: No. The heartbeat and API calls are fire-and-forget; they won't crash your game if they fail. If `require_validation` is `false` (the default), the game runs normally even without a connection.

**Q: What happens if a player closes the game while the heartbeat is running?**  
A: Nothing bad. The timer is destroyed with the scene tree when the game exits. The last heartbeat sent before closure is the last payout recorded.

**Q: My heartbeat is returning HTTP 403 during testing. Why?**  
A: Your test install ID might be expired or you may have hit the API before the session was registered. Try regenerating your Test Install ID on the Glitch dashboard and updating Project Settings.

**Q: Can I use this for a game that isn't on the Glitch store?**  
A: The plugin is specifically designed for games distributed through Glitch. The `install_id` is generated by the Glitch launcher. Without it, payouts and DRM features won't work (though cloud saves and events will still function if you provide a consistent `user_install_id` manually).

**Q: Does this work for offline/singleplayer games?**  
A: Yes. The only internet requirement is the heartbeat. Everything else (your game's actual gameplay) remains fully offline.

**Q: My Godot Web export can't call `JavaScriptBridge`. What's wrong?**  
A: Make sure you exported with the **Web** template (not Desktop). Godot wraps `JavaScriptBridge` calls in `OS.has_feature("web")` checks so they won't crash on desktop, but they won't return data either.

**Q: How do I know the heartbeat is actually being sent?**  
A: Connect to `Glitch.heartbeat_sent` and print a message, or check the Network tab in your browser's DevTools (Web export). You can also use the Playground on the Glitch Technical page to see live API calls.

---

## Support

- 💬 **Discord:** [Join our Developer Community](https://discord.gg/RPYU9KgEmU)
- 📖 **Documentation:** [Full API Reference](https://docs.glitch.fun)
- 🌐 **Website:** [glitch.fun](https://www.glitch.fun)
- 🐛 **Bug Reports:** [GitHub Issues](https://github.com/Glitch-Gaming-Platform/Glitch-Godot-Extensions/issues)
