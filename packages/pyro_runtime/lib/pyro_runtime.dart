/// Loads Pyro scenes into a Flame game.
///
/// `PyroScene.load` turns a Scene file into a Flame component, building
/// Custom components and Behaviors through the generated Registry
/// (`pyroRegistry` in `lib/pyro.g.dart`), and Hot-swaps it in debug builds
/// (project plan §6.2). Re-exports `pyro_annotations`, and `Behavior` and
/// `EntityMixin` from `flame_behaviors`, so games depend on this package
/// for them. The Scene format (`SceneCodec`, `Scene` and the Node kinds) is
/// shared with Pyro, so the editor and games always agree on it.
library;

export 'package:flame_behaviors/flame_behaviors.dart'
    show Behavior, EntityMixin;
export 'package:pyro_annotations/pyro_annotations.dart';

export 'src/assets/asset_source.dart' show AssetSource;
export 'src/loader/load_exception.dart';
export 'src/loader/pyro_entity.dart';
export 'src/loader/pyro_scene.dart' show PyroScene, SceneReloaded;
export 'src/loader/registry.dart';
export 'src/loader/repair_warning.dart';
export 'src/loader/unknown_type.dart';
export 'src/scene/errors.dart';
export 'src/scene/node.dart';
export 'src/scene/overrides.dart';
export 'src/scene/scene.dart';
export 'src/scene/scene_codec.dart';
export 'src/scene/tree_repair.dart'
    show
        CycleBroken,
        DuplicateChild,
        MissingChild,
        MultipleParents,
        OrphanAttached,
        RepairReport,
        RootAsChild,
        SelfChild,
        TreeIssue;
export 'src/scene/values.dart';
