# Glitch Aegis for Godot (No-Code Integration)

The official Godot addon for the [Glitch Gaming Platform](https://www.glitch.fun). This addon allows you to integrate security, payouts, and analytics into your game **without writing a single line of code.**

## 🚀 Features
*   **Aegis Handshake:** Automatic DRM that verifies player licenses on startup.
*   **Developer Payouts:** Automatically sends heartbeats every 60 seconds so you earn **$0.10 per hour** of active playtime.
*   **Zero-Config Analytics:** Automatically tracks sessions, device types, and hardware fingerprints.
*   **Editor Integration:** Manage your Glitch settings directly inside the Godot Project Settings.

---

## 📦 Installation

1.  **Download** this repository.
2.  **Copy** the `addons/glitch_aegis` folder into your Godot project's `res://addons/` directory.
3.  **Enable the Plugin:**
    *   In the Godot Editor, go to **Project > Project Settings**.
    *   Click the **Plugins** tab.
    *   Find **Glitch Aegis** and check the **Enable** box.

---

## ⚙️ Configuration

Once the plugin is enabled, a new configuration section is added directly to your Godot settings.

1.  Go to **Project > Project Settings**.
2.  Scroll down the left sidebar to the bottom. You will see a new category named **Glitch**.
3.  Click on **Config** and enter your details from the [Glitch Dashboard](https://www.glitch.fun/dashboard):
    *   **Title ID:** Your game's unique UUID.
    *   **Title Token:** Your secret API key (found in the "Tokens" tab).
    *   **Auto Start Handshake:** Keep this checked to enable no-code payouts.

**That's it!** Your game is now connected. When you run your game, Glitch will automatically handle the security handshake and start your payout timer.

---

## 🛠️ Advanced Usage (Optional)

While this addon is designed to work with zero code, you can still use the `Glitch` singleton in your own scripts to track specific events or manage cloud saves.

### Tracking Custom Events
Track milestones like "Level Completed" to see player progression in your dashboard.
```gdscript
func _on_boss_defeated():
    Glitch.track_event("combat", "boss_defeated", {"boss_name": "Dragon", "health_remaining": 10})
```

### Manual Cloud Saves
Store player data in the Glitch cloud so they can play on any device.
```gdscript
func save_game():
    var data = {"stats": {"level": 10, "gold": 500}}
    Glitch.upload_save(1, data) # Saves to Slot 1
```

---

## 🖥️ Editor Console
This addon adds a **Glitch Console** to the bottom panel of your Godot Editor. You can use this panel to:
*   Verify your API connection.
*   View real-time integration logs.
*   Quickly access the Glitch Developer Documentation.

---

## ⚠️ Important Notes
*   **WebGL/Web Exports:** This addon automatically detects if it is running in a browser and will pull the necessary session IDs from the URL provided by the Glitch launcher.
*   **Security:** Your `Title Token` is sensitive. Godot's Project Settings are bundled into your exported game, which is safe for compiled PC/Mobile builds. For Web builds, ensure you use a **Title Token** and not a personal User JWT.

---

## 🆘 Support
*   **Discord:** [Join our Developer Community](https://discord.gg/RPYU9KgEmU)
*   **Documentation:** [Full API Reference](https://api.glitch.fun/api/documentation)
*   **Website:** [glitch.fun](https://www.glitch.fun)
