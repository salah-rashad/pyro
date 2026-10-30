# Spike #3 — Disk rendering

Throwaway code for the v0.0 de-risking spike (`dev-docs/project-plan.md` §14 row 3, §10, §12,
§15.3 item 3; decisions Q8, Q10, Q18, Q31). Findings go into `dev-docs/ARCHITECTURE.md`; nothing
here ships.

| Path | What it is |
|---|---|
| `studio/` | Flutter macOS app standing in for the Studio's viewport. Not sandboxed. Renders a sprite, a frame animation and two Tiled maps inside a Flame `GameWidget`, all read from a project folder chosen at runtime, and reloads whatever a changed file feeds. |
| `studio/lib/disk_asset_source.dart` | `DiskAssetBundle` (an `AssetBundle` that reads files under a root folder) and `TrackingImages` (Flame's `Images` cache that records which files each load stands for). |
| `studio/lib/tiled_disk_loader.dart` | Two ways to load a `.tmx`: flame_tiled's own `TiledComponent.load` (`stock`) and a path-resolving loader on top of `RenderableTiledMap.fromTiledMap` (`resolved`). |
| `tool/make_assets.py` | Writes a tiny hand-made project (PNGs, `.tmx`, `.tsx`; stdlib only, no third-party art). `--variant 2` recolors everything and changes the map. |
| `tool/edit_cases.py` | Edits that project while the app watches it: in-place writes, atomic replace (temp + rename), delete, re-create, an unrelated file. |
| `tool/run_cases.sh` | Fresh project → start the built app → run every edit case → quit. |
| `tool/summarize.py` | Joins the app's JSON log with the edit times into the latency table below. |
| `screenshots/` | Captures from the runs below (the app captures its own window after every reload). |

## What is being checked

1. The Studio (a Flutter macOS app that never runs user code) renders a **sprite**, a **frame
   animation** and a **Tiled `.tmx` with its tilesets** from an arbitrary folder on disk, not
   from its own asset bundle (§10, *Q31*, *Q10*).
2. External tilesets (`.tsx`) and relative image paths inside `.tmx`/`.tsx` resolve the way
   Tiled resolves them.
3. Editing, replacing, deleting and re-creating a file on disk shows up without restarting, and
   only what used that file reloads.
4. What forces the Studio to bundle particular Flame / flame_tiled versions (*Q18*).

The sample project's layout is chosen to exercise path resolution:

```
assets/images/hero.png             sprite (32×32)
assets/images/coin.png             4 frames of 16×16
assets/images/props.png            image of a tileset embedded in level.tmx ("../images/props.png")
assets/tilesets/terrain.tsx        external tileset, image="terrain.png", one animated tile
assets/tilesets/terrain.png
assets/maps/level.tmx              tilesets: "../tilesets/terrain.tsx" + embedded "props"
assets/maps/edge.tmx               tileset: "sets/edge.tsx"
assets/maps/sets/edge.tsx          image="img/edge.png"   (→ assets/maps/sets/img/edge.png)
assets/maps/sets/img/edge.png
```

## Quick start

Prerequisites: macOS, Flutter stable (tested with 3.44.2) on your `PATH`, Python 3.
Commands run from `spikes/03_disk_render/`.

### 1. Make a sample project folder

```bash
python3 tool/make_assets.py out/sample
```

`out/` is gitignored. Any folder works; the app never looks at its own bundle.

### 2. Run the viewport on it

```bash
cd studio && FLAME_SPIKE_PROJECT="$PWD/../out/sample" flutter run -d macos
```

Or start it without the variable and type a path into the field (Enter), or use **Browse…**.
The bottom panel lists every slot's status and the files it read.

Environment knobs (all read at runtime):

| Variable | Values | Effect |
|---|---|---|
| `FLAME_SPIKE_PROJECT` | folder | Open it at startup |
| `FLAME_SPIKE_SHOTS` | folder | Save a PNG of the window after every (re)load |
| `FLAME_SPIKE_TILED` | `resolved` (default), `stock` | Tiled loader, see note 2 |
| `FLAME_SPIKE_CACHE` | `generation` (default), `shared` | Image cache strategy, see note 3 |
| `FLAME_SPIKE_SLOW_MS` | ms | Delay every disk read (widens the eviction-to-swap window) |
| `FLAME_SPIKE_KEEP_ATLAS` | `1` | Skip `TiledAtlas.clearCache()` before map builds, see note 4 |

### 3. Edit files while it runs

From another terminal in `spikes/03_disk_render/`, all cases (1.5 s apart):

```bash
python3 tool/edit_cases.py out/sample
```

Or one case: `sprite_inplace`, `anim_atomic`, `tmx_edit`, `tsx_image_atomic`, `edge_image`,
`unrelated_file`, `delete_props`, `recreate_props`. To get back to the original art:

```bash
python3 tool/make_assets.py out/sample
```

### 4. Automated run with latency table

```bash
cd studio && flutter build macos --debug && cd ..
```

```bash
tool/run_cases.sh out/run1
```

```bash
python3 tool/summarize.py out/run1
```

`run_cases.sh` takes environment knobs after the folder, e.g.
`tool/run_cases.sh out/stock FLAME_SPIKE_TILED=stock`. `summarize.py` takes several run folders
and prints medians with ranges.

## Results

macOS 26.2, Apple M4, Flutter 3.44.2, Flame 1.38.2, flame_tiled 3.1.2 (tiled 0.11.1, xml
6.6.1), 2026-10-16. Debug build unless noted.

| Check | Result |
|---|---|
| Sprite from a folder on disk, inside a `GameWidget` | ✅ ([01](screenshots/01_initial.png)) |
| Frame animation from disk (`SpriteAnimation.fromFrameData`) | ✅ |
| `.tmx` + external `.tsx` in another folder (`../tilesets/terrain.tsx`, image next to the `.tsx`) + embedded tileset with `../images/props.png` | ✅ both loaders |
| `.tsx` in a subfolder with its image in a subfolder of that (`sets/edge.tsx` → `img/edge.png`) | ✅ `resolved` · ❌ `stock` flame_tiled loads `assets/maps/img/edge.png` ([09](screenshots/09_stock_flame_tiled_edge_fails.png), note 2) |
| Animated tile defined in the `.tsx` | ✅ loads (frames not checked one by one) |
| Edit / replace a file → only the slots that read it reload, no restart | ✅ every case below ([02](screenshots/02_sprite_edited.png)–[08](screenshots/08_image_recreated.png)) |
| Unrelated file in the project changes | ✅ ignored |
| Deleted image → inline error; re-created → recovers | ✅ ([07](screenshots/07_image_deleted.png), [08](screenshots/08_image_recreated.png)) |
| Initial load (4 slots, 9 files) | 134 ms median (debug), 114 ms (release) |
| Release build (unsandboxed) | ✅ same behavior, write → frame 64–95 ms |
| Sandboxed build (`com.apple.security.app-sandbox` = true) | ❌ `PathAccessException … Operation not permitted` on the first read (expected, §12) |
| Shared `Images` cache with `Images.clear` on change | ⚠️ works at normal speed, but it's a race: with reads slowed to 300 ms the viewport goes blank until the swap, 18 failed asserts ([10](screenshots/10_shared_cache_mid_swap_blank.png), note 3) |
| Without `TiledAtlas.clearCache()` before each map build | ❌ image edits stay stale and maps stop tracking their images ([11](screenshots/11_atlas_cache_kept_stale.png), note 4) |

### Reload latency

`resolved` loader, `generation` cache, debug build, 3 runs (median, range in brackets), ms.
"Write" is when the edit script's write (or rename) returned; "frame" is two frames after the
new component was added, so it's on screen.

| Case | Reloaded | Write → FS event | FS event → frame | Write → frame |
|---|---|---|---|---|
| `hero.png` written in place | sprite | 97 (13–115) | 60 (52–64) | 162 (74–166) |
| `coin.png` temp + rename | animation | 11 (10–105) | 65 (56–66) | 76 (68–172) |
| `level.tmx` written in place | level.tmx | 12 (12–60) | 71 (69–77) | 90 (81–131) |
| `terrain.png` (used via the `.tsx`) temp + rename | level.tmx | 12 (11–95) | 70 (64–77) | 90 (82–159) |
| `sets/img/edge.png` written in place | edge.tmx | 87 (12–113) | 62 (58–71) | 145 (82–175) |
| `notes.txt` (unused) | — ignored | 11 (11–91) | — | — |
| `props.png` deleted | level.tmx → error | 51 (12–112) | 81 (80–87) | 132 (91–199) |
| `props.png` re-created | level.tmx | 108 (49–113) | 73 (68–76) | 176 (125–186) |

FS event → frame is 30 ms of debounce, 2–25 ms of build, and ~33 ms waiting for two frames.
The `stock` loader and the `shared` cache (3 runs each) had the same FS event → frame times
(53–87 ms); their write → frame medians (97–191 ms) differ only by FSEvents' delivery time.

## Notes

**1. Pointing Flame at disk takes one small `AssetBundle`.** `DiskAssetBundle` overrides
`load`, `loadString` and `loadStructuredData` and reads `File(join(root, key))` every time (no
caching of its own). Everything else takes a bundle as a parameter: `Images(bundle:, prefix:)`,
`TiledComponent.load(bundle:, images:, prefix:)`, `RenderableTiledMap.fromTiledMap(images:)`,
`FlameTsxProvider.parse(key, bundle, prefix)`. Nothing global (`Flame.bundle`, `Flame.images`)
has to change, so one viewport per project with its own bundle is possible. Keys are paths
relative to the project root, which are exactly the asset paths a game declares in
`pubspec.yaml`. The same scene reference (`assets/images/hero.png`) therefore loads from disk in
the Studio and from `rootBundle` in the game, which is what the `AssetSource` split in *Q31*
needs. Two things don't carry over: `Images.loadAllImages` / `loadAllFromPattern` read
`AssetManifest.bin`, which a disk folder doesn't have (the Studio lists files itself), and
`Images.prefix` must be empty or end in `/` (an assert).

**2. flame_tiled resolves tileset images with a heuristic, and it can be wrong.** `.tsx` files
are read relative to the map (`prefix` + source), as Tiled does. Tileset images, though, are
loaded through `Images` relative to the *map's* folder, and `TiledAtlas.fromTiledMap`
(`tile_atlas.dart`) only joins the `.tsx` folder in front of the image path **when the two
paths have a different number of segments**. `../tilesets/terrain.tsx` + `terrain.png` (3 vs 1)
works; `sets/edge.tsx` + `img/edge.png` (2 vs 2) loads `assets/maps/img/edge.png` instead of
`assets/maps/sets/img/edge.png`, and the map fails. A game using `TiledComponent.load` from its
bundle fails the same way, so this isn't a disk problem. Also, in `stock` mode the `Images`
cache needs the map's folder as its prefix (keys like `../images/props.png`), so every map
folder gets its own cache and the same PNG can be cached under several keys; and
`TiledComponent.load` asserts the file name has no `/`.

The `resolved` loader (~60 lines) does it like Tiled: read the `.tmx`, parse it with
`TiledMap.fromString` and our own `TsxProvider` (the `.tsx` read from disk), rewrite every
tileset image, per-tile image and image-layer source to a root-relative path resolved against
the file that references it, set `tileset.source = null` so flame_tiled doesn't re-join, then
call `RenderableTiledMap.fromTiledMap` with one root-relative `Images`. Everything public; no
fork. No existing upstream issue found for the heuristic (searched flame-engine/flame for
tsx/tileset path issues; #2814 introduced the join, #3826 fixed a related single-image case).

**3. `Images.clear` disposes the image while it may still be on screen.** `Images` has no way
to forget an entry without calling `Image.dispose()`. In `shared` mode the app clears the
changed files' keys and then rebuilds; until the new component replaces the old one, the old
one draws a disposed image, `Canvas.drawImageRect` fails `assert(!image.debugDisposed)`, and the
frame stops there: everything the world would draw after it is missing
([10](screenshots/10_shared_cache_mid_swap_blank.png); 18 failed asserts in a 300 ms window
with `FLAME_SPIKE_SLOW_MS=300`). At normal speed the rebuild finishes inside one frame and
nothing showed, but it's a race that a large map or a slow disk will lose. The `generation`
mode avoids it: each rebuild loads into a **fresh** `Images`, the new component is swapped in
synchronously (`old.removeFromParent(); world.add(new)`), and the old cache is disposed only
after `await old.removed`. The cost is no sharing of decoded images between slots; the real
Studio wants a project-wide cache that keeps old images alive until nothing draws them
(versioned entries, or handing out `Image.clone()` handles that holders dispose).

Two more `Images` details. A failed load surfaces twice: the `await` throws (the app catches
it and shows the error), and an unhandled async error is logged too, because `_ImageAsset`'s
`.then` has no error handler. And, from the source (`_assets[key] ??= …`), the failed future
stays cached, so a shared cache must clear the key or the file can never load again; the spike
clears changed keys (`shared`) or uses fresh caches (`generation`), so it didn't bite.

**4. flame_tiled has a process-wide atlas cache.** `TiledAtlas.atlasMap` is a `static` map
keyed by the tileset image source strings, independent of the bundle or `Images` passed in.
Without `TiledAtlas.clearCache()` before a map build:

- an edited tileset image keeps showing the old pixels (a single-image map gets a clone of the
  cached atlas, [11](screenshots/11_atlas_cache_kept_stale.png));
- the rebuild doesn't call `Images.load` at all, so dependency tracking loses the image files,
  and later edits to them are ignored;
- from the code (not run): two maps, or two projects, whose tilesets use the same image source
  strings share one atlas entry.

The spike clears it before every map build. A Studio with several open maps will want to drop
only the affected entries (`atlasMap` is public, though `@visibleForTesting`).

**5. Dependency tracking.** Each slot build runs in a `Zone` holding a `Set<String>`;
`DiskAssetBundle.load` and `TrackingImages.load` add the absolute path they stand for (the
latter even on a cache hit, since the bundle only sees the first read). A file event reloads
exactly the slots whose set contains the path. The set from a *failed* build is kept, so it
includes the missing file and re-creating that file triggers the rebuild.

**6. Watching.** `Directory(root).watch(recursive: true)` (FSEvents). Event paths are real
paths: a project opened as `/tmp/x` reports `/private/tmp/x/...`, so the root is resolved with
`resolveSymbolicLinksSync()` first. A temp + rename save arrives as events for both `x.tmp~`
and `x`; a 30 ms debounce coalesces them into one reload. Write → event takes 10–115 ms and
looks bimodal (~12 ms or ~112 ms), which is FSEvents' own coalescing.

**7. Sandbox.** With `com.apple.security.app-sandbox` on, `File.existsSync()` still returns
true but the read fails with `PathAccessException: Cannot open file … (OS Error: Operation not
permitted)`. A sandboxed Studio would need security-scoped bookmarks for every project folder.
The plan's unsandboxed app (§12) avoids that; `DebugProfile.entitlements` and
`Release.entitlements` here both set it to `false`.

**8. Versions (*Q18*).** The Studio reads files, never the user's code, so nothing in disk
rendering ties it to the user's Flame version. It does bundle a matched pair: flame_tiled 3.1.2
requires `flame ^1.38.0` and Flutter ≥ 3.41, and pins `tiled ^0.11` → `xml ^6` (xml 7.1 is out
but can't be used). What matters is that the Studio's rendering matches what the game's
flame_tiled does with the same files, and Flame's main branch (unreleased, on the 2.0 train)
already changes exactly the APIs this spike uses:

- flame-engine/flame#4015 removes `prefix` from `Images`, `AssetsCache` and flame_tiled
  (`TiledComponent.load`, `fromFile`/`fromString`, `FlameTsxProvider.parse`); keys become full
  bundle paths, the "no `/` in the file name" assert goes away, and tileset/image-layer images
  resolve against a new `imagesDirectory` argument (default `assets/images/`).
- flame-engine/flame#4073 moves flame_tiled to tiled 0.12: `TsxProvider` is replaced by
  `ParserProvider`, external files are loaded through a loader called with paths relative to
  the map, and xml 7 is required.

Both are breaking for this spike's loader (`TrackingImages` prefix, `_DiskTsx`). Whether tiled
0.12 resolves `.tsx`-relative images correctly wasn't checked; re-run `edge.tmx` when it's
released.

**9. Testing pitfalls.** Flutter's error reports didn't show up in the app's stdout (launched
directly, not via `flutter run`), so the failed asserts in note 3 were at first invisible: only
the blank screenshot gave them away. The app now routes `FlutterError.onError` into its JSON
log. Also, `flutter run` passes the environment through
to the app, so the knobs work with it as well as with the built binary.

**Not exercised:** the **Browse…** button (`file_selector`'s folder panel) wasn't clicked in
the automated runs; the folder came from `FLAME_SPIKE_PROJECT`, read at runtime. Tiled features
beyond orthogonal tile layers (object layers, image layers, templates, infinite maps,
collection-of-images tilesets) weren't in the sample, though the `resolved` loader rebases image
layers and per-tile images too.
