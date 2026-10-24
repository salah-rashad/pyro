# Recorded transcripts (spec 007)

Real output recorded on the reference Mac for Phase 5's tests. The older daemon recordings of spec
005 stay in `../daemon/`.

**Auth codes.** `dart run bin/play.dart <project> --record <file>` masks every VM service auth code
as `<auth-code>` before it writes a line. `build_runner` prints no address. Before committing a
transcript, this must print nothing:

```bash
grep -rE '[A-Za-z0-9_-]{6,}=/' test/fixtures/transcripts
```

| File | Recorded with | Flutter | Date | Read by |
|---|---|---|---|---|
| `run-scene-save.txt` | `dart run bin/play.dart ../../example --record …` (start, one scene save, stop) | 3.47.7 | 2026-10-25 | `play_controller_test.dart` |
| `build-failure.txt` | the same, with a compile error added to `example/lib/code_marker.dart` and reverted after (a copy outside the repository does not resolve its workspace dependencies); the compiler's message went to stderr, which the file does not hold | 3.47.7 | 2026-10-25 | `play_controller_test.dart` |
| `exit-without-stop.txt` | the same; the game's process ended from outside (a scripted stand-in for closing its window: the same `Lost connection to device.` and `app.stop` as spec 005's `crash.txt`) | 3.47.7 | 2026-10-25 | `play_controller_test.dart` |
| `ide-attached.txt` | the same, plus `flutter attach -d macos --debug-uri <address>` in another terminal | 3.44.2 | — | `play_session_test.dart`, `play_controller_test.dart` |
| `build-runner-watch.txt` | `dart run build_runner watch` in `example/` (the first build, then a save of `lib/behaviors/spin.dart`) | 3.47.7 | 2026-10-25 | `generator_output_test.dart` |
| `build-runner-takeover.txt` | the same watcher's output while a second `dart run build_runner build` ran: it ends with `Exiting as requested by another build_runner process.` | 3.47.7 | 2026-10-25 | `generator_output_test.dart`, `generator_supervisor_test.dart` |
| `build-runner-waiting.txt` | the second process's own output in that run: `Waiting for already-running build_runner.`, then its build (exit 0) | 3.47.7 | 2026-10-25 | `generator_output_test.dart`, `generator_supervisor_test.dart` |
| `build-runner-stop.txt` | the watcher's output while `dart run build_runner stop` ran: the same exit line, so only the lock tells a stop from a takeover | 3.47.7 | 2026-10-25 | `generator_output_test.dart`, `generator_supervisor_test.dart` |
| `build-runner-error.txt` | a syntax error in `spin.dart`'s `@PyroBehavior` class (`double turnsPerSecond = ;`), then the fix | 3.47.7 | 2026-10-25 | `generator_output_test.dart`, `generator_supervisor_test.dart` |

A dash in the date column means the file is not recorded yet. The plan pins Flutter 3.44.2; the
reference Mac ran 3.47.7 when these were recorded.
