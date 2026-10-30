# Pyro Constitution

## Core Principles

### I. Clean Code

Code in the workspace reads as if one careful person wrote it, because one person maintains it
(project-plan §2, goal 4).

- Every workspace member MUST pass `dart analyze` / `flutter analyze --fatal-infos` and
  `dart format --set-exit-if-changed` with the shared `analysis_options.yaml` (strict casts,
  inference and raw types). Lints are fixed, not suppressed; an `// ignore:` MUST carry a
  one-line reason.
- Public APIs MUST be documented (`public_member_api_docs`). Comments explain *why*, not *what*.
- Names MUST follow [`GLOSSARY.md`](../../GLOSSARY.md) (Node, Behavior, Override, Type ID,
  Registry, Manifest, Type catalog, Hot-swap…). A new domain term is added to the glossary in the
  same change that introduces it.
- Data models MUST be immutable (freezed or `final` fields with `copyWith`); mutation happens only
  through the owning API (for scenes: a named transaction, project-plan §8.2).
- No dead code, commented-out code or speculative abstractions in `packages/` or `apps/`. An
  abstraction needs at least two real callers or a documented seam (a test double, a package
  boundary). Throwaway code lives in `spikes/`, which is exempt from this constitution.
- Errors MUST name what failed and where (scene, Node, Type ID, file path). No bare
  `catch (_) {}`; a swallowed error MUST be logged with its reason.

**Rationale:** a solo, evenings-only project survives only if any file can be picked up cold
after weeks away.

### II. Modular Boundaries

Each package has one job, and the dependency graph is a rule, not a convention.

- The dependency rules of project-plan §5 are binding:
  - `pyro_annotations` is pure Dart with **no dependencies**.
  - `pyro_generator` depends on the annotations, `source_gen`, `build` and `analyzer`; it MUST
    NOT depend on the runtime or Flutter.
  - `pyro_runtime` stays small (it ships in every game); the scene model, its JSON format and
    migrations live here and nowhere else.
  - `pyro_ui` depends on Flutter (plus its icon font) only. Its widgets take plain values and
    callbacks and MUST NOT know about scenes, the document, Riverpod or Flame.
  - The app (`apps/editor`) MUST NOT depend on the generator and MUST NOT import or execute user
    code (*Q7*).
- All editor UI MUST be built from `Pr` components in `pyro_ui` (*Q87*). A missing component is
  proposed and the author decides whether it is built; panels never style raw Material widgets
  around the design system.
- Inside the app, code is grouped by feature (`app/`, `document/`, `viewport/`, `panels/`,
  `project/`, `process/`). A feature reaches another only through its public provider or API,
  never through another feature's `src/` internals.
- Packages expose a deliberate public surface through their library file; everything else
  stays under `lib/src/`.
- A change that adds a package dependency or crosses a boundary MUST say so in its plan and,
  if it changes the architecture, be recorded as a decision (`dev-docs/decisions.md`) or an ADR.

**Rationale:** isolation keeps user bugs and editor bugs apart, keeps the shipped runtime small,
and lets each part be tested and replaced on its own.

### III. Performance by Design

Pyro is an AOT release build so it can be smooth (project-plan §4.3); the design MUST keep it
that way, and claims about speed MUST be measured.

- **Editor frame budget:** interactive editing (dragging gizmos, scrubbing a number field,
  selecting in the hierarchy, typing in the inspector) MUST hold 60 fps (≤ 16 ms per frame) in
  profile mode on the reference Mac with a 1,000-Node scene.
- **Rebuild scope:** a document change MUST rebuild only the widgets and preview components
  whose data changed: the reconciler skips `identical` Nodes (§8.3), the document uses
  structural sharing, and panels watch the narrowest provider (`nodeProvider(id)`, `select`),
  never the whole document.
- **No blocking the UI isolate:** file I/O MUST be async; parsing or hashing a large file,
  Manifest processing and process-output parsing MUST NOT block a frame (use isolates or
  chunking when they would).
