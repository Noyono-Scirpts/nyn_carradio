# nyn_carradio

Synchronized vehicle radio for FiveM — native GTA stations, custom web streams, Svelte NUI with equalizer.

**Requires:** `nyn_lib`, `ox_lib`

## Preview

<p align="center">
  <img src="https://r2.fivemanage.com/b6cO99cjGUYnzPKfPXk4X/Snmekobrazovky2026-07-10192554.png" width="80%" alt="UI" />
  <img src="https://r2.fivemanage.com/b6cO99cjGUYnzPKfPXk4X/Snmekobrazovky2026-07-10192559.png" width="80%" alt="Stations" />
  <img src="https://r2.fivemanage.com/b6cO99cjGUYnzPKfPXk4X/Snmekobrazovky2026-07-10192613.png" width="80%" alt="Radio" />
</p>

## Features

- Tap / hold keybind (next station vs full carousel)
- Multiplayer sync for driver + passengers (native + streams)
- Local logos (`ui/images/`) or HTTPS image URLs
- Locales (`cs` / `en`) via `Config.Locale`
- Emergency vehicle lockout (class 18) with optional notify
- Optional Car Radio+ shell — UI in base; command/keybind in `nyn_carradio_plus`

## Installation

1. Ensure `nyn_lib` and `ox_lib` start before this resource.
2. Place `nyn_carradio` in `resources`.
3. `server.cfg`:

```cfg
ensure nyn_lib
ensure ox_lib
ensure nyn_carradio
```

## Controls

Default key: **`Q`** (Settings → Key Bindings → FiveM → Open car radio)

- **Tap:** next station + mini HUD
- **Hold:** full carousel
- **Scroll / arrows:** change station while UI open
- **Release / Escape:** close UI

## Configuration

Edit `shared/config.lua`:

```lua
Config.Locale = 'en'
Config.Debug = false
Config.Keybind = 'Q'
Config.EnableExtension = true
Config.ExtensionResource = 'nyn_carradio_plus'
Config.DisableInEmergency = true
Config.NotifyOnBlocked = true
Config.Notify = 'nyn_lib' -- 'nyn_lib' | 'ox_lib'
Config.Stations = { ... }
```

Locales: `locales/cs.lua`, `locales/en.lua`  
Plus UI strings use the same packs (`plus_*` keys).

## Car Radio+

YouTube and live streams in the vehicle via `xsound`. Cabin mix: full volume inside, muffled outside with closed doors, clearer when doors are open.

1. Add `nyn_carradio_plus`
2. `ensure xsound` + `ensure nyn_carradio` + `ensure nyn_carradio_plus`
3. Set `Config.EnableExtension = true` in base; open with `/carradio` or the keybind from Plus config (default **F7**)

## UI development

Source in `web/`, build output in `ui/`:

```bash
cd web
npm install
npm run build
```
