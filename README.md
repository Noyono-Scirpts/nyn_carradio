# nyn_carradio

Modern synchronized car radio for FiveM — glassmorphic UI, audio visualizer, native GTA stations + custom web streams.

**Requires:** `nyn_lib`, `ox_lib`

## Preview / Showcase

<p align="center">
  <img src="https://r2.fivemanage.com/b6cO99cjGUYnzPKfPXk4X/Snmekobrazovky2026-07-10192554.png" width="80%" alt="Showcase 1" />
  <img src="https://r2.fivemanage.com/b6cO99cjGUYnzPKfPXk4X/Snmekobrazovky2026-07-10192559.png" width="80%" alt="Showcase 2" />
  <img src="https://r2.fivemanage.com/b6cO99cjGUYnzPKfPXk4X/Snmekobrazovky2026-07-10192613.png" width="80%" alt="Showcase 3" />
</p>

## Features

- Premium glassmorphic UI with equalizer visualizer
- Tap / hold keybind (cycle station vs full carousel)
- Multiplayer sync for driver + passengers (native + streams)
- Local logos (`ui/images/`) or HTTPS image URLs
- Locales (`cs` / `en`) via `Config.Locale`
- Emergency vehicle lockout (class 18) with optional `nyn_lib` notify

## Controls

Default key: **`Q`** (Settings → Key Bindings → FiveM → Open car radio)

- **Tap:** next station + mini HUD
- **Hold:** full carousel
- **Scroll / arrows:** change station while UI open
- **Release / Escape:** close UI

## Configuration

Edit `shared/config.lua`:

```lua
Config.Locale = 'cs'
Config.Debug = false
Config.Keybind = 'Q'
Config.DisableInEmergency = true
Config.NotifyOnBlocked = true
Config.Stations = { ... }
```

Locales: `locales/cs.lua`, `locales/en.lua`

## Installation

1. Ensure `nyn_lib` and `ox_lib` start before this resource.
2. Place `nyn_carradio` in `resources`.
3. `server.cfg`:

```cfg
ensure nyn_lib
ensure ox_lib
ensure nyn_carradio
```
