import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/process.dart';

/// A VM service stand-in: a WebSocket JSON-RPC server on 127.0.0.1 only
/// (spec 007, T041). It records every request and answers from [answers].
final class FakeVmService {
  FakeVmService._(this._server, this.authCode);

  static Future<FakeVmService> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeVmService._(server, 'Zq3xK9mP2vTn');
    unawaited(
      server.forEach((request) async {
        // Closed with the server.
        // ignore: close_sinks
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((data) {
          final message = jsonDecode(data as String) as Map<String, Object?>;
          fake.requests.add(message);
          final method = message['method'] as String;
          final answer = fake.answers[method];
          final id = message['id'];
          socket.add(
            jsonEncode(
              answer == null
                  ? {
                      'jsonrpc': '2.0',
                      'id': id,
                      'error': {
                        'code': -32601,
                        'message': 'Method not found: $method',
                      },
                    }
                  : answer(message),
            ),
          );
        });
      }),
    );
    return fake;
  }

  final HttpServer _server;
  final String authCode;

  /// Every request, in order.
  final requests = <Map<String, Object?>>[];

  /// Answers by method name; each returns the whole JSON-RPC response.
  final answers =
      <String, Map<String, Object?> Function(Map<String, Object?>)>{};

  /// The address as the daemon reports it: an auth code in the path.
  String get wsUri => 'ws://127.0.0.1:${_server.port}/$authCode=/ws';

  Map<String, Object?> result(Map<String, Object?> request, Object value) => {
    'jsonrpc': '2.0',
    'id': request['id'],
    'result': value,
  };

  Map<String, Object?> error(
    Map<String, Object?> request,
    int code,
    String message,
  ) => {
    'jsonrpc': '2.0',
    'id': request['id'],
    'error': {'code': code, 'message': message},
  };

  Future<void> close() => _server.close(force: true);
}

void main() {
  late FakeVmService fake;
  late VmServiceLink link;

  setUp(() async {
    fake = await FakeVmService.start();
    fake.answers['_flutter.listViews'] = (request) => fake.result(request, {
      'type': 'FlutterViewList',
      'views': [
        {
          'type': 'FlutterView',
          'id': '_flutterView/0x1',
          'isolate': {'type': '@Isolate', 'id': 'isolates/1', 'name': 'main'},
        },
      ],
    });
    link = await VmServiceLink.connect(fake.wsUri);
  });

  tearDown(() async {
    await link.close();
    await fake.close();
  });

  test('listViews sends _flutter.listViews and reads the views', () async {
    final views = await link.listViews();
    expect(fake.requests.single['method'], '_flutter.listViews');
    expect(views, hasLength(1));
    expect(views.single.id, '_flutterView/0x1');
    expect(views.single.isolateId, 'isolates/1');
  });

  test('setAssetBundlePath sends the view, isolate and directory', () async {
    fake.answers['_flutter.setAssetBundlePath'] = (request) =>
        fake.result(request, {'type': 'Success'});
    await link.setAssetBundlePath(
      viewId: '_flutterView/0x1',
      isolateId: 'isolates/1',
      assetDirectory: 'file:///proj/build/flutter_assets',
    );
    final request = fake.requests.single;
    expect(request['method'], '_flutter.setAssetBundlePath');
    expect(request['params'], {
      'viewId': '_flutterView/0x1',
      'isolateId': 'isolates/1',
      'assetDirectory': 'file:///proj/build/flutter_assets',
    });
  });

  test(
    'evict sends ext.flutter.evict with the isolate and the asset',
    () async {
      fake.answers['ext.flutter.evict'] = (request) =>
          fake.result(request, {'type': 'Success'});
      await link.evict(
        isolateId: 'isolates/1',
        asset: 'assets/scenes/level1.scene.json',
      );
      final request = fake.requests.single;
      expect(request['method'], 'ext.flutter.evict');
      expect(request['params'], {
        'isolateId': 'isolates/1',
        'value': 'assets/scenes/level1.scene.json',
      });
    },
  );

  group('a rejected call', () {
    test(
      'throws VmServiceCallFailed naming the method and the engine',
      () async {
        fake.answers['_flutter.setAssetBundlePath'] = (request) =>
            fake.error(request, -32000, 'Asset directory does not exist');
        await expectLater(
          link.setAssetBundlePath(
            viewId: 'v',
            isolateId: 'i',
            assetDirectory: 'file:///nope',
          ),
          throwsA(
            isA<VmServiceCallFailed>()
                .having(
                  (e) => e.method,
                  'method',
                  '_flutter.setAssetBundlePath',
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('does not exist'),
                ),
          ),
        );
      },
    );

    test('never shows the address in the exception', () async {
      // The engine echoes the request URI back in its message.
      fake.answers['ext.flutter.evict'] = (request) =>
          fake.error(request, -32000, 'failed for ${fake.wsUri}');
      try {
        await link.evict(isolateId: 'i', asset: 'a');
        fail('expected a failure');
      } on VmServiceCallFailed catch (error) {
        expect('$error', isNot(contains(fake.authCode)));
        expect(error.message, isNot(contains(fake.authCode)));
        expect('$error', contains('ext.flutter.evict'));
      }
    });

    test('an unknown method is a failure naming it', () async {
      await expectLater(
        link.evict(isolateId: 'i', asset: 'a'),
        throwsA(
          isA<VmServiceCallFailed>().having(
            (e) => e.method,
            'method',
            'ext.flutter.evict',
          ),
        ),
      );
    });
  });

  test('toString of the link hides the address', () {
    expect('$link', isNot(contains(fake.authCode)));
    expect('$link', isNot(contains(fake.wsUri)));
  });

  test('a connection that fails says so without the address', () async {
    final address = fake.wsUri;
    await fake.close();
    try {
      await VmServiceLink.connect(address);
      fail('expected a failure');
    } on VmServiceCallFailed catch (error) {
      expect('$error', isNot(contains(fake.authCode)));
      expect('$error', isNot(contains('127.0.0.1')));
      expect(error.method, 'connect');
    }
  });

  test('calls after close fail rather than hang', () async {
    await link.close();
    await expectLater(
      link.listViews().timeout(const Duration(seconds: 5)),
      throwsA(isA<VmServiceCallFailed>()),
    );
  });
}
