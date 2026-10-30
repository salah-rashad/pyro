# Feature Specification: Generator

**Feature Branch**: `specs/003-generator`

**Created**: 2026-10-20

**Status**: Draft

**Input**: User description: "#7 Generator (Phase 2, project-plan §14): the annotations in
`pyro_annotations` (`@PyroBehavior`, `@PyroComponent`, `@Editable`), introspection of annotated
classes, the build-time rules of §6.1, Type IDs and collisions (ADR 0002), supertypes and parent
types (Q57), the Registry and Manifest emitters into `lib/` with `build.yaml` (Q68), errors
reported in the Manifest, for the preview's Field types. References: project-plan §6.1, §7.3,
§9.2; dev-docs/phases.md Phase 2; spike `spikes/02_generator/`. Done-when for this item: the
generator's goldens pass on annotated fixtures, including error cases (Type ID collision,
unsupported field, bad constructor)."

## Overview

The Generator is how Pyro learns about the developer's own code without ever running it (*Q7,
Q38*). The developer marks Behaviors and Custom components in their Flame game with Pyro's
annotations, and marks the fields they want to tweak in the editor as Editable. At build time the
Generator reads those classes and writes two files into the game's `lib/`, both committed:

- the **Registry**, code shipped in the game that lets the Runtime create each user type by its
  Type ID and set its Editable fields from a Scene;
- the **Manifest**, data describing the same types and fields, which Pyro reads to fill its Type
  catalog, the inspector and the Add lists, and to tell what a Scene's Type IDs mean.