- **Feedback latency** (the product loop, *Q82*): a saved scene MUST appear on the running
  device in about a second (spike #1 measured 58–250 ms of reload), a file change on disk MUST
  reach the viewport in ≤ ~200 ms (spike #3), and the generator's watch output SHOULD land in
  ≤ ~3 s on a mid-size project (spike #2).
- **Runtime cost in games:** `pyro_runtime` adds no per-frame work after a scene loads; debug-only
  code (Hot-swap) MUST sit behind `kDebugMode` so release builds tree-shake it.
- Resources are owned and released: subscriptions cancelled, sinks closed, images disposed only
  after nothing draws them (*Q79*), child processes stopped with the project.
- A feature that touches a hot path (viewport, reconciler, document, inspector, process output,
  runtime loader) MUST state its budget in its plan and how it is measured (profile-mode
  DevTools timeline or a benchmark). A regression past a budget blocks the change unless it is
  justified in Complexity Tracking.

**Rationale:** the editor is only worth using if editing feels instant and the save-to-device
loop stays short; performance lost through architecture is expensive to win back.

### IV. User Data Integrity (NON-NEGOTIABLE)

Pyro never silently deletes or rewrites user data it doesn't understand (project-plan §11).

- Scene and project files MUST be written atomically (temp file + rename).
- Unknown types, missing behaviors and orphaned field values MUST be preserved verbatim and shown
  to the user, never dropped (*Q32*).
- Files from a newer `schemaVersion` MUST be refused with the required version; Pyro MUST NOT
  write a `schemaVersion` the project's Runtime can't read (*Q49*).
- The real scene file changes only when the user saves; crash safety comes from the recovery file
  (*Q55*).
- Scene JSON is deterministic (sorted keys, Overrides only, *ADR 0003*) so diffs stay reviewable
  and round-trips are byte-for-byte.
- Changes to the user's project (pubspec, `build.yaml`, assets) MUST be shown as a diff before
  they are applied.

**Rationale:** a scene editor that loses work loses its users; this is goal 3 of the project.

### V. Tested Core

The core is tested heavily so one person can change it with confidence.

- The test layers in project-plan §13 are required at their stated weight. Document and
  history, serialization and migrations, the reconciler, the generator, the runtime loader and
  the contract test are **Heavy**: every behavior change in them ships with tests in the same
  change.
- A bug fix MUST start with a failing test that reproduces it, where the layer is testable.
- Formats are pinned by goldens: generator output (Registry and Manifest), the Manifest of
  `example/`, and one golden per `pyro_ui` gallery page.
- The contract test (*Q59*) MUST stay green: the generator runs on `example/` and every
  `example/` scene loads with `flame_test` against the real Registry.
- Process clients are tested against recorded daemon transcripts, never a real Flutter SDK.
- Tests MUST be deterministic: no real network, no wall-clock sleeps; time and file system are
  injected or faked.

**Rationale:** heavy tests on the data contract are what make the rest of the editor safe to
iterate on quickly.

## Technology and Platform Constraints

- **Workspace:** one repository, Dart pub workspace (`sdk: ^3.12.0`), members as listed in the
  root `pubspec.yaml`. `spikes/` is outside the workspace.
- **Toolchain:** Flutter stable only; the Runtime supports the latest stable Flame minor with a
  floor of Flame 1.36; `build_runner ≥ 2.14` (*Q18, Q48, Q66*).
- **App stack:** Riverpod for state and freezed for models (*Q26*); menus on `RawMenuAnchor` and
  tooltips on `RawTooltip`, no menu package (*Q84*); no `dart:mirrors` or `reflectable`, user
  types come from the generator (*Q12, Q38*).
- **Platforms:** macOS first-class for v0.1; Windows and Linux are built in CI on a best-effort
  basis. The macOS app is unsandboxed, hardened, signed and notarized (§12).
- **Process model:** Pyro runs the game with the user's own SDK as a child process; the IDE
  attaches (*ADR 0001*). Pyro uses the user's installed SDK and never bundles one (*Q39*).
- **Licensing:** MIT. New dependencies MUST be compatible with MIT distribution, and bundled
  non-package assets (fonts) MUST register their licences (§12).

## Development Workflow and Quality Gates

- **Sources of truth:** `dev-docs/project-plan.md` owns scope and design; `dev-docs/decisions.md` records
  decisions as numbered questions (`Qnn`); `dev-docs/adr/` holds architecture decisions;
  `dev-docs/ARCHITECTURE.md` records what was verified; `dev-docs/phases.md` tracks progress and MUST be
  updated in the same commit when project-plan §14 changes.
- **Spec Kit flow:** each feature's `plan.md` MUST pass the Constitution Check before research
  and again after design. A violation is either fixed or justified in Complexity Tracking with
  the simpler alternative that was rejected and why.
- **Spec branches:** each feature's work MUST happen on a branch named `specs/<spec-id>`, where
  `<spec-id>` is its directory under `specs/` (`specs/001-scene-format` for
  `specs/001-scene-format/`). Spec Kit doesn't create branches in this repository, so the branch
  is created by hand when a spec's work starts, and all of that spec's commits go on it.
- **CI gates (every push and PR):** format check, analyze with `--fatal-infos`, and all tests on
  macOS, Windows and Linux; the contract job; release builds of the app. A red gate blocks
  merging.
- **Commits:** Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`,
  `perf:`), citing the decision (`Qnn`) or ADR they implement where one applies.
- **Review:** every change is self-reviewed against this constitution before merge; changes to
  the data contract (scene format, Manifest, Registry, annotations) also get a contract-test run
  and a note in `ARCHITECTURE.md` if behavior was verified or changed.

## Governance

This constitution supersedes other practices in this repository where they conflict. The project
plan and decisions log describe *what* Pyro is; this file governs *how* it is built.

- **Amendments:** made by editing this file in a dedicated commit (`docs: amend constitution to
  vX.Y.Z …`), with a Sync Impact Report for review that is removed before committing. If an
  amendment changes a rule another document repeats (project plan, glossary, templates), those
  are updated in the same change.
- **Versioning:** semantic. MAJOR for removing or redefining a principle or a backward-incompatible
  governance change; MINOR for a new principle or section or materially expanded guidance; PATCH
  for wording and clarifications.
- **Compliance:** every feature plan runs the Constitution Check; every change is reviewed against
  the principles before merge; complexity and budget overruns MUST be justified in writing.
  Principle IV is non-negotiable and cannot be waived by a plan.
- **Runtime guidance:** day-to-day design detail lives in `dev-docs/project-plan.md`,
  `dev-docs/ARCHITECTURE.md`, `dev-docs/ui-components-plan.md` and `GLOSSARY.md`.

**Version**: 1.1.0 | **Ratified**: 2026-10-18 | **Last Amended**: 2026-10-18
