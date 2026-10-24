import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'redact.dart';

/// A Flutter view of the running game, as `_flutter.listViews` reports it.
final class ViewInfo {
  /// Creates the view.
  const ViewInfo({required this.id, required this.isolateId});

  /// The view's id, such as `_flutterView/0x…`.
  final String id;

  /// The id of the isolate that runs the view.
  final String isolateId;

  @override
  String toString() => 'ViewInfo($id, $isolateId)';
}

/// A call to the game's VM service that failed (spec 007, research R4).
///
/// The message is the engine's, with VM service auth codes masked; it never
/// holds the address.
final class VmServiceCallFailed implements Exception {
  /// Creates the failure of [method].
  VmServiceCallFailed(this.method, String message)
    : message = redactAuthCodes(message);

  /// The service method that failed: `_flutter.setAssetBundlePath`, or
  /// `connect`.
  final String method;

  /// What went wrong, in the engine's words.
  final String message;

  @override
  String toString() => '$method failed: $message';
}

/// The three VM service calls Play makes to keep Hot-swap working while an
/// IDE is attached (spec 007, research R4, R5): list the views, point the
/// engine's asset reads at Pyro's copy of the project, and evict a cached
/// asset. The first two are private engine extensions, so this is the one
/// place to re-check on each Flutter stable release.
abstract interface class VmServiceLink {
  /// Connects to the game's VM service at [wsUri], the address with its auth
  /// code. Throws [VmServiceCallFailed] (method `connect`) without the
  /// address in its message.
  static Future<VmServiceLink> connect(String wsUri) async {
    try {
      return _RealVmServiceLink(await vmServiceConnectUri(wsUri));
    } on Object {
      // The platform's own message names the address.
      throw VmServiceCallFailed(
        'connect',
        "couldn't connect to the game's VM service.",
      );
    }
  }

  /// `_flutter.listViews`.
  Future<List<ViewInfo>> listViews();

  /// `_flutter.setAssetBundlePath`.
  Future<void> setAssetBundlePath({
    required String viewId,
    required String isolateId,
    required String assetDirectory,
  });

  /// `ext.flutter.evict`: drops [asset] from the engine's asset cache.
  Future<void> evict({required String isolateId, required String asset});

  /// Closes the connection. Calls after it fail with [VmServiceCallFailed].
  Future<void> close();
}

final class _RealVmServiceLink implements VmServiceLink {
  _RealVmServiceLink(this._vm);

  final VmService _vm;
  var _closed = false;

  Future<Response> _call(
    String method, {
    String? isolateId,
    Map<String, Object?>? args,
  }) async {
    if (_closed) {
      throw VmServiceCallFailed(method, 'the connection is closed.');
    }
    try {
      return await _vm.callMethod(method, isolateId: isolateId, args: args);
    } on RPCError catch (error) {
      throw VmServiceCallFailed(method, error.message);
    } on Object {
      throw VmServiceCallFailed(method, 'the connection failed.');
    }
  }

  @override
  Future<List<ViewInfo>> listViews() async {
    final response = await _call('_flutter.listViews');
    final views = (response.json?['views'] as List?) ?? const [];
    return [
      for (final view in views.cast<Map<String, Object?>>())
        ViewInfo(
          id: view['id']! as String,
          isolateId:
              (view['isolate']! as Map<String, Object?>)['id']! as String,
        ),
    ];
  }

  @override
  Future<void> setAssetBundlePath({
    required String viewId,
    required String isolateId,
    required String assetDirectory,
  }) async {
    await _call(
      '_flutter.setAssetBundlePath',
      isolateId: isolateId,
      args: {'viewId': viewId, 'assetDirectory': assetDirectory},
    );
  }

  @override
  Future<void> evict({required String isolateId, required String asset}) async {
    await _call(
      'ext.flutter.evict',
      isolateId: isolateId,
      args: {'value': asset},
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _vm.dispose();
  }

  @override
  String toString() => 'VmServiceLink(connected)';
}
