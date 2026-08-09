import 'package:flutter_test/flutter_test.dart';
import 'package:songloft_flutter/features/player/domain/use_cases/playback_resume_state.dart';

void main() {
  late PlaybackResumeState resumeState;

  setUp(() {
    resumeState = PlaybackResumeState();
  });

  test('returns the restored position once for the matching song', () {
    resumeState.restore(
      songId: 35,
      songType: 'local',
      position: const Duration(seconds: 19),
    );

    expect(
      resumeState.takeFor(songId: 35, songType: 'local'),
      const Duration(seconds: 19),
    );
    expect(resumeState.takeFor(songId: 35, songType: 'local'), isNull);
  });

  test('does not apply the position to a different song', () {
    resumeState.restore(
      songId: 35,
      songType: 'local',
      position: const Duration(seconds: 19),
    );

    expect(resumeState.takeFor(songId: 36, songType: 'local'), isNull);
    expect(resumeState.takeFor(songId: 35, songType: 'local'), isNull);
  });

  test('includes song type in the restored identity', () {
    resumeState.restore(
      songId: 35,
      songType: 'local',
      position: const Duration(seconds: 19),
    );

    expect(resumeState.takeFor(songId: 35, songType: 'radio'), isNull);
  });

  test('clear discards the restored position', () {
    resumeState.restore(
      songId: 35,
      songType: 'local',
      position: const Duration(seconds: 19),
    );

    resumeState.clear();

    expect(resumeState.takeFor(songId: 35, songType: 'local'), isNull);
  });

  test('zero position is not retained', () {
    resumeState.restore(songId: 35, songType: 'local', position: Duration.zero);

    expect(resumeState.takeFor(songId: 35, songType: 'local'), isNull);
  });
}
