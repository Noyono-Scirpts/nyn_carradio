# nc_carradio

Modern and fully synchronized car radio for FiveM featuring a premium glassmorphic UI, dynamic audio visualizer, and support for both native GTA V radio stations and custom web audio streams.

## Preview / Showcase

<p align="center">
  <img src="https://r2.fivemanage.com/b6cO99cjGUYnzPKfPXk4X/Snmekobrazovky2026-07-10192554.png" width="80%" alt="Showcase 1" />
  <img src="https://r2.fivemanage.com/b6cO99cjGUYnzPKfPXk4X/Snmekobrazovky2026-07-10192559.png" width="80%" alt="Showcase 2" />
  <img src="https://r2.fivemanage.com/b6cO99cjGUYnzPKfPXk4X/Snmekobrazovky2026-07-10192613.png" width="80%" alt="Showcase 3" />
</p>

---

## Features

- **Premium Glassmorphic Design:** Modern visual interface with smooth sliding animations, neon outer glows, and dynamic text gradients.
- **Dual-Mode UI (Tap & Hold):**
  - **Tap (Quick press Q):** Instantly cycles the vehicle radio to the next station and displays a compact mini badge popup. The mini UI fades away after 1.5 seconds of inactivity. Tapping Q repeatedly cycles stations instantly without delays.
  - **Hold (Long press Q):** Opens the full-screen layout with a horizontal carousel slider showing all available radio stations. Releasing Q closes the UI overlay instantly.
- **Non-Blocking Driving Controls:** The player maintains complete vehicle steering, throttle, and camera control while the UI is open. Selection is performed using the **Mouse Scroll Wheel** or **Left/Right Arrow keys**.
- **Multiplayer Synchronization & Shared Control:**
  - **Any passenger** inside the vehicle (driver or passengers) can trigger and control the radio.
  - Zvuk/Audio (both native radio stations and custom **web streams like MP3/Icecast**) plays in perfect sync for all players in the car.
  - When anyone in the vehicle changes the station, the mini UI badge automatically pops up for 1.5 seconds on all passengers' screens to announce the new station.
  - Entering a vehicle that already has a radio active automatically syncs the stream in the background without popups.
- **Dynamic Equalizer Visualizer:** A 5-bar animated equalizer in the header that bounces actively when music is playing and drops flat/silent when the radio is set to "Radio Off".
- **External Image Support:** Configured stations (`config.lua`) support local file logos (under `ui/images/`, e.g. `"OFF.png"`) as well as direct HTTP/HTTPS web links (e.g. `https://r2.fivemanage.com/...`). The script automatically detects the path type.
- **GTA HUD Displacement:** The script automatically hides and disables the stock GTA V radio wheel to prevent HUD overlapping.

---

## Controls

The default key is **`Q`** (players can customize this in-game under *Settings -> Key Bindings -> FiveM -> Otevrit autoradio*).

- **Tap Q (Quick Release):** Cycles to the next station and shows the mini HUD.
- **Hold Q:** Opens the full carousel selection menu.
- **Scroll Wheel Down / Right Arrow / `,`:** Selects the next station (when UI is open).
- **Scroll Wheel Up / Left Arrow / `.`:** Selects the previous station (when UI is open).
- **Release Q / Escape / Backspace:** Instantly closes the radio UI.

---

## Configuration (`config.lua`)

Configure the keybind and station lists inside `config.lua`:

```lua
Config = {}

Config.Keybind = 'Q'

Config.Stations = {
    {
        name = "Radio Off",
        type = "off",
        value = nil,
        image = "OFF.png",
        icon = "OFF"
    },
    {
        name = "Non-Stop-Pop FM",
        type = "native",
        value = "RADIO_02_POP",
        image = "RADIO_02_POP.png",
        icon = "POP"
    },
    {
        name = "Spin",
        type = "stream",
        value = "https://icecast4.play.cz/spin128.mp3",
        image = "https://r2.fivemanage.com/ip40XPTNAyr9igwi6trti/p2mVFQmx0Dyp.jpg",
        icon = "SPIN"
    }
}
```

---

## Custom Logos Guidelines

If you want to add your own custom radio station logos, follow these recommendations for the best visual presentation:

- **Dimensions:** **128x128 pixels** is recommended (or **256x256 pixels** for crisp high-DPI rendering).
- **Aspect Ratio:** **1:1 (Square)**. The UI buttons are circular circles, so square images will clip perfectly into circles without stretching.
- **Format:** **PNG with transparent background** (or transparent WebP). Using a transparent background allows the dark styling and active border glow of the buttons to blend nicely behind the logo.
- **Paths:** You can use local files stored in `ui/images/` or paste a direct external HTTPS URL.

---

## Installation

1. Place the `nc_carradio` directory inside your server's `resources` folder.
2. Add the following to your `server.cfg`:
   ```cfg
   ensure nc_carradio
   ```
3. If modifying configurations at runtime, remember to run these commands in the console:
   ```cmd
   refresh
   restart nc_carradio
   ```
