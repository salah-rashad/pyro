/// The open project: recent projects, SDK detection, Runtime compatibility,
/// asset-folder discovery and the Type catalog (spec 006, work items 1, 6).
library;

export 'asset_folders.dart'
    show
        AssetFolders,
        discoverAssetFolders,
        discoverImages,
        imageExtensions,
        isDeclaredFolder;
export 'build_runner_version.dart'
    show
        BuildRunnerAbsent,
        BuildRunnerOk,
        BuildRunnerTooOld,
        BuildRunnerUnknown,
        BuildRunnerVersion,
        minimumBuildRunner;
export 'catalog/behaviors.dart'
    show behaviorOffers, behaviorRefusal, satisfiesParentType;
export 'catalog/built_in.dart' show builtInTypes;
export 'catalog/manifest_parse.dart'
    show
        FieldDescriptor,
        ManifestAbsent,
        ManifestFailed,
        ManifestNewer,
        ManifestParsed,
        ManifestProblem,
        ManifestRead,
        ManifestStale,
        ManifestUnreadable,
        ManifestUpToDate,
        ManifestOrigin,
        TypeCatalog,
        TypeDescriptor,
        fieldTypesByName,
        maxManifestVersion,
        readManifest;
export 'catalog/parenting.dart'
    show
        AddParent,
        OfferedChild,
        ReparentAllowed,
        ReparentCheck,
        ReparentRefused,
        canReparent,
        childOffers,
        hitboxUnderRootReason;
export 'catalog/provider.dart'
    show
        TypeCatalogNotifier,
        catalogFileSystemProvider,
        manifestQuietPeriod,
        manifestRelativePath,
        manifestWatchProvider,
        typeCatalogProvider;
export 'recent_projects.dart' show RecentProjects, RecentProjectsStore;
export 'runtime_compat.dart'
    show RuntimeCompatStatus, RuntimeCompatibility, checkRuntimeCompatibility;
export 'sdk.dart'
    show
        PathVersion,
        SdkInfo,
        SdkSource,
        dartExecutable,
        detectSdk,
        flutterExecutable,
        flutterPathVersion;
