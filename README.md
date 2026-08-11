# nyn_carradio

Modern synchronized car radio for FiveM — glassmorphic UI (Svelte), audio visualizer, native GTA stations + custom web streams.

**Requires:** `nyn_lib`, `ox_lib`

## Preview / Showcase

<p align="center">
  <img src="https://r2.fivemanage.com/b6cO99cjGUYnzPKfPXk4X/Snmekobrazovky2026-07-10192554.png" width="80%" alt="Showcase 1" />
  <img src="https://r2.fivemanage.com/b6cO99cjGUYnzPKfPXk4X/Snmekobrazovky2026-07-10192559.png" width="80%" alt="Showcase 2" />
  <img src="https://r2.fivemanage.com/b6cO99cjGUYnzPKfPXk4X/Snmekobrazovky2026-07-10192613.png" width="80%" alt="Showcase 3" />
</p>

## Features

- Premium glassmorphic UI (Svelte) with equalizer visualizer
- Tap / hold keybind (cycle station vs full carousel)
- Multiplayer sync for driver + passengers (native + streams)
- Local logos (`ui/images/`) or HTTPS image URLs
- Locales (`cs` / `en`) via `Config.Locale`
- Emergency vehicle lockout (class 18) with optional notify
- Extension shell — UI in base; command/keybind in `nyn_carradio_plus`

## Car Radio+ (paid extension)

YouTube **and live streams** in the vehicle via `xsound` (boombox-style + streams from base radio).

**Cabin mix:** full volume inside → muffled outside with closed doors → clearer when doors are open.

1. Add `nyn_carradio_plus`
2. `ensure xsound` + `ensure nyn_carradio` + `ensure nyn_carradio_plus`
3. `/carradio` or the keybind from `nyn_carradio_plus` config → Play URL (YT or `https://…/stream.mp3`)

## Controls

Default key: **`Q`** (Settings → Key Bindings → FiveM → Open car radio)

- **Tap:** next station + mini HUD
- **Hold:** full carousel
- **Scroll / arrows:** change station while UI open
- **Release / Escape:** close UI
- **Car Radio+:** set `Config.EnableExtension = true` in base; command/keybind live in `nyn_carradio_plus` (default `/carradio`, **F7**)

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

## UI development (Svelte)

Source lives in `web/`. Built files go to `ui/`.

```bash
cd web
npm install
npm run build
```

Dev preview (browser only):

```bash
npm run dev
```

After UI changes, always run `npm run build` before restarting the resource.

## Installation

1. Ensure `nyn_lib` and `ox_lib` start before this resource.
2. Place `nyn_carradio` in `resources`.
3. `server.cfg`:

```cfg
ensure nyn_lib
ensure ox_lib
ensure nyn_carradio
```
