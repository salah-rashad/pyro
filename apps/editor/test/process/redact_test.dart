import 'package:flutter_test/flutter_test.dart';
import 'package:pyro/process/process.dart';

void main() {
  group('redactAuthCodes', () {
    test('masks the VM service URL the engine prints on desktop', () {
      expect(
        redactAuthCodes(
          'flutter: The Dart VM service is listening on '
          'http://127.0.0.1:50300/AbCdEf123456=/',
        ),
        'flutter: The Dart VM service is listening on '
        'http://127.0.0.1:50300/<auth-code>=/',
      );
    });

    test('masks a WebSocket URI', () {
      expect(
        redactAuthCodes('ws://127.0.0.1:50300/AbCdEf123456=/ws'),
        'ws://127.0.0.1:50300/<auth-code>=/ws',
      );
    });

    test("masks the tooling daemon's URI at the end of a line", () {
      expect(
        redactAuthCodes('DTD at ws://127.0.0.1:1235/AbCdEf123456='),
        'DTD at ws://127.0.0.1:1235/<auth-code>=',
      );
    });

    test('masks a code followed by a closing delimiter', () {
      const lines = [
        '(ws://127.0.0.1:1/AbCdEf123456=)',
        "'ws://127.0.0.1:1/AbCdEf123456='",
        'ws://127.0.0.1:1/AbCdEf123456=,',
        'ws://127.0.0.1:1/AbCdEf123456=.',
      ];
      for (final line in lines) {
        expect(
          redactAuthCodes(line),
          line.replaceAll('AbCdEf123456=', '<auth-code>='),
        );
      }
    });

    test('masks a URI inside JSON quotes', () {
      expect(
        redactAuthCodes('{"wsUri":"ws://127.0.0.1:50300/AbCdEf123456=/ws"}'),
        '{"wsUri":"ws://127.0.0.1:50300/<auth-code>=/ws"}',
      );
    });

    test('leaves lines without a code alone', () {
      const lines = [
        'Launching lib/main.dart on macOS in debug mode...',
        'See https://flutter.dev/to/add-desktop-support to learn more.',
        'http://127.0.0.1:8080/index.html',
      ];
      for (final line in lines) {
        expect(redactAuthCodes(line), line);
      }
    });

    group('the shapes of spec 007 (FR-037, SC-005)', () {
      test("masks the app.debugPort event's wsUri", () {
        expect(
          redactAuthCodes(
            '[{"event":"app.debugPort","params":{"appId":"a","port":50300,'
            '"wsUri":"ws://127.0.0.1:50300/AbCdEf123456=/ws",'
            '"baseUri":"file:///tmp/example/"}}]',
          ),
          '[{"event":"app.debugPort","params":{"appId":"a","port":50300,'
          '"wsUri":"ws://127.0.0.1:50300/<auth-code>=/ws",'
          '"baseUri":"file:///tmp/example/"}}]',
        );
      });

      test('masks a raw stdout line carrying the http address', () {
        expect(
          redactAuthCodes('flutter: listening at http://127.0.0.1:50300/AbC=/'),
          'flutter: listening at http://127.0.0.1:50300/<auth-code>=/',
        );
      });

      test("masks the tooling daemon's ws address at the end of a line", () {
        expect(
          redactAuthCodes(
            'The Dart Tooling Daemon is at ws://127.0.0.1:9/AbC=',
          ),
          'The Dart Tooling Daemon is at ws://127.0.0.1:9/<auth-code>=',
        );
      });

      test('masks an address inside a daemon error message', () {
        expect(
          redactAuthCodes(
            'Error: could not connect to ws://127.0.0.1:50300/AbC=/ws: refused',
          ),
          'Error: could not connect to ws://127.0.0.1:50300/<auth-code>=/ws: '
          'refused',
        );
      });

      test('leaves look-alikes byte for byte unchanged', () {
        const lines = [
          'ws://127.0.0.1:50300/ws',
          'key=value and other=thing',
          '/Users/me/project/assets/a=',
          'base64 AbCdEf123456= alone',
          'http://example.com/path/to/page',
        ];
        for (final line in lines) {
          expect(redactAuthCodes(line), line);
        }
      });

      test('ConsoleBuffer.add masks the same shapes', () {
        final buffer = ConsoleBuffer();
        addTearDown(buffer.dispose);
        buffer
          ..add('http://127.0.0.1:50300/AbC=/', source: ConsoleSource.game)
          ..add('ws://127.0.0.1:9/AbC=', source: ConsoleSource.pyro)
          ..add('key=value', source: ConsoleSource.generator);
        expect(buffer.lines.map((line) => line.text), [
          'http://127.0.0.1:50300/<auth-code>=/',
          'ws://127.0.0.1:9/<auth-code>=',
          'key=value',
        ]);
      });
    });
  });
}
