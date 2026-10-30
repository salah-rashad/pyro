# pyro_generator

The `build_runner` generator for Pyro. It reads the Behaviors and Custom
components you annotate in your game's `lib/` and writes two files there, which
you commit:

- `lib/pyro.g.dart`: the **Registry**, which your game passes to the Runtime so it
  can create your types from Scenes and set their Editable fields.
- `lib/pyro.manifest.json`: the **Manifest**, which Pyro reads to offer your types
  and their fields, and to show the generator's errors and warnings.

## Setup

```yaml
dependencies:
  pyro_runtime: ^0.0.1 # re-exports pyro_annotations

dev_dependencies:
  build_runner: ">=2.14.0 <3.0.0"
  pyro_generator: ^0.0.1
```

No `build.yaml` is needed: both builders apply to any package that depends on
`pyro_generator`. Then run `dart run build_runner build` (or let Pyro run
`build_runner watch`).

## Rules

The build fails, naming the file, class and field, when an annotated class is
private, abstract, generic or has no unnamed constructor callable with no
arguments; when two classes share a Type ID; or when an `@Editable` field is
private, final, static, a getter or setter, of an unsupported type, or
non-nullable without a default. Entity references, `Sprite` and
`SpriteAnimation` fields must be nullable. The errors are also written into the
Manifest's `errors`, and the classes concerned are left out of both files. See
[`dev-docs/project-plan.md`](../../dev-docs/project-plan.md) §6.1 and
[`specs/003-generator/`](../../specs/003-generator/spec.md).

## Checking the committed files in CI

On Flutter ≥ 3.47, `dart run build_runner build --only-check`. Below that,
`dart run build_runner build` followed by
`git diff --exit-code lib/pyro.g.dart lib/pyro.manifest.json` (*Q76*).

> **Status:** not on pub.dev yet; the packages are used from this repository
> until v0.1, with `dependency_overrides` for all three.
