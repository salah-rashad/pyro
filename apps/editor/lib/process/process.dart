/// Play: runs the developer's game with `flutter run --machine` and
/// Hot-swaps its Scenes when they are saved (project plan §9.3; spec 005).
///
/// [PlayClient.start] returns a [PlaySession], whose events report the game's
/// lifecycle and output with VM service auth codes masked. Nothing here
/// imports Flutter, so `bin/play.dart` runs it with `dart run`.
library;

export 'src/build_lock.dart' show BuildLockProbe, LockProbeResult;
export 'src/console_buffer.dart' show ConsoleBuffer;
export 'src/console_line.dart' show ConsoleLine, ConsoleSeverity, ConsoleSource;
export 'src/generator_output.dart'
    show GeneratorLine, classifyGeneratorLine, severeFile;
export 'src/generator_state.dart' show GeneratorState, GeneratorStatus;
export 'src/generator_supervisor.dart' show GeneratorSupervisor;
export 'src/hot_swap_monitor.dart' show HotSwapMonitor;
export 'src/play_block.dart' show PlayBlock;
export 'src/play_client.dart' show PlayClient, ProcessStarter;
export 'src/play_controller.dart'
    show
        GameStopped,
        HotSwapFailed,
        PlayController,
        PlayNotice,
        PlayPhase,
        PlayStarter,
        RunLinkMaker;
export 'src/play_defaults.dart' show PlayDefaults;
export 'src/play_event.dart'
    show
        PlayDebuggerAvailable,
        PlayEvent,
        PlayFailed,
        PlayHotSwapFailed,
        PlayOutput,
        PlayOutputSource,
        PlayReloadFailed,
        PlayReloaded,
        PlayReloading,
        PlayStartException,
        PlayStarted,
        PlayStarting,
        PlayState,
        PlayStopped,
        ReloadResult;
export 'src/play_session.dart' show PlaySession;
export 'src/redact.dart' show redactAuthCodes;
export 'src/run_link.dart' show RunLink;
export 'src/scene_watcher.dart' show DirectoryWatcher, watchRecursively;
export 'src/vm_service_link.dart'
    show ViewInfo, VmServiceCallFailed, VmServiceLink;
