/// One-shot playback position restored from the previous app session.
///
/// The position is bound to the restored song identity so it cannot be
/// applied to a different song if the user changes the queue before resuming.
class PlaybackResumeState {
  int? _songId;
  String? _songType;
  Duration _position = Duration.zero;

  void restore({
    required int songId,
    required String songType,
    required Duration position,
  }) {
    if (position.inMilliseconds <= 0) {
      clear();
      return;
    }

    _songId = songId;
    _songType = songType;
    _position = position;
  }

  /// Returns the pending position for [songId] once, then clears it.
  ///
  /// A mismatched song also clears the pending value because the restored
  /// position is no longer valid after playback has moved elsewhere.
  Duration? takeFor({required int songId, required String songType}) {
    if (_songId != songId || _songType != songType) {
      clear();
      return null;
    }

    final position = _position;
    clear();
    return position.inMilliseconds > 0 ? position : null;
  }

  void clear() {
    _songId = null;
    _songType = null;
    _position = Duration.zero;
  }
}
