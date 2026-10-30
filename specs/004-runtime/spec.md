# Feature Specification: Runtime

**Feature Branch**: `specs/004-runtime`

**Created**: 2026-10-20

**Status**: Draft

**Input**: User description: "#8 Runtime (pyro_runtime, full scope per dev-docs/project-plan.md §14
and dev-docs/phases.md Phase 2): PyroScene.load with the two-pass loading order (reads each Scene
with SceneCodec.decode and calls warnAboutRepairs after it, FR-024a), building the built-in Node
kinds and custom ones through the Registry, AssetSource and asset fields (the Q78 loader), lookup
API (find, findAll, paths), unknown-type handling (Q58), Hot-swap (onHotReload, content hash,
onReloaded, the stale-reference warning; Q66, Q67, Q71). §6.2, §10"

## Overview

The Runtime is the part of Pyro that ships inside the developer's game. A game calls
`PyroScene.load` with a Scene's asset path and the generated Registry and gets back one Flame
component holding the whole Scene. The developer adds it to their world and looks up the Nodes
their code needs by name, tag or path. Nothing in it depends on Pyro running (*Q64*): a game
started from the IDE, from CI or as a release build loads its Scenes the same way.

In debug builds the same component also does Hot-swap. When Pyro (or anyone) hot-reloads the game
after a Scene file changed, the Scene rebuilds itself in the running game and tells the game to
redo its lookups (*Q66, Q67, Q71*).

