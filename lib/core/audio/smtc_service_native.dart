import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';

import 'audio_service.dart';

Future<void> initializeSmtc() async {
  await SMTCWindows.initialize();
}

class SmtcService {
  final SongloftAudioHandler _audioHandler;
  late final SMTCWindows _smtc;
  static const _disposePendingTimeout = Duration(seconds: 1);

  StreamSubscription<PlaybackState>? _playbackSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  StreamSubscription<PressedButton>? _buttonSub;
  StreamSubscription<Duration>? _positionSub;
  final _pendingCalls = <Future<void>>[];
  bool _disposed = false;

  SmtcService(this._audioHandler) {
    _smtc = SMTCWindows(
      config: const SMTCConfig(
        playEnabled: true,
        pauseEnabled: true,
        nextEnabled: true,
        prevEnabled: true,
        stopEnabled: true,
        fastForwardEnabled: false,
        rewindEnabled: false,
      ),
    );

    _listenButtons();
    _listenPlaybackState();
    _listenMediaItem();
    _listenPosition();
  }

  void _listenButtons() {
    _buttonSub = _smtc.buttonPressStream.listen((button) {
      if (_disposed) return;
      switch (button) {
        case PressedButton.play:
          _audioHandler.play();
        case PressedButton.pause:
          _audioHandler.pause();
        case PressedButton.next:
          _audioHandler.skipToNext();
        case PressedButton.previous:
          _audioHandler.skipToPrevious();
        case PressedButton.stop:
          _audioHandler.stop();
        default:
          break;
      }
    });
  }

  void _listenPlaybackState() {
    _playbackSub = _audioHandler.playbackState.listen((state) {
      if (_disposed) return;
      PlaybackStatus status;
      if (state.playing) {
        status = PlaybackStatus.playing;
      } else if (state.processingState == AudioProcessingState.idle) {
        status = PlaybackStatus.stopped;
      } else {
        status = PlaybackStatus.paused;
      }
      _runSmtc(() => _smtc.setPlaybackStatus(status));
    });
  }

  void _listenMediaItem() {
    _mediaItemSub = _audioHandler.mediaItem.listen((item) {
      if (_disposed) return;
      if (item == null) return;
      _runSmtc(
        () => _smtc.updateMetadata(
          MusicMetadata(
            title: item.title,
            artist: item.artist,
            album: item.album,
            thumbnail: item.artUri?.toString(),
          ),
        ),
      );
      if (item.duration != null) {
        _runSmtc(
          () => _smtc.updateTimeline(
            PlaybackTimeline(
              startTimeMs: 0,
              endTimeMs: item.duration!.inMilliseconds,
              positionMs: _audioHandler.position.inMilliseconds,
            ),
          ),
        );
      }
    });
  }

  void _listenPosition() {
    _positionSub = _audioHandler.positionStream.listen((position) {
      if (_disposed) return;
      final duration = _audioHandler.duration;
      _runSmtc(
        () => _smtc.updateTimeline(
          PlaybackTimeline(
            startTimeMs: 0,
            endTimeMs: duration?.inMilliseconds ?? 0,
            positionMs: position.inMilliseconds,
          ),
        ),
      );
    });
  }

  void _runSmtc(Future<void> Function() action) {
    if (_disposed) return;
    late Future<void> call;
    try {
      call = action()
          .catchError((Object e) {
            if (!_disposed) {
              debugPrint('[SmtcService] native call failed: $e');
            }
          })
          .whenComplete(() {
            _pendingCalls.remove(call);
          });
    } catch (e) {
      debugPrint('[SmtcService] native call failed: $e');
      return;
    }
    _pendingCalls.add(call);
    unawaited(call);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _buttonSub?.cancel();
    await _playbackSub?.cancel();
    await _mediaItemSub?.cancel();
    await _positionSub?.cancel();

    final pendingCalls = List<Future<void>>.of(_pendingCalls);
    if (pendingCalls.isNotEmpty) {
      try {
        await Future.wait(
          pendingCalls,
          eagerError: false,
        ).timeout(_disposePendingTimeout);
      } on TimeoutException {
        debugPrint(
          '[SmtcService] pending native calls timed out during dispose',
        );
      } catch (e) {
        debugPrint(
          '[SmtcService] pending native calls failed during dispose: $e',
        );
      }
      _pendingCalls.clear();
    }

    try {
      await _smtc.disableSmtc();
      await _smtc.clearMetadata();
    } catch (e) {
      debugPrint('[SmtcService] cleanup failed: $e');
    }
    try {
      await _smtc.dispose();
    } catch (e) {
      debugPrint('[SmtcService] dispose failed: $e');
    }
    debugPrint('[SmtcService] disposed');
  }
}
