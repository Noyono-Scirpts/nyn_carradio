# releases/

Staging for the Tebex / FiveM zip. **Only shippable files** live here — nothing from `web/`, `TEMPLATE.md`, `scripts/`, or `.git`.

## Layout

After `./scripts/release.sh patch|minor|major`:

```
releases/
  nyn_nazev/                 ← folder named after the resource (repo directory)
    fxmanifest.lua
    client/
    server/
    shared/
    locales/
    ui/                      ← built NUI, if the resource has UI
    README.md
  nyn_nazev-1.0.1.zip        ← zip of that folder only
```

The zip root **is** `nyn_nazev/`. Players drop that folder into `resources`. Do not zip the repo root.

## Version

`fxmanifest.lua` `version` is the source of truth. The release script bumps it from the change type:

| Argument | Example     | When |
|----------|-------------|------|
| `patch`  | 1.0.0 → 1.0.1 | bugfix / small change |
| `minor`  | 1.0.0 → 1.1.0 | new feature, compatible |
| `major`  | 1.0.0 → 2.0.0 | breaking change |

Generated folders and zips in this directory are gitignored. This README stays.

`./scripts/release.sh` / `scripts\release.bat` also writes the new `fxmanifest` version into public [Noyono-Scirpts/nyn_versions](https://github.com/Noyono-Scirpts/nyn_versions), then commits, tags, pushes, and creates a GitHub Release. Needs `gh auth login`.