It is the last piece of Phase 2 (project-plan §6.2, §10, §14 item 8; phases.md #8). It builds on
what is already in `pyro_runtime`: the Scene format and its reader (spec 001), the repair warning
(spec 001 FR-024a) and the Registry contract the Generator writes into games (spec 003). Pyro's
own disk-backed asset source and preview components (#4, #6), the Play button that triggers the
reload (#11) and the CI contract test on `example/` (#12) are separate items.

**Who uses it**

- **Game developer**: loads Scenes, looks up Nodes from game code, reads the Runtime's errors and
  debug warnings, and re-runs lookups after a Hot-swap.
- **Pyro** (#11): saves a Scene and hot-reloads the running game, relying on the Scene to rebuild
  itself only when its content changed.
- **Pyro's viewport** (#4): supplies a disk-backed asset source through the same seam the game uses
  for its bundle, so assets load from the same paths in both (*Q31, Q79*).
- **CI** (the contract test, #12): loads every `example/` Scene against the real Registry.

## Clarifications

### Session 2026-10-20

- Q: How does a `SpriteAnimation` Override name one animation of a multi-animation `.anim.json`
  file? → A: With a second key in the asset reference: `{"asset": "assets/anims/goblin.anim.json",
  "animation": "walk"}`. The value stays one tagged asset reference, so Pyro still finds and
  rewrites every asset path without the Manifest (*Q27*, *Q91*), and the animation name is a
  structured value rather than syntax hidden inside the path (asset keys may contain `#`). It
  amends spec 001's v1 contract, which allowed only `{"asset": path}`. No released file uses it
  yet, so `schemaVersion` stays 1 (FR-034).
- Q: Which uses of a stale reference does the debug warning detect? → A: The uses the Runtime can
  observe cheaply: a removed component's transform changing, the component being added to a tree
  again, or it being passed to a `PyroScene` API. Method calls and field reads on it go unnoticed.
- Q: How long may a load or a rebuild block the game's isolate (constitution III: parsing a large
  file must not block a frame)? → A: Measure it first. The benchmark records the longest
  synchronous pause during a load and during a rebuild of the 1,000-Node Scene. The limit, and
  whether the builder must yield between passes, is decided from that measurement on the
  reference Mac (tasks T042, T043).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Load a Scene into a game (Priority: P1)

A developer has `assets/scenes/level1.scene.json`, saved by Pyro. It holds a goblin entity with a
`Patrol` Behavior, a sprite and a rectangle hitbox under it, and a `Player` Custom component with
two Overrides. In their `FlameGame.onLoad` they call `PyroScene.load` with the path and
`pyroRegistry` and add the result to the world. The game starts with the goblin and the player
where Pyro placed them. The goblin's sprite shows the right region of its sheet. Patrol's `speed`
is the Override from the Scene, and its `direction` is the default from code. Patrol's `target`
already points at the player when `Patrol.onLoad` runs.

**Why this priority**: this is the item's reason to exist. Without it no Scene made in Pyro can
appear in a game, and Phase 3's vertical slice can't start.

**Independent Test**: in a headless Flame test game, load fixture Scenes covering every Node kind
and every Field type with a hand-written Registry. Check the resulting component tree, every
built-in property and every field value.

**Acceptance Scenarios**:

1. **Given** a Scene with every built-in Node kind (root, entity, sprite, rectangle hitbox, circle
   hitbox) and a Custom component, **When** it is loaded, **Then** the result is one component for
   the root whose children mirror the Scene's tree. The children are in `childIds` order and each
   Node is the matching Flame component: an entity, a sprite, a rectangle hitbox, a circle hitbox,
   or the Custom component's class created through the Registry.
2. **Given** positioned Nodes with transforms, **When** the Scene is loaded, **Then** each
   component's position, size, scale, angle and anchor equal the Scene's, including custom
   anchors.
3. **Given** a sprite Node with and without a source region, **When** the Scene is loaded,
   **Then** the sprite draws the whole image or exactly that region.
4. **Given** hitbox Nodes, **When** the Scene is loaded, **Then** each hitbox has the Scene's
   position, size or radius, angle (rectangles), anchor, collision type and solidity.
5. **Given** an entity or Custom component Node with Behaviors, **When** the Scene is loaded,
   **Then** each Behavior is created through the Registry and attached to its Node in the
   Scene's order.
6. **Given** a Behavior or Custom component with Overrides of every v1 Field type (`int`,
   `double`, `bool`, `String`, an enum, `Vector2`, `Color`, `ImagePath`, `Sprite`,
   `SpriteAnimation`, an entity reference), **When** the Scene is loaded, **Then** each field
   holds the converted Override value and every field without an Override keeps its default from
   code (ADR 0003).
7. **Given** components and Behaviors whose `onLoad` reads their Editable fields, **When** the
   Scene is loaded and added to the game, **Then** every `onLoad` already sees its Overrides, its
   loaded assets and its resolved entity references. The loading order is: construct every Node,
   assign Overrides and load asset fields, resolve entity references, add to the tree (§6.2).
8. **Given** an entity reference to a Node anywhere in the same Scene, including one later in
   the file, the root, or the referencing Node itself, **When** the Scene is loaded, **Then** the
   field holds that Node's component.
9. **Given** a Scene whose tree the reader had to repair (an orphan, a Node listed under two
   parents), **When** it is loaded in a debug build, **Then** it loads with the repaired tree and
   one warning lists the repairs (spec 001 FR-024a). In a release build it loads silently.
10. **Given** a game that loads the same Scene twice, or two different Scenes, **When** both are
    in the world, **Then** each is independent: its own components, its own lookups.

---

### User Story 2 - Clear errors when code and Scene disagree (Priority: P1)

A developer deletes the `Patrol` class and runs the game. `PyroScene.load` fails. Its error names
the Scene file, the Node (by name and ID) and the Type ID `Patrol`, and says how to keep going.
The developer passes `onUnknownType: UnknownType.skip` while they finish a refactor. The Scene
loads without that Behavior, and a debug warning lists what was skipped. Later they change a field
from `int` to `bool` in code. The next load fails and names the Scene, the Node, the field, the
value in the file and the type the code now expects.

**Why this priority**: code and data drift all the time in this workflow (§11). An error that
doesn't say which Scene, Node and type, or a load that silently builds the wrong thing, makes
every refactor a debugging session. *Q58* chose failing loudly by default.

**Independent Test**: load one fixture Scene per error case with a hand-written Registry. Check
what each load does (error, skip or warning) and that each message names the Scene, the Node and
the type, field or path involved.

**Acceptance Scenarios**:

1. **Given** a Node or Behavior whose Type ID the Registry doesn't have, **When** the Scene is
   loaded with the default setting, **Then** the load fails with an error naming the Scene, the
   Node and the Type ID, and suggesting `onUnknownType: UnknownType.skip` (*Q58*).
2. **Given** the same Scene, **When** it is loaded with `onUnknownType: UnknownType.skip`,
   **Then** it loads. An unknown Behavior is left out and its Node stays. A Node of an unknown
   Custom component type is left out together with everything under it. A debug warning lists
   every skipped Node and Behavior.
3. **Given** a Node of a kind this version doesn't know (kept by the reader as an unknown Node),
   **When** the Scene is loaded, **Then** it is treated like an unknown Type ID: an error naming
   the kind by default, or skipped with its subtree and a warning under `UnknownType.skip`.
4. **Given** an Override value that doesn't fit its field (a string for a `bool`, an enum value
   name the enum doesn't have, a malformed colour, `1.5` for an `int`, `null` for a non-nullable
   field), **When** the Scene is loaded, **Then** the load fails with an error naming the Scene,
   the Node, the Type ID, the field, the value and the expected Field type.
5. **Given** an Override whose value converts without loss (`80` for a `double`, `2.0` for an
   `int`), **When** the Scene is loaded, **Then** it is converted silently.
6. **Given** an Override for a field the Registry doesn't list (a field removed from code),
   **When** the Scene is loaded, **Then** it loads, the value is ignored, and a debug warning names
   the Scene, the Node, the Type ID and the field (§11, "Unused values").
7. **Given** an entity reference to a Node ID that isn't in the Scene, or to a Node whose
   component isn't of the field's type, **When** the Scene is loaded, **Then** the load fails with
   an error naming the Scene, the referencing Node, the field and the target.
8. **Given** an entity reference to a Node that was left out under `UnknownType.skip`, **When**
   the Scene is loaded, **Then** the field stays `null` and the skip warning names the reference.
9. **Given** a sprite Node, a `Sprite`, `SpriteAnimation` or animation file whose asset can't be
   loaded (missing, not an image, malformed animation file, or a `SpriteAnimation` Override
   naming an animation the file doesn't hold), **When** the Scene is loaded, **Then** the load
   fails with an error naming the Scene, the Node, the field (where there is one) and the asset
   path, and, for an unknown animation, the animations the file holds. A `SpriteAnimation`
   Override with no animation name is a value mismatch (#4).
10. **Given** Behaviors on a Custom component that can't hold Behaviors, or a Behavior whose
    required parent type the Node's component doesn't satisfy, **When** the Scene is loaded,
    **Then** the load fails with an error naming the Scene, the Node and the Behavior's Type ID.
11. **Given** a Scene file that is missing, isn't valid JSON, or has a newer `schemaVersion`,
    **When** it is loaded, **Then** the load fails with the reader's error (spec 001), wrapped so
    it names the Scene's asset path.
12. **Given** a Custom component or Behavior whose constructor or field setter throws, **When**
    the Scene is loaded, **Then** the load fails with an error naming the Scene, the Node and the
    Type ID, keeping the original error and stack trace.

---

### User Story 3 - Find Nodes from game code (Priority: P1)

After loading `level1`, the game looks up `scene.find<Player>('player')`, every enemy with
`scene.findAll(tag: 'enemy')`, and the boss with `scene.find<Boss>('arena/boss')`, because there
are two Nodes named `boss` in the Scene. It does this straight after `load` returns, before the
Scene is mounted. When a lookup goes wrong, the error says what matched and how to fix it.

**Why this priority**: lookups are how game logic connects to a Scene built in Pyro (§6.2). Node
names aren't unique (*Q51*), so ambiguity has to fail clearly rather than return an arbitrary
Node.

**Independent Test**: load a fixture Scene with repeated names, tags and nested paths, then call
every lookup form and check its results and its errors.

**Acceptance Scenarios**:

1. **Given** exactly one Node named `player`, **When** game code calls `find<Player>('player')`,
   **Then** it returns that Node's component.
2. **Given** two Nodes named `boss` under different parents, **When** game code calls
   `find('boss')`, **Then** it fails with an error that lists both Nodes' paths and points to
   `findAll` or a path.
3. **Given** the path `arena/boss`, **When** game code calls `find` with it, **Then** it matches
   the Node named `boss` whose parent is named `arena`, at any depth. A path that starts with `/`
   matches from the Scene's root only. A path that still matches several Nodes fails like an
   ambiguous name.
4. **Given** no matching Node, **When** game code calls `find`, **Then** it fails with an error
   naming the Scene and the name or path. **Given** one match whose component isn't a `T`,
   **Then** it fails naming the Node, its actual type and `T`.
5. **Given** Nodes tagged `enemy`, **When** game code calls `findAll(tag: 'enemy')`, **Then** it
   returns all of them in tree order (depth first, in `childIds` order). `findAll` also filters by
   name or path and by component type, and returns an empty list when nothing matches.
6. **Given** a Scene that has just been loaded but not yet added to a game, **When** game code
   calls any lookup, **Then** it works as it would on a mounted Scene.

---

### User Story 4 - Hot-swap a saved Scene in the running game (Priority: P1)

The developer presses Play in Pyro and their game runs on macOS. They move the goblin in Pyro and
save. About a second later the goblin stands in its new place in the running game. The game's
`onReloaded` callback has re-run its lookups, so `player` points at the new player. Next they
change only a method in their IDE and hot-reload. The Scene isn't rebuilt and the player keeps its
health. When the game still uses an old `player` reference somewhere it forgot to refresh, a debug
warning says so the first time.

**Why this priority**: the save-to-device loop is the product loop of the early preview (*Q82*,
constitution III). Spike #1 proved the mechanism; this item makes it the real Runtime.

**Independent Test**: in a headless Flame test, load a Scene, change the bytes its asset source
returns, trigger a hot reload and check the rebuild and the callback. Leave the bytes unchanged,
reload again and check that nothing was rebuilt.

**Acceptance Scenarios**:

1. **Given** a mounted Scene in a debug build whose file has changed, **When** the game is
   hot-reloaded, **Then** the Scene re-reads its file, sees that the content differs from what it
   loaded, rebuilds all of its Nodes from the new content, and calls `onReloaded` with itself once
   the new Nodes are in place (*Q67*).
2. **Given** a hot reload where neither the Scene file nor any animation file it uses changed (a
   Dart-only reload, or a second reload of the same save), **When** it happens, **Then** nothing
   is rebuilt, `onReloaded` isn't called, and the Scene's Nodes keep their runtime state (*Q66*).
3. **Given** an animation file used by the Scene that changed while the Scene file didn't, **When**
   the game is hot-reloaded, **Then** the Scene rebuilds with the new animation data, and the old
   cached animation data isn't reused (*Q72*).
4. **Given** a changed image file only, **When** the game is hot-reloaded, **Then** the Scene isn't
   rebuilt. Images aren't part of the comparison, and Pyro offers a restart for them instead
   (*Q72*).
5. **Given** a changed Scene file that no longer loads (malformed JSON mid-edit, an unknown Type
   ID, a bad Override), **When** the game is hot-reloaded, **Then** the current Scene keeps
   running unchanged, `onReloaded` isn't called, and a debug error names the Scene and the cause.
   A later reload with a fixed file rebuilds as usual.
6. **Given** a rebuilt Scene, **When** game code calls a lookup on it, **Then** it returns the new
   components. The `PyroScene` the game holds stays the same object, still in the world.
7. **Given** a component of a removed Node that game code kept from before a rebuild, **When**
   game code changes its transform, adds it to a tree again or passes it to a `PyroScene` API,
   **Then** a debug warning names the Scene, the Node and `onReloaded`, once per Node per rebuild
   (*Q71*).
8. **Given** a release build, **When** the game runs, **Then** no Hot-swap work happens and its
   code is left out of the build (constitution III).

---

### User Story 5 - Same paths in Pyro and the game (Priority: P2)

Pyro's viewport (#4) loads sprites and animations from the project folder on disk, while the game
loads them from its asset bundle. Both use the same project-relative paths that the game declares
in `pubspec.yaml`, so a Scene that renders in Pyro also loads in the game (*Q31, Q78, Q79*).

**Why this priority**: the seam is small, but #4 depends on it, and getting it wrong lets a Scene
look right in Pyro and fail in the game (ARCHITECTURE.md, spike #3 finding 2).

**Independent Test**: load the same fixture Scene with the default bundle-backed source and with a
test source that serves files from memory. Check that the same paths are requested and the same
assets come back.

**Acceptance Scenarios**:

1. **Given** a game that passes no asset source, **When** a Scene is loaded, **Then** every image,
   animation file and the Scene itself are read from the game's asset bundle by their
   project-relative path (`assets/images/goblin.png`), with no prefix added.
2. **Given** a caller that passes its own asset source, **When** a Scene is loaded, **Then** every
   read goes through that source and none through the game's bundle or Flame's global caches.
3. **Given** two Nodes that use the same image, **When** the Scene is loaded, **Then** the image is
   read and decoded once for that Scene.

---

### Edge Cases

- **An empty Scene** (only the root): loads as an empty component, and lookups find nothing.
- **A Node with no name**: never matched by name or path, but still found by tag and type.
- **A Node name that contains `/`**: it can't be found by name or path, because lookups read `/` as
  a path separator. `findAll` still finds it by tag or type, and the hierarchy panel (#3) warns
  about such names.
- **An entity reference that points at a Behavior**: impossible, since Behaviors aren't Nodes; a
  reference always targets a Node's component.
- **A reference cycle** (A references B, B references A): fine, because references are assigned
  after every Node exists.
- **A Custom component that changes its own transform or children in `onLoad`**: its code wins.
  The Runtime has already applied the Scene's values and doesn't re-apply them.
- **A hitbox directly under the root**: the load fails naming the Node. Flame needs a hitbox inside
  a positioned component (an entity, sprite or Custom component) that owns its collisions, and
  refuses one without (found while implementing, 2026-10-20).
- **Hitboxes in a game without collision detection**: they load. Detecting collisions stays the
  game's job (Flame's `HasCollisionDetection`), as in hand-written Flame code.
- **A hot reload while the Scene isn't mounted** (loaded but not added, or removed): Flame doesn't
  notify it, so nothing happens. The next reload after it is mounted again compares as usual.
- **Two hot reloads in quick succession**: rebuilds don't overlap. The Scene ends on the latest
  content, and `onReloaded` is called once per rebuild that completed.
- **A game without an `onReloaded` callback**: Hot-swap still rebuilds the Scene. References the
  game kept go stale, and the stale-reference warning covers them.
- **A field typed as a supertype of its reference target** (`PositionComponent? target` pointing at
  a sprite Node): accepted, since a reference accepts any subtype (*Q57*).
- **A `String` Override that looks like a path**: stays text. Only `ImagePath`, `Sprite` and
  `SpriteAnimation` fields load or wrap assets.
- **An `ImagePath` field**: set to the path only. The image isn't loaded, so the game decides
  when to load it.
- **The same Behavior type twice on one Node**: both are created and attached, in order.

## Requirements *(mandatory)*

### Functional Requirements

**Loading**

- **FR-001**: The Runtime MUST provide `PyroScene.load`, which takes a Scene's project-relative
  asset path, the game's Registry, and optionally an unknown-type policy, an `onReloaded`
  callback and an asset source. It returns a Flame component that stands for the Scene's root
  and holds the whole Scene (§6.2). It MUST work in any `FlameGame` with no base class or mixin
  required of the game (*Q30*).
- **FR-002**: Loading MUST read the Scene with the Scene format's reader (spec 001). In debug
  builds it MUST call the repair warning with the Scene's asset path whenever the tree was
  repaired (spec 001 FR-024a).
- **FR-003**: Loading MUST follow this order: (1) construct a component for every Node and every
  Behavior; (2) apply built-in properties and transforms, assign Overrides and load asset fields;
  (3) resolve entity references; (4) attach Behaviors and children in Scene order. Every user
  `onLoad` then runs after all four steps, so it sees configured fields (§6.2).
- **FR-004**: `PyroScene.load` MUST complete only after every asset the Scene needs has been
  loaded, or fail with the first error found. On failure it MUST leave no partly built Scene for
  the caller.

**Built-in Node kinds**

- **FR-005**: Each built-in Node kind of `schemaVersion` 1 MUST become the matching Flame
  component:
  - the root becomes the `PyroScene` itself;
  - `entity` becomes a `flame_behaviors` entity that can hold Behaviors;
  - `sprite` becomes a sprite component showing its image, or the given source region of it;
  - `rectangleHitbox` and `circleHitbox` become Flame's rectangle and circle hitboxes.
- **FR-006**: Every transform and hitbox property in the Scene MUST be applied exactly: position,
  size, scale, angle, anchor (named or custom) and, for hitboxes, radius, collision type and
  solidity.

**Custom components and Behaviors**

- **FR-007**: A `custom` Node and every Behavior MUST be created through the Registry by Type ID,
  with the Registry's role checked: a Behavior Type ID MUST NOT build a Node, and the reverse.
  A role mismatch is an error naming the Scene, the Node and the Type ID.
- **FR-008**: Behaviors MUST only be attached to Nodes whose component can hold them and whose
  type satisfies the Behavior's required parent type. Otherwise the load fails with an error
  naming the Scene, the Node and the Behavior's Type ID.

**Overrides and Field types**

- **FR-009**: Each Override MUST be converted from its written form (*Q91*, spec 001 contract) to
  the value its Field type expects, checked with the Registry's `accepts`, then assigned with its
  `set`:
  - numbers become `int` or `double`;
  - booleans, strings and enum value names become their values;
  - `[x, y]` becomes `Vector2`;
  - `"#AARRGGBB"` becomes `Color`;
  - `{"asset": path}` becomes `ImagePath` or a loaded `Sprite` (the whole image);
  - `{"asset": path, "animation": name}` becomes a loaded `SpriteAnimation` (FR-010);
  - `{"ref": id}` becomes the referenced Node's component.
- **FR-010**: A `SpriteAnimation` Override MUST be `{"asset": path, "animation": name}`: the
  `.anim.json` file (§7.2) and the name of one animation in it. A missing `animation` key is a
  value mismatch (FR-011). A name the file doesn't hold fails the load with an error naming the
  Scene, the Node, the field, the file and the animations it does hold. An `animation` key on any
  other Field type is a mismatch (FR-011). The Runtime MUST read the animation file format,
  including grids, per-frame step times and looping, and MUST refuse a newer `schemaVersion` in it
  as it does for Scenes.
- **FR-011**: Lossless number conversions (an integral number for `double`, an integral `2.0` for
  `int`) MUST be accepted silently. Every other mismatch MUST fail the load with an error naming
  the Scene, the Node, the Type ID, the field, the written value and the expected Field type.
- **FR-012**: An Override for a field the Registry doesn't list MUST be ignored with a debug
  warning naming the Scene, the Node, the Type ID and the field. The Runtime never changes the
  file.
- **FR-013**: A field with no Override MUST keep its default from code (ADR 0003, *Q46*).

**Entity references**

- **FR-014**: An entity reference MUST resolve to the component of the referenced Node in the
  same Scene (*Q56*), after every Node exists. A missing target, or a target whose component the
  field doesn't accept, MUST fail the load with an error naming the Scene, the Node, the field and
  the target's Node ID. A reference to a Node skipped under `UnknownType.skip` leaves the field
  `null` and is listed in the skip warning.

**Unknown types**

- **FR-015**: By default an unknown Type ID (on a Node or a Behavior) or an unknown Node kind MUST
  fail the load with an error naming the Scene, the Node (name and ID) and the Type ID or kind,
  and suggesting `UnknownType.skip` (*Q58*).
- **FR-016**: Under `UnknownType.skip` an unknown Behavior MUST be left out and its Node kept. A
  Node of an unknown type or kind MUST be left out with its whole subtree. In debug builds one
  warning per load MUST list everything left out.

**Errors**

- **FR-017**: Every load failure MUST be one Runtime error type whose message names the Scene's
  asset path and, where they apply, the Node (name and ID), the Type ID, the field and the asset
  path. It MUST keep the underlying error and stack trace (constitution I).
- **FR-018**: Errors thrown by user code during loading (a constructor or a field setter) MUST be
  reported as in FR-017, naming the Type ID whose code threw.

**Lookups**

- **FR-019**: `PyroScene` MUST provide `find<T>(nameOrPath)`. It returns the one Node component
  that matches, and fails if none or more than one matches, or if the match isn't a `T`. Each
  error names the Scene, what was searched and, for ambiguity, every matching Node's path, and
  points to `findAll` or a path (§6.2, *Q51*).
- **FR-020**: A path is Node names joined by `/`. It matches a Node whose name is the last segment
  and whose ancestors, nearest first, carry the earlier segments. A leading `/` anchors the path
  at the Scene's root. A single name is a one-segment path.
- **FR-021**: `PyroScene` MUST provide `findAll<T>({name or path, tag})`, which returns every
  matching Node component in tree order (depth first, `childIds` order). Filters combine. An
  empty result is not an error.
- **FR-022**: Lookups MUST work as soon as `load` returns, whether or not the Scene is mounted. They
  MUST only return components of the current Scene version.

**Hot-swap (debug builds only)**

- **FR-023**: In debug builds a mounted `PyroScene` MUST react to Flame's hot-reload notification
  (*Q66*, Flame ≥ 1.36). It re-reads its Scene file and every animation file the Scene used, and
  compares their content with what it built from.
- **FR-024**: If the content is unchanged, the Scene MUST do nothing (*Q67*).
- **FR-025**: If it changed, the Scene MUST drop the cached data of the changed files, build the
  new content completely, and only then swap: remove every old Node component, add the new ones,
  and call `onReloaded` with itself. The `PyroScene` stays the same object in the same parent.
  `onReloaded` runs once the new Nodes are in the tree and lookups return them, before their own
  `onLoad`s have run, as after `load`. Images aren't compared and their caches aren't cleared
  (*Q72*).
- **FR-026**: If the new content fails to load, the Scene MUST keep the old Nodes running, MUST
  NOT call `onReloaded`, and MUST print a debug error naming the Scene and the cause.
- **FR-027**: Rebuilds MUST NOT overlap. A reload that arrives during a rebuild is handled after
  it, against the content as it is then.
- **FR-028**: After a rebuild, the debug build MUST warn the first time game code uses a component
  of a removed Node (*Q71*, provisional): when its transform changes, when it is added to a tree
  again, or when it is passed to a `PyroScene` API. The warning names the Scene and the Node and
  points to `onReloaded`, once per Node per rebuild. Other uses (method calls, field reads) are
  not detected. `PyroScene` v0.1 has no API that takes a component, so that case applies to APIs
  added later. The detection MUST add no work to Nodes of the current Scene version.
- **FR-029**: In release builds every Hot-swap path MUST be inactive and removable by the
  compiler (constitution III). Profile builds behave like release builds.

**Assets**

- **FR-030**: Every file the Runtime reads (the Scene, animation files, images) MUST go through
  one asset source per load, keyed by project-relative path with no prefix added (*Q31, Q79*).
  The default reads the game's asset bundle. A caller MAY pass another source (Pyro's disk
  source, a test source), and then nothing is read from the bundle or Flame's global caches.
- **FR-031**: Within one Scene, each image MUST be read and decoded once however many Nodes and
  fields use it.

**Cost and footprint**

- **FR-032**: After a Scene is loaded, the Runtime MUST add no per-frame work beyond the Flame
  components it built (constitution III).
- **FR-033**: The Runtime MUST NOT add package dependencies beyond what `pyro_runtime` already
  declares (Flutter, Flame, `flame_behaviors`, `pyro_annotations`) unless the plan justifies one
  (constitution II).

**Scene format amendment**

- **FR-034**: The Scene format (spec 001 contract, `schemaVersion` 1) MUST accept and write an
  asset reference with an optional second key, `animation` (a non-empty string):
  `{"asset": path, "animation": name}`. It reads, round-trips and is found by asset-path rewriting
  like `{"asset": path}`, and any other extra key still makes the value an ordinary JSON value.
  `schemaVersion` stays 1, since no released file uses the form yet. Spec 001's contract,
  project-plan §7.1 and the Generator's written-form table are updated in the same change.

### Key Entities

- **PyroScene**: the Flame component a loaded Scene becomes. It stands for the Scene's root, owns
  the Node components, answers lookups and, in debug builds, Hot-swaps itself.
- **Node component**: the Flame component built for one Node: a built-in kind's component or a
  Custom component from the Registry.
- **Unknown-type policy**: what a load does with Type IDs and Node kinds it doesn't know: fail
  (default) or skip.
- **Asset source**: where a load reads every file from, by project-relative path. The game's bundle
  by default, Pyro's disk folder in the viewport.
- **Animation file** (`.anim.json`): one spritesheet's named animations (§7.2), which
  `SpriteAnimation` fields load from.
- **Runtime error**: a failed load. It names the Scene and the Node, Type ID, field or asset
  involved.
- **Stale reference**: a component of a Node that a Hot-swap removed, still held by game code.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Fixture Scenes covering every built-in Node kind, a Custom component, Behaviors and
  every v1 Field type load in a headless Flame test with a hand-written Registry. Every built-in
  property, transform and field value matches the Scene or the code default, and every user
  `onLoad` sees its configured fields.
- **SC-002**: 100% of the error cases in User Story 2 have a fixture. Every message names the
  Scene's asset path and the Node, plus the Type ID, field or asset path where there is one.
- **SC-003**: Across 100 simulated hot reloads alternating changed and unchanged content, every
  changed one rebuilds once and calls `onReloaded` once, and every unchanged one rebuilds nothing.
- **SC-004**: On the reference Mac, loading the 1,000-Node benchmark Scene takes a median under
  50 ms, excluding image decoding. A Hot-swap check that finds nothing changed takes under 5 ms.
  A rebuild of that Scene takes under 100 ms, within the ~1 s save-to-device loop (constitution
  III). The longest synchronous pause of the game's isolate during a load and during a rebuild is
  measured and recorded. Its limit is set once it has been measured on the reference Mac
  (Clarifications).
- **SC-005**: Every lookup form returns the expected Nodes on a fixture with repeated names, tags
  and nested paths. Every ambiguous or failed lookup's error lists the matching paths or what was
  searched.
- **SC-006**: In a release build, the Hot-swap code paths are absent from the compiled game
  (checked against a release build of a small app that loads a Scene), and a loaded Scene adds no
  per-frame cost beyond its components.

## Assumptions

- **Scope** is §14 item 8 in full (~4 evenings): loader, two-pass references, assets, lookups,
  unknown types, Hot-swap. The Tiled map Node kind and its shared loader (*Q78*) arrive in v0.2.
  This item provides the asset-source seam that loader will use, not the loader. Animated sprite
  Nodes (v0.1.1), prefab instances (v0.2) and node-level patching (v0.4) are out of scope. Typed
  accessors (`Level1Scene.player`) come in v0.4.
- **Entity Nodes** become `flame_behaviors` `PositionedEntity`s, and a Custom component holds
  Behaviors only if it mixes in `EntityMixin` (*Q50*). A Behavior's required parent type is
  checked against the Node component's type at load.
- **Lookups** are by Node name, path, tag and type only. Lookup by Node ID and lookups of
  Behaviors (use `flame_behaviors`' own) are not part of v0.1.
- **The content comparison** for Hot-swap is over the bytes the Runtime read, so a change in
  whitespace alone also rebuilds. Pyro writes the canonical form, so this only happens after a
  hand edit.
- **Hot-swap is triggered by Flame's notification only.** Pyro's daemon reload (#11) and the IDE's
  hot reload both cause it. A hot restart reloads everything anyway.
- **Missing assets fail the load.** In the game a missing asset is an error the developer must
  see. Pyro's viewport (#4) shows its own inline error instead (§11).
- **Pyro's viewport** may reuse the built-in kinds' construction for its preview components (#6),
  but this item promises no API for that beyond the asset source.
- **The animation-name key** is one of this item's decisions (Clarifications); it is recorded in
  `decisions.md` with the others when the feature is implemented. `Sprite` fields keep the
  one-key form (the whole image); a region key for them is not part of v0.1.
- **Docs**: §14, phases.md and `decisions.md` are updated when this feature is implemented, as
  specs 001–003 did. `GLOSSARY.md` gains any new term (asset source, stale reference) in the same
  change.
