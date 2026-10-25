// A standalone program, not a test: holds build_runner's lock the way a
// running `build_runner` does, so the lock probe meets a real operating-system
// lock from another process (spec 007, T027).
//
//   dart run test/helpers/hold_lock.dart <project>
//
// Prints `locked` once it holds the lock and releases it when stdin closes.
import 'dart:io';

Future<void> main(List<String> args) async {
  final file = File('${args.single}/.dart_tool/build/lock/build_runner.lock')
    ..createSync(recursive: true);
  final handle = await file.open(mode: FileMode.append);
  await handle.lock(FileLock.exclusive);
  stdout.writeln('locked');
  await stdin.drain<void>();
  await handle.unlock();
  await handle.close();
}
