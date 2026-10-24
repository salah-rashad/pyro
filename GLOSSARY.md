# Pyro

A desktop editor for games made with the Flame engine: developers compose scenes visually while all
game logic stays in plain Dart in their own IDE.

## Language

### Tools and packages

**Pyro**:
The desktop app (*Q86*).
_Avoid_: Flame Studio (reserved by the Flame team), Studio, Editor (as a product name), IDE

**Runtime**:
The package shipped inside the user's game that loads scenes into Flame.

**Generator**:
The build-time tool that inspects the user's annotated classes and produces the Registry and the Manifest.

### Scenes

**Scene**:
A file holding a tree of Nodes that the Runtime loads into a running game.
_Avoid_: Level, map

**Node**:
One element of a Scene's tree, such as an Entity, a sprite, a hitbox or a Prefab instance.
_Avoid_: Object, game object, element

**Node kind**:
What sort of thing a Node is: a built-in sort (root, entity, sprite, hitbox, prefab instance) or a Custom component.
_Avoid_: Kind (unqualified), node type

**Entity**:
A Node that can hold Behaviors. In a game its component is a `PyroEntity`.

**Behavior**:
A user-written Dart class holding logic, attached to an Entity.
_Avoid_: Script

**Custom component**:
A Node whose class is a user-written Flame component rather than a built-in Node kind.

**Prefab**:
A Scene used inside other Scenes by reference.

**Prefab instance**:
A Node that places a Prefab inside another Scene.

**Node name**:
A human-chosen label on a Node, used to look it up from game code; not required to be unique.

**Node ID**:
The stable identifier of a Node within its Scene; it never changes when the Node is renamed, moved or edited.
_Avoid_: UUID (as a term)

**Canonical form**:
The one exact way Pyro writes a Scene file, so saving an unchanged Scene changes no bytes.

**Repair report**:
The list of inconsistencies in a Scene's tree that reading found and fixed (an orphan, a Node under two parents, a missing child…), each naming the Nodes involved.
_Avoid_: Fix log, migration

### User types and their fields

**Type ID**:
The stable identifier a Scene uses to name a user's Behavior or Custom component class: the class name unless the developer gives an explicit one.
_Avoid_: Class path, fully qualified name

**Type role**:
Whether a user type is a Behavior or a Custom component.
_Avoid_: Kind (for types)

**Parent type**:
The Node type a Behavior requires (`Enemy` in `Behavior<Enemy>`); Pyro offers the Behavior only on Nodes of that type or a subtype.
_Avoid_: Owner type, host type

**Editable field**:
A field of a user type that Pyro lets the developer set per Node.

**Field type**:
The value type of an Editable field (number, text, enum, vector, colour, asset reference, entity reference).
_Avoid_: Kind (for fields)

**Image path**:
The Field type of an Editable field holding a project-root-relative image path, declared with `ImagePath` from `pyro_annotations`; a plain `String` field is always text.
_Avoid_: Asset string

**Animation file**:
A `*.anim.json` file holding one spritesheet's named animations; a `SpriteAnimation` Override names the file and one of its animations.
_Avoid_: Animation sheet

**Asset source**:
Where the Runtime and Pyro read a Scene's files from, by project-relative path: the game's asset bundle in a game, the project folder on disk in Pyro.
_Avoid_: Asset loader, asset provider

**Override**:
A value the developer explicitly set for an Editable field on a Node; it is saved in the Scene. A field with no Override takes its default from code.
_Avoid_: Saved value, custom value

**Registry**:
Generated code shipped in the game that lets the Runtime create user types and set their Editable fields.
_Avoid_: Type registry

**Manifest**:
Generated data describing the user's annotated types and their Editable fields, read by Pyro.
_Avoid_: types.json

**Generator error** / **Generator warning**:
A broken build-time rule the Generator reports in the build log and the Manifest, naming the file, class and field. An error fails the build and leaves its class out of the Registry and the Manifest; a warning doesn't.
_Avoid_: Lint (for these)

**Type catalog**:
Pyro's complete list of types it can offer: the user's types from the Manifest plus Flame's built-in Node kinds.
_Avoid_: Type registry, Registry (in Pyro)

**Missing behavior** / **Missing component**:
A Behavior or Custom component referenced by a Scene whose Type ID no longer exists in the code; its data is kept untouched.
_Avoid_: Missing script

### Editing and running

**Document**:
Pyro's in-memory, undoable model of one open Scene.

**Transaction**:
A named change to a Document, such as *Move 3 Nodes*; the only way a Document changes, and one step of undo.

**Coalescing key**:
The identifier that merges the transactions of one continuous gesture (a drag, a slider scrub, typing in one field) into one undo step.

**Unsaved changes**:
A Document whose state differs from its Scene file on disk; shown with a marker and confirmed before closing.
_Avoid_: dirty (in user-facing text)

**Recovery copy**:
A copy of a Document with unsaved changes, kept outside the project so the work survives a crash; Pyro offers to restore it on the next launch.
_Avoid_: autosave, backup

**Play**:
Running the developer's game from Pyro on a chosen device; Pyro owns that running game.
_Avoid_: Run game, launch

**Play session**:
One run of the developer's game through Pyro's Play client, from starting `flutter run` to the game's exit; it reports the game's output and Hot-swaps its saved Scenes.
_Avoid_: run, launch

**Console**:
Pyro's one log of the generator's, the game's and Pyro's own lines for the open project, with debugger auth codes masked; it keeps the last 10,000 lines.
_Avoid_: log panel, output

**External build_runner**:
A `build_runner` that Pyro did not start, such as one the developer runs in a terminal or an IDE. Pyro sees it only by its lock, shows "External build_runner", never stops it, and starts its own run again once the lock is free.
_Avoid_: user generator, foreign build

**Contract test**:
The CI check that `example/`'s generated Registry and Manifest are committed and reviewed, and that every `example/` Scene loads with the real Registry, with no error and no warning.

**Attach**:
Connecting the developer's IDE debugger to a game Pyro is already running.

**Hot-swap**:
Replacing a Scene inside a running game with its newly saved version, without restarting the game. It happens only when the Scene's content changed.
_Avoid_: Scene reload, live reload

**Hot-swap report**:
The one line the Runtime prints in a debug build when a Scene loads (`[pyro] Scene loaded: <path>`), is Hot-swapped (`reloaded`), or fails to Hot-swap (`not reloaded`); Pyro reads it to know a Hot-swap reached the game.

**Stale reference**:
A component of a Node that a Hot-swap removed, still held by game code; debug builds warn the first time one is moved or added back.
_Avoid_: Dangling reference

**Live bridge**:
A future two-way connection between Pyro and a running game for selecting and tweaking Nodes live.