It is the second piece of Phase 2 (project-plan §6.1, §7.3, §9.2; phases.md #7). It builds on the
shape proven in spike #2 (`spikes/02_generator/`, ARCHITECTURE.md): a per-library scan plus one
aggregator that writes both files. The Runtime that consumes the Registry (#8), the Pyro side that
parses the Manifest (#6) and the build_runner watcher Pyro runs (#11) are separate items.

**Who uses it**

- **Game developer**: annotates classes and fields, runs `build_runner` (or lets Pyro run it),
  and reads the Generator's errors when an annotation breaks a rule.
- **The Runtime** (#8, in the game): creates user types and sets their fields through the Registry.
- **Pyro** (#6, #9): reads the Manifest, including its errors, to know which types exist, what
  fields they have, and which Behaviors fit which Nodes.
- **CI** (the contract test, #12): regenerates both files and fails if the committed ones differ.

## Clarifications

### Session 2026-10-20

- Q: Which Field types does this item support: only the preview's (`int`, `double`, `bool`,
  `String`, enum, `Vector2`, image path), or every v1 Field type? → A: Every v1 Field type, in
  both the Manifest and the Registry: `Color`, entity references, `Sprite` and `SpriteAnimation`
  as well. The preview's inspector still shows the extra types read-only (#5), but games can use
  them from the start, matching #8's full scope (asset loading, two-pass references). Phase 7's
  "#7 Generator: the rest of the v1 Field types" (~2 evenings) moves into this item.
- Q: How does a developer declare an image-path field? → A: With a small path type from
  `pyro_annotations` (`ImagePath`), which keeps that package free of dependencies, makes asset
  fields easy to spot in code, and lets the Generator tell an image path from ordinary text.
- Q: Must entity-reference, `Sprite` and `SpriteAnimation` fields be nullable? → A: Yes; a
  non-nullable one fails the build with an error naming the field. "No Override" means `null`.
  `ImagePath` fields may be either, since a path can have a `const` default.
- Q: Can `@Editable` go on a setter or a getter/setter pair, or only on plain fields? → A: Plain
  fields only in v0.1; `@Editable` on a getter or setter fails the build with an error naming it.
  Developers react to values in `onLoad`, after the Runtime has set every Override.
- Q: What happens to `@Editable` on a class that has no Pyro annotation and isn't a superclass of
  an annotated class? → A: A build warning, in the build log and in a separate `warnings` list in
  the Manifest; the build still succeeds and no type is left out.
- Q: When does `manifestVersion` go up, and what does Pyro do with a newer one? → A: It goes up
  only for changes an older reader would misread (a new Field type or role, a changed meaning or
  shape); readers ignore unknown keys, so new optional keys don't change it. Pyro refuses a newer
  version with *Update Pyro* and keeps the last Manifest it could read.
- Q: What happens when `min` is above `max`, or a constant default lies outside `[min, max]`?
  → A: `min` above `max` is a build error; a default outside the range is a warning (it is often
  deliberate, like `-1` for "off"), and the inspector still shows the real default.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Annotate a Behavior and see it described (Priority: P1)

A developer writes a `Patrol` Behavior for their enemies, annotates it with a label and a
category, and marks `speed` (a `double` between 0 and 400 with a tooltip), `direction` (a
`Vector2`) and `mode` (an enum) as Editable. They run the build. The Manifest now lists `Patrol`
with its Type ID, role, label, category, source file, doc comment, the parent type it needs and
its three fields in declaration order, each with its Field type, default and limits. The Registry
can create a `Patrol` and set each of the three fields.

**Why this priority**: this is the whole point of the item; without it Pyro has nothing to offer
in the inspector and the Runtime can't build a single user type.

**Independent Test**: run the Generator on an annotated fixture package and compare the Registry
and the Manifest with their golden files.

**Acceptance Scenarios**:

1. **Given** a public, non-abstract class annotated `@PyroBehavior` with an unnamed constructor
   callable with no arguments, **When** the build runs, **Then** the Manifest lists it with role
   "behavior", its Type ID (the class name), label, category, source path and doc comment, and
   the Registry can create it by that Type ID.
2. **Given** a class annotated `@PyroComponent` that extends `PositionComponent`, **When** the
   build runs, **Then** the Manifest lists it with role "component", whether it accepts Behaviors
   (it mixes in `EntityMixin`), its preview image if one is given, and the Registry can create it.
3. **Given** an annotation with an explicit `id:`, **When** the build runs, **Then** that is the
   Type ID in both files, and renaming the class or moving its file doesn't change either file's
   Type ID entries (*ADR 0002*).
4. **Given** Editable fields of each v1 Field type (`int`, `double`, `bool`, `String`, an enum,
   `Vector2`, `Color`, `ImagePath`, `Sprite`, `SpriteAnimation`, and a `Component` subtype as an
   entity reference), **When** the build runs, **Then** each appears in the Manifest with its
   Field type, its annotation options (minimum, maximum, tooltip, label), for enums the value
   names in declaration order and for entity references the referenced type, and the Registry
   can set each one.
5. **Given** an Editable field whose initializer is a constant (a literal, an enum value, a
   negative number, `const ImagePath('assets/images/fx.png')`), **When** the build runs, **Then**
   the Manifest records the evaluated value as the default; **Given** a non-constant initializer (`Vector2(1, 0)`), **Then** the default
   is empty and the initializer's source text is recorded for display (*§7.3*).
6. **Given** a Behavior declared as `Behavior<Enemy>`, **When** the build runs, **Then** the
   Manifest records `Enemy` (by Type ID if `Enemy` is annotated, by class name otherwise) as its
   required parent type, so Pyro offers it only on compatible Nodes.
7. **Given** a Custom component `Boss extends Enemy extends PositionedEntity`, **When** the build
   runs, **Then** the Manifest records its supertypes as its class chain, nearest first, so
   reference fields and parent-type checks accept subtypes (*Q57*).
8. **Given** a class that inherits Editable fields from a superclass, **When** the build runs,
   **Then** the inherited fields are listed too, superclass fields first, and the Registry can set
   them.
9. **Given** a package with no annotated classes, **When** the build runs, **Then** an empty
   Registry and an empty Manifest are written, so a game that calls the Runtime still compiles.

---

### User Story 2 - Get a clear error for every broken rule (Priority: P1)

A developer annotates a class that has a required constructor argument, another whose Editable
field is a `Map`, and copies a Behavior to a second file under the same class name. The build
fails. Each error says what is wrong, names the class (and field) and its file, and says how to
fix it. The same errors are written into the Manifest, so Pyro can show them inline even though
the build failed. The two classes sharing a Type ID are both left out of the Registry and the
Manifest, so the game can never silently build the wrong one. When the developer fixes the
problems and saves, the next build succeeds and the errors are gone.

**Why this priority**: the Generator's rules are the safety net of the data contract
(constitution IV, V). An error that is unclear or that leaves stale output behind costs testers
the setup they are least patient with.

**Independent Test**: run the Generator on one fixture per rule and compare its Manifest (with
the errors) and its Registry with golden files; check that the build reports failure.

**Acceptance Scenarios**:

1. **Given** two annotated classes with the same Type ID (same class name in two files, or the
   same explicit `id:`), **When** the build runs, **Then** it fails with one error naming the
   Type ID and both classes with their files, suggesting an explicit `id:`, and neither class
   appears in the Registry or the Manifest's types (*Q45*).
2. **Given** an annotated class that is private, abstract, generic, or whose unnamed constructor
   is missing or needs an argument, **When** the build runs, **Then** it fails with an error
   naming the class, its file and the rule, and the class is left out of both files.
3. **Given** an `@Editable` field whose type isn't a supported Field type (`Map`, `List`, a class
   that isn't a Component), **When** the build runs, **Then** it fails with an error naming the
   class, the field, its type and its file, and the class is left out of both files.
4. **Given** an `@Editable` field that is private, final, const, static, or non-nullable
   with no initializer, or `@Editable` on a getter or setter, **When** the build runs, **Then** it fails with an error naming the field
   and the rule.
5. **Given** a non-nullable `@Editable` entity-reference, `Sprite` or `SpriteAnimation` field
   (`Player target = Player();`), **When** the build runs, **Then** it fails with an error naming
   the field and saying it must be nullable.
6. **Given** a `@PyroComponent` class that doesn't extend `PositionComponent`, or a
   `@PyroBehavior` class that doesn't extend `Behavior`, or a class with both annotations,
   **When** the build runs, **Then** it fails with an error naming the class and the rule.
7. **Given** an explicit `id:` that is empty or contains whitespace, **When** the build runs,
   **Then** it fails with an error naming the class and the ID.
8. **Given** a build with errors, **When** it finishes, **Then** both files are still written:
   valid types appear as usual, every error appears in the Manifest's `errors`, and build_runner
   reports the build as failed.
9. **Given** a build that failed, **When** the developer fixes the cause and the build runs
   again, **Then** the errors are gone from the Manifest and the fixed types reappear in both
   files; **When** nothing is fixed and the build runs again, **Then** the same errors are
   reported again rather than disappearing.
10. **Given** an `@Editable` field in a class or mixin that has no Pyro annotation and is no
    annotated class's superclass or mixin, **When** the build runs, **Then** it succeeds, and a warning naming the
    class, the field and its file appears in the build log and the Manifest's `warnings`,
    suggesting `@PyroBehavior` or `@PyroComponent`.

---

### User Story 3 - Committed output that never drifts (Priority: P1)

A developer clones a game that uses Pyro and opens it straight away in Pyro, with no build step,
because the Registry and the Manifest are committed. On another machine a teammate runs the build
on the same source: neither file changes. In CI, regenerating the files and comparing them with
the committed ones catches a forgotten build. Editing a method body or an unannotated file leaves
both files untouched; changing a tooltip changes only the Manifest.

**Why this priority**: both files are committed and checked in CI (*Q68, Q76*); a single
non-deterministic byte would make every build look like a change and break the contract test.

**Independent Test**: build the fixture package twice from a clean cache, and on two operating
systems, and compare bytes; make each kind of edit and check which file changes.

**Acceptance Scenarios**:

1. **Given** identical source, **When** the build runs from a clean cache, on any supported
   operating system, **Then** both files are byte-identical to the previous build.
2. **Given** both files, **When** they are read, **Then** they hold no timestamps, absolute paths,
   machine names or other content that depends on when or where the build ran.
3. **Given** annotated classes in several files, **When** the build runs, **Then** types are
   listed in Type ID order and fields in declaration order, independent of file names or the
   order build_runner visits files.
4. **Given** an edit that doesn't change any annotated class's description (a method body, an
   unannotated file), **When** the build runs, **Then** neither file is rewritten.
5. **Given** an edit to a tooltip, label, category or doc comment only, **When** the build runs,
   **Then** only the Manifest changes.
6. **Given** a game that depends on `pyro_generator` and `build_runner`, **When** the developer
   runs `dart run build_runner build` with no further configuration, **Then** both files are
   written to `lib/pyro.g.dart` and `lib/pyro.manifest.json`.

---

### User Story 4 - Fast feedback while Pyro watches (Priority: P2)

With Pyro's watcher running (#11), a developer adds an Editable field to a Behavior in their IDE
and saves. About a second later the Manifest has changed, and Pyro's inspector shows the new
field.

**Why this priority**: the code-to-editor loop is part of the product loop (constitution III,
*Q82*), but the watcher itself is #11; this item only has to keep the Generator fast enough.

**Independent Test**: on a synthetic mid-size project, measure the time from a save to the
Manifest update in `build_runner watch`, as spike #2 did.

**Acceptance Scenarios**:

1. **Given** a running `build_runner watch` on a mid-size Flame project, **When** an annotated
   file is saved, **Then** the Manifest is updated within the budget of SC-004.
2. **Given** a file with no Pyro annotations, **When** it is saved, **Then** the Generator's
   per-file scan is skipped for it.

---

### Edge Cases

- **Annotations used under another name** (re-exported, or imported with a prefix): classes are
  still recognised, by the annotation's type, not its spelling; the cheap skip of unannotated
  files may then not apply, which only costs time.
- **An annotated class outside `lib/`** (in `test/`, `bin/` or `example/` of the package): ignored;
  only classes the game can import from `lib/` are described.
- **An annotated class in a `part` file**: described as part of its library; its source path is
  the part file.
- **A class that extends another annotated class**: both are described, each with its own Type
  ID; the subclass lists the superclass's Type ID among its supertypes.
- **An enum Editable field whose enum has no values**: an unsupported field error.
- **A nullable Editable field** (`Player? target`, `String? note`): allowed; recorded as nullable
  with an empty default when it has no initializer.
- **An entity reference to a built-in Flame type** (`SpriteComponent? icon`): allowed; the
  referenced type is recorded by class name, and Pyro matches it against the built-in Node kinds'
  hand-written supertypes (*Q57*).
- **An entity reference to `Component` itself**: allowed; any Node can be referenced.
- **A `String` field holding a path**: plain text; only `ImagePath` (or `Sprite`,
  `SpriteAnimation`) makes a field an asset reference.
- **A field name that shadows an inherited Editable field**: listed once, with the subclass's
  declaration.
- **Two errors in one class**: both are reported; the class is left out once.
- **A Type ID that matches a built-in Node kind's name** (a user class called `Sprite`): allowed;
  Custom components are written with `"kind": "custom"`, so the names never meet in a Scene.
- **A field type from a package the game doesn't depend on directly** (spike #2: `Vector2` from
  `vector_math`): the Registry names it through a library the developer's own file can import,
  so the Registry passes the game's analysis without implementation-import warnings.
- **The game imports a user type under a library prefix**: the Registry uses its own prefixes so
  names from different libraries never clash.

## Requirements *(mandatory)*

### Functional Requirements

**Annotations (`pyro_annotations`)**

- **FR-001**: `pyro_annotations` MUST provide `@PyroBehavior`, `@PyroComponent` and `@Editable`,
  and the `ImagePath` type (FR-012), with no package dependencies (*Q44*).
- **FR-002**: `@PyroBehavior` MUST accept an optional label, category and explicit Type ID.
  `@PyroComponent` MUST accept the same plus an optional preview image path (*§6.1*).
- **FR-003**: `@Editable` MUST accept optional minimum, maximum, tooltip and label. Minimum and
  maximum apply to numeric fields only; giving them on another Field type is an error naming the
  field. A minimum above the maximum is an error naming the field and both values; a constant
  default outside `[min, max]` is a warning naming the field, the default and the range.
- **FR-004**: The annotations MUST be usable in `const` context and MUST NOT carry behavior; they
  only describe.

**Recognition and build-time rules**

- **FR-005**: The Generator MUST recognise annotated classes by the annotation's type, in every
  library under the package's `lib/`, and only there.
- **FR-006**: An annotated class MUST be public, non-abstract, non-generic, and have an unnamed
  constructor callable with no arguments (optional parameters allowed); otherwise the build fails
  with an error naming the class, its file and the broken rule.
- **FR-007**: A `@PyroComponent` class MUST extend `PositionComponent`; a `@PyroBehavior` class
  MUST extend `Behavior`; a class MUST NOT carry both annotations. Breaking any of these fails the
  build with an error naming the class and the rule (*Q50*).
- **FR-008**: The Type ID MUST be the explicit `id:` if given, otherwise the class name. An
  explicit ID MUST be non-empty and contain no whitespace (*ADR 0002*).
- **FR-009**: Type IDs MUST be unique across the package. When two or more classes share one, the
  build MUST fail with a single error naming the Type ID and every class sharing it with its file,
  suggesting an explicit `id:`, and MUST leave all of them out of both outputs (*Q45*; spike #2
  finding 4).
- **FR-010**: An `@Editable` field MUST be a public, non-final, non-const, non-static instance
  field of a supported Field type, and MUST have an initializer unless it is nullable; otherwise
  the build fails with an error naming the class, the field, its declared type and the rule.
  `@Editable` on a getter or setter (including a getter/setter pair) fails the build with an
  error naming the class and the accessor.
- **FR-011**: The supported Field types MUST be every v1 Field type (*§6.1, Q12*): `int`,
  `double`, `bool`, `String`, enums, `Vector2`, `Color`, asset references (`ImagePath`, `Sprite`,
  `SpriteAnimation`) and entity references (a `Component` or any subtype of it that isn't a
  `Behavior`, since Behaviors are never Nodes), each in both the Manifest and the Registry. Any other type, including `Map` and `List`, fails the build with an
  error pointing at the field.
- **FR-012**: An image-path field MUST be declared with the `ImagePath` type from
  `pyro_annotations`, a const-constructible wrapper around a project-root-relative asset path as
  in the Scene format (*Q27, Q91*). A plain `String` field is always text, never an asset
  reference.
- **FR-011a**: Entity-reference, `Sprite` and `SpriteAnimation` fields MUST be nullable; a
  non-nullable one fails the build with an error naming the class and the field. Their code
  default is `null`, which a Scene's Override replaces. `ImagePath` fields may be nullable or not.
- **FR-012a**: For an entity reference, the Manifest MUST record the referenced type: by Type ID
  when it is annotated, by class name otherwise (*Q57*).
- **FR-013**: A class MUST include the Editable fields it inherits from its superclasses and the
  mixins applied to them, whether or not those are annotated, listed from the top of the chain
  down, each in declaration order.
- **FR-013a**: A Behavior's parent type (`T` in `Behavior<T>`) MUST be a class, so Pyro can match
  it against Nodes' supertypes; a mixin or interface-only type fails the build with an error
  naming the Behavior. `Behavior<EntityMixin>` or a bare `Behavior` means any Node that accepts
  Behaviors.
- **FR-014**: All errors in a build MUST be reported, not only the first; a class with any error
  MUST be left out of both outputs; the remaining valid classes MUST still be written.
- **FR-014a**: An `@Editable` field in a class or mixin that has no Pyro annotation and is no
  annotated class's superclass or mixin MUST produce a warning naming the class, the field and its file. Warnings
  MUST NOT fail the build or leave any type out of either output.

**Manifest**

- **FR-015**: The Generator MUST write `lib/pyro.manifest.json` with `manifestVersion`, the list
  of types, the list of errors and the list of warnings (*§7.3*).
- **FR-015a**: `manifestVersion` starts at 1 and MUST go up only with a change an older reader
  would misread: a new Field type or role, or a changed meaning or shape of an existing key. New
  optional keys MUST NOT change it, and readers MUST ignore keys they don't know. Pyro (#6)
  refuses a Manifest with a newer version, asking the developer to update Pyro, and keeps the
  last Manifest it could read.
- **FR-016**: Each type MUST record its Type ID, role, label (the class name when none is given),
  category, source path relative to the package root, doc comment, supertypes and fields. A
  Behavior MUST also record its required parent type; a Custom component MUST also record whether
  it accepts Behaviors and its preview image path, if given.
- **FR-017**: Supertypes MUST be the class chain, nearest first, ending at `Component` for Custom
  components and at `Behavior` for Behaviors; an annotated supertype is named by its Type ID,
  any other by its class name (*Q57*). Interfaces and mixins other than `EntityMixin` (recorded as
  "accepts Behaviors") MUST NOT be listed (spike #2 finding 6).
- **FR-018**: Each field MUST record its name, Field type, nullability, label, tooltip, minimum
  and maximum when given, and its default: the evaluated value when the initializer is constant,
  otherwise an empty default and the initializer's source text. Enum fields MUST also record their
  value names in declaration order.
- **FR-019**: Each error and each warning MUST record a message, the file, the line, and the Type ID, class and
  field it concerns where they apply, so Pyro can show it next to the right type.
- **FR-020**: Errors MUST be written into the Manifest even when the build fails, and both
  outputs MUST be written before the build reports failure (spike #2 finding 4).

**Registry**

- **FR-021**: The Generator MUST write `lib/pyro.g.dart`, which the game compiles and passes to
  the Runtime (*§6.2*).
- **FR-022**: For each valid type, the Registry MUST be able to create a new instance by Type ID
  and set each of its Editable fields by name from a value the Runtime has already converted from
  the Scene's written form (*Q91*); conversion of written forms stays in the Runtime (spike #2
  finding 6).
- **FR-023**: The Registry MUST describe each type's role and each field's Field type (and enum
  values), so the Runtime can convert and check Scene values without the Manifest, which isn't
  shipped in the game.
- **FR-024**: The Registry MUST implement a Registry contract defined in `pyro_runtime`, which
  this item adds and #8 consumes; `pyro_generator` itself MUST NOT depend on `pyro_runtime` or
  Flutter (*§5*, constitution II).
- **FR-025**: The Registry MUST compile without analyzer errors or warnings in the game, MUST
  import types through public libraries (no `src/` implementation imports of other packages), and
  MUST stay correct when user types or field types share names across libraries. A field type
  that no import of the declaring library makes available fails the build with an error naming
  the field, rather than producing an implementation import.
- **FR-025a**: A package that uses the Generator but doesn't depend on `pyro_runtime` MUST get a
  build error saying so, since its Registry couldn't compile.

**Build integration and determinism**

- **FR-026**: The Generator MUST run as a per-library scan that writes intermediate results to
  the build cache plus one aggregator that writes both outputs to the package's `lib/`
  (`build_to: source`; *Q68*, spike #2).
- **FR-027**: The Generator's builders MUST apply automatically to packages that depend on
  `pyro_generator`, so a game needs no `build.yaml` of its own to get both outputs.
- **FR-028**: The per-library scan MUST be skipped for libraries that mention none of Pyro's
  annotations (build_runner triggers).
- **FR-029**: Both outputs MUST be deterministic: byte-identical for identical input on every
  supported operating system, with types in Type ID order, fields in declaration order, sorted
  JSON keys, `/` path separators, and no timestamps, absolute paths or machine-dependent content.
- **FR-030**: An output whose content didn't change MUST NOT be rewritten, so Pyro can react to
  every Manifest file event (spike #2 finding 4).
- **FR-031**: The Generator MUST accept the wide dependency ranges that let it resolve in Flutter
  3.44 projects (build_runner 2.15) as well as the newest releases (spike #2 finding 1).

### Key Entities

- **Annotated type**: a Behavior or Custom component class the developer marked; has a Type ID,
  a role, display data (label, category, doc, preview), supertypes, Editable fields and, for a
  Behavior, a required parent type.
- **Type ID**: the stable name a Scene uses for an annotated type: the class name or the explicit
  `id:`; unique per package.
- **Editable field**: a field of an annotated type (own or inherited) the inspector can edit and
  a Scene can override; has a name, Field type, nullability, options and default.
- **Field type**: the value type of an Editable field; decides how the Runtime converts the
  Scene's written form and which editor Pyro shows.
- **Generator error**: a broken build-time rule; names the file, line, type and field it concerns
  and how to fix it; written to the build log and the Manifest. A **Generator warning** has the
  same shape but doesn't fail the build (FR-014a).
- **Manifest**: the committed JSON description of all valid types plus all errors and warnings, read by Pyro.
- **Registry**: the committed generated code that creates types by Type ID and sets their fields,
  implementing the Runtime's Registry contract.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every golden fixture passes: one fixture package covering every supported Field
  type, both roles, explicit IDs, parent types, supertypes and inherited fields, and one fixture
  per build-time rule (at least Type ID collision, unsupported field and bad constructor), each
  compared byte for byte with its Registry and Manifest goldens.
- **SC-002**: 100% of the build-time rules in FR-003, FR-006 to FR-014a, FR-025 and FR-025a
  have an error or warning fixture, and every message names the file and the class (and field,
  where there is one).
- **SC-003**: Building the fixture packages twice from a clean cache, on macOS, Linux and
  Windows in CI, produces byte-identical outputs every time.
- **SC-004**: In `build_runner watch` on a mid-size Flame project (300 files, 42 annotated), the
  median time from saving an annotated file to the Manifest update is under 3 s on the reference
  Mac, matching spike #2's ~0.9 s within the budget (constitution III).
- **SC-005**: The generated Registry for the full fixture compiles and passes analysis with zero
  issues, and a test that creates every type by Type ID and sets every field succeeds.
- **SC-006**: For every type in the full fixture, the Manifest and the Registry list exactly the
  same Type IDs and field names.

## Assumptions

- **Scope** is the early preview's part of #7 (*§14*) plus every remaining v1 Field type, which
  §14 and phases.md had deferred to Phase 7 (Clarifications, 2026-10-20). §14, phases.md and
  `decisions.md` are updated to match when this feature is implemented, as specs 001 and 002 did;
  the inspector's editors for those types stay in Phase 7 (#5). The Pyro side that parses the Manifest
  (#6), the Runtime loader that uses the Registry (#8), Pyro's watcher and lock probe (#11) and
  the CI contract job on `example/` (#12) are separate items. Prefab instances, animations and
  `@RenamedFrom` (dropped by *Q45*) are out of scope.
- **The Registry contract** (the interface the generated Registry implements) is added to
  `pyro_runtime` by this item, kept as small as FR-022 and FR-023 need; #8 builds the loader on
  it and may extend it.
- **Only the package's own `lib/` is scanned.** Annotated types in the game's dependencies (a
  shared library of Behaviors) are not described in v0.1.
- **Behaviors** are `flame_behaviors` Behaviors and their parent type is the type argument of
  `Behavior<T>`; a Behavior with no type argument requires any entity.
- **Defaults** that aren't constant are shown, not evaluated; the inspector shows them as
  "default from code" (*§6.1*). Evaluating `const` constructor calls (`const Color(...)`) may come
  later if the inspector needs real values (spike #2 finding 6).
- **Annotation names** are as proposed in §6.1 (◇ proposed); the Generator matches them by type,
  so a rename before pub.dev changes only `pyro_annotations` and the triggers.
- **The `build.yaml` in §14's description** is the Generator package's own builder registration
  (FR-027). The README recipe (Phase 5) and the "Add Pyro" flow (Phase 7) therefore don't need to
  add a `build.yaml` to the game unless a later option requires it.
- **The Manifest's exact key spelling and Field type names** follow §7.3's example and are pinned
  in the plan's contract.
- **Dependencies**: no new package dependencies beyond those `pyro_generator` already declares
  (`analyzer`, `build`, `source_gen`, `dart_style`, `pyro_annotations`); test-only dependencies are
  settled in the plan.
