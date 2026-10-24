import 'package:pyro/process/process.dart';

/// A `VmServiceLink` that records its calls, and the order of everything
/// else the test appends to [log], for the re-point sequence (spec 007,
/// contracts/play-orchestration.md).
final class FakeVm implements VmServiceLink {
  /// Every call and request in order: `listViews`,
  /// `setAssetBundlePath <dir>`, `evict <asset>`, and whatever the test adds
  /// (`app.restart`).
  final log = <String>[];

  /// How many `setAssetBundlePath` calls are rejected before one succeeds.
  var rejectSetPath = 0;

  /// The address [connect] was called with.
  String? connectedTo;

  var connects = 0;
  var closed = false;

  /// The connector to give `PlayClient`.
  Future<VmServiceLink> connect(String wsUri) async {
    connects++;
    connectedTo = wsUri;
    return this;
  }

  @override
  Future<List<ViewInfo>> listViews() async {
    log.add('listViews');
    return const [ViewInfo(id: 'view/1', isolateId: 'isolates/1')];
  }

  @override
  Future<void> setAssetBundlePath({
    required String viewId,
    required String isolateId,
    required String assetDirectory,
  }) async {
    log.add('setAssetBundlePath $assetDirectory');
    if (rejectSetPath > 0) {
      rejectSetPath--;
      throw VmServiceCallFailed(
        '_flutter.setAssetBundlePath',
        'Asset directory does not exist',
      );
    }
  }

  @override
  Future<void> evict({required String isolateId, required String asset}) async {
    log.add('evict $asset');
  }

  @override
  Future<void> close() async => closed = true;

  @override
  String toString() => 'FakeVm';
}
