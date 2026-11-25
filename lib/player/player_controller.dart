import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/diag_log.dart';
import '../core/errors.dart';
import '../core/json_store.dart';
import '../core/models.dart';
import 'audio_backend.dart';
import 'media_controls.dart';
import 'play_queue.dart';

class PlayerController extends ChangeNotifier {
  PlayerController({
    required AudioBackend backend,
    required Future<ResolvedStream> Function(Track track,
            {bool preferProgressive})
        resolveStream,
    required this.onAuthProblem,
    MediaControls? mediaControls,
    this.unavailableOf,
    this.onUnavailable,
    this.onMessage,
    JsonStore? store,
    PlayQueue? queue,
    DateTime Function()? clock,
  })  : _backend = backend,
        _resolve = resolveStream,
        _controls = mediaControls,
        _store = store,
        _clock = clock ?? DateTime.now,
        queue = queue ?? PlayQueue() {
    _subs.addAll([
      _backend.position.listen(_onPosition),
      _backend.duration.listen((d) {
        if (d > Duration.zero) duration.value = d;
      }),
      _backend.playing.listen((p) {
        if (p == _playing) return;
        _playing = p;
        _pausedAt = p ? null : _clock();
        _controls?.setPlaying(p);
        _saveSoon();
        notifyListeners();
      }),
      _backend.completed.listen((done) {
        if (!done || current == null || _loading || !_loaded) return;
        if (_endedEarly()) {
          _onLoadFailure(
              'ended at ${_rawPosition.inSeconds}s of ${duration.value.inSeconds}s; ${_cutoffState()}');
        } else {
          _onCompleted();
        }
      }),
      _backend.error.listen(_onBackendError),
    ]);
    _controls
      ?..onButton = _onMediaButton
      ..onSeek = seek;
  }

  static const stateName = 'player_v1';

  static const stalePause = Duration(minutes: 10);

  final AudioBackend _backend;
  final Future<ResolvedStream> Function(Track track, {bool preferProgressive})
      _resolve;
  final MediaControls? _controls;
  final JsonStore? _store;
  final void Function(String source, ScAuthExpired error) onAuthProblem;
  final Unavailable? Function(Track track)? unavailableOf;
  final void Function(Track track, Unavailable reason)? onUnavailable;
  final void Function(String message)? onMessage;
  final PlayQueue queue;
  final DateTime Function() _clock;
  final List<StreamSubscription<Object?>> _subs = [];

  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);

  bool _playing = false;
  bool _loading = false;
  bool _loaded = false;
  bool _isPreview = false;
  int _request = 0;
  double _volume = 70;
  bool _muted = false;
  Duration? _resumeAt;
  int? _resumeId;
  Duration _keepAt = Duration.zero;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _rawPosition = Duration.zero;
  Timer? _saveTimer;
  int _lastSavedSecond = -1;
  Duration _openedAt = Duration.zero;
  bool _retried = false;
  DateTime? _pausedAt;
  DateTime? _resolvedAt;
  String? _lastError;
  DateTime? _lastErrorAt;

  Track? get current => queue.current;
  bool get playing => _playing;
  bool get loading => _loading;
  bool get isPreview => _isPreview;
  double get volume => _volume;
  bool get muted => _muted;
  bool get shuffle => queue.shuffle;
  LoopMode get repeat => queue.repeat;
  List<Track> get upNext => queue.upNext;
  bool get hasTrack => current != null;

  bool _playable(Track t) => unavailableOf?.call(t) == null;

  Future<void> playTracks(List<Track> tracks,
      {int? start, bool? shuffle}) async {
    final startTrack = start != null && start >= 0 && start < tracks.length
        ? tracks[start]
        : null;
    final playable = tracks.where(_playable).toList();
    if (playable.isEmpty) {
      onMessage?.call('Nothing playable here');
      return;
    }
    var i = startTrack == null ? 0 : playable.indexOf(startTrack);
    if (i < 0) i = 0;
    if (startTrack == null && shuffle == true) {
      i = DateTime.now().microsecondsSinceEpoch % playable.length;
    }
    queue.setTracks(playable, start: i, shuffle: shuffle);
    _saveSoon();
    await _playIndex(queue.index);
  }

  Future<void> _playIndex(int index,
      {Duration? startAt, bool retry = false}) async {
    final request = ++_request;
    if (!retry) {
      _retried = false;
      _keepAt = Duration.zero;
    }
    if (startAt == null && !retry) _setResume(null, null);
    queue.jumpTo(index);
    for (var guard = 0; guard < 500; guard++) {
      final track = queue.current;
      if (track == null) break;
      if (startAt != null &&
          track.durationMs > 0 &&
          startAt >= Duration(milliseconds: track.durationMs) - const Duration(seconds: 5)) {
        startAt = null;
      }
      _loading = true;
      _loaded = false;
      _rawPosition = startAt ?? Duration.zero;
      _openedAt = _rawPosition;
      position.value = _rawPosition;
      duration.value = Duration(milliseconds: track.durationMs);
      notifyListeners();
      try {
        final resume = startAt != null && startAt > Duration.zero;
        final stream = await _resolve(track, preferProgressive: resume);
        if (request != _request) return;
        _resolvedAt = _clock();
        _lastError = null;
        if (resume) {
          final kind = stream.protocol.isEmpty
              ? describeStreamUrl(stream.url, _clock())
              : stream.protocol;
          final note = stream.isProgressive
              ? 'progressive'
              : 'no progressive stream, $kind';
          DiagLog.write(
              'player: ${track.id} opening at ${startAt.inSeconds}s with $note (${describeStreamUrl(stream.url, _clock())})');
        }
        _isPreview = stream.isPreview || track.isPreviewOnly;
        if (_isPreview) duration.value = const Duration(seconds: 30);
        final atStart = await _backend.open(stream.url, start: startAt);
        if (request != _request) return;
        if (!atStart) {
          _openedAt = Duration.zero;
          _rawPosition = Duration.zero;
          position.value = Duration.zero;
        }
        await _backend.setVolume(_muted ? 0 : _volume);
        _loaded = true;
        _setResume(null, null);
        await _controls?.setTrack(track);
        _loading = false;
        _saveSoon();
        notifyListeners();
        return;
      } on ScUnplayable catch (e) {
        if (request != _request) return;
        onUnavailable?.call(track, e.reason);
        final i = queue.index;
        queue.remove(track.id);
        startAt = null;
        if (queue.isEmpty) break;
        if (i >= queue.items.length) {
          if (queue.repeat == LoopMode.off) {
            queue.jumpTo(queue.items.length - 1);
            _stopAtEnd();
            return;
          }
          queue.jumpTo(0);
        } else {
          queue.jumpTo(i);
        }
      } on ScException catch (e) {
        if (e is ScAuthExpired) onAuthProblem('player.resolve', e);
        if (request != _request) return;
        if (startAt != null) _setResume(track, startAt);
        _loading = false;
        notifyListeners();
        onMessage?.call(friendlyError(e));
        return;
      }
    }
    if (request != _request) return;
    _loading = false;
    notifyListeners();
    onMessage?.call('Nothing playable here');
  }

  Future<void> playAt(int index) => _playIndex(index);

  // A saved position belongs to one track and is never applied to another.
  void _setResume(Track? track, Duration? at) {
    _resumeAt = track == null ? null : at;
    _resumeId = track?.id;
  }

  Duration? _resumeFor(Track track) => _resumeId == track.id ? _resumeAt : null;

  Future<void> togglePlay() async {
    final track = current;
    if (track == null) return;
    if (!_loaded) {
      if (!_loading) {
        final at = _resumeFor(track);
        await _playIndex(queue.index, startAt: at);
      }
      return;
    }
    if (_playing) {
      await _backend.pause();
      return;
    }
    final since = _pausedAt == null ? null : _clock().difference(_pausedAt!);
    if (since != null && since >= stalePause) {
      // Signed stream links expire; reopen at the same spot instead of resuming a dead one.
      DiagLog.write('player: paused ${since.inMinutes} min, fresh stream for ${track.id}');
      await _playIndex(queue.index, startAt: _rawPosition);
      return;
    }
    await _backend.play();
  }

  Future<void> play() async {
    if (!_playing) await togglePlay();
  }

  Future<void> pause() async {
    if (_playing) await _backend.pause();
  }

  Future<void> next() async {
    final i = queue.nextIndex();
    if (i != null) await _playIndex(i);
  }

  Future<void> previous() async {
    if (position.value > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    final i = queue.previousIndex();
    if (i == null) {
      await seek(Duration.zero);
    } else {
      await _playIndex(i);
    }
  }

  Future<void> seek(Duration to) async {
    if (!_loaded) {
      final t = current;
      if (t != null) _setResume(t, to);
      position.value = to;
      return;
    }
    position.value = to;
    await _backend.seek(to);
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0, 100);
    _muted = _volume == 0;
    await _backend.setVolume(_volume);
    _saveSoon();
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    if (!_muted && _volume == 0) _volume = 70;
    await _backend.setVolume(_muted ? 0 : _volume);
    _saveSoon();
    notifyListeners();
  }

  void toggleShuffle() {
    queue.setShuffle(!queue.shuffle);
    _saveSoon();
    notifyListeners();
  }

  void cycleRepeat() {
    queue.cycleRepeat();
    _saveSoon();
    notifyListeners();
  }

  void moveUpNext(int from, int to) {
    queue.moveUpNext(from, to);
    _saveSoon();
    notifyListeners();
  }

  List<Track> clearUpNext() {
    final removed = queue.clearUpNext();
    _saveSoon();
    notifyListeners();
    return removed;
  }

  void restoreUpNext(List<Track> tracks) {
    queue.restoreUpNext(tracks);
    _saveSoon();
    notifyListeners();
  }

  bool playNext(Track t) {
    if (!_playable(t)) return false;
    final wasEmpty = queue.isEmpty;
    queue.playNext(t);
    _saveSoon();
    notifyListeners();
    if (wasEmpty) _playIndex(0);
    return true;
  }

  bool addToQueue(Track t) {
    if (!_playable(t)) return false;
    final wasEmpty = queue.isEmpty;
    queue.add(t);
    _saveSoon();
    notifyListeners();
    if (wasEmpty) _playIndex(0);
    return true;
  }

  Future<void> stop() async {
    _request++;
    await _backend.stop();
    await _controls?.clear();
    queue.setTracks(const []);
    _loaded = false;
    _playing = false;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    await _store?.delete(stateName);
    notifyListeners();
  }

  void _onPosition(Duration p) {
    if (_loading) return;
    _rawPosition = p;
    final now = DateTime.now();
    if (now.difference(_lastTick) >= const Duration(milliseconds: 80)) {
      _lastTick = now;
      position.value = p;
    }
    _controls?.setTimeline(p, duration.value);
    final s = p.inSeconds;
    if (s % 5 == 0 && s != _lastSavedSecond) {
      _lastSavedSecond = s;
      _saveSoon();
    }
  }

  Future<void> _onCompleted() async {
    final i = queue.nextIndex(auto: true);
    if (i == null) {
      _stopAtEnd();
      return;
    }
    if (i == queue.index) {
      await _backend.seek(Duration.zero);
      await _backend.play();
      return;
    }
    await _playIndex(i);
  }

  void _stopAtEnd() {
    _loading = false;
    _loaded = false;
    _playing = false;
    _setResume(null, null);
    position.value = Duration.zero;
    _controls?.setPlaying(false);
    _saveSoon();
    notifyListeners();
  }

  void _onMediaButton(MediaButton button) {
    switch (button) {
      case MediaButton.play:
        play();
      case MediaButton.pause:
        pause();
      case MediaButton.next:
        next();
      case MediaButton.previous:
        previous();
      case MediaButton.stop:
        pause();
    }
  }

  bool _endedEarly() {
    final d = duration.value;
    return d > const Duration(seconds: 5) &&
        _rawPosition < d - const Duration(seconds: 5);
  }

  String _cutoffState() {
    final now = _clock();
    final linkAge = _resolvedAt == null ? '?' : '${now.difference(_resolvedAt!).inSeconds}s';
    final err = _lastError == null
        ? 'no backend error'
        : 'last error ${now.difference(_lastErrorAt!).inSeconds}s ago: $_lastError';
    return 'opened at ${_openedAt.inSeconds}s, link age $linkAge, playing $_playing, $err';
  }

  // Host, kind and expiry of a signed stream link; never the path or signature.
  static String describeStreamUrl(String url, DateTime now) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return 'unparsed link';
    final kind = u.path.endsWith('.m3u8') || u.path.contains('/playlist')
        ? 'hls'
        : 'progressive';
    int? epoch;
    final q = u.queryParameters;
    final expires = q['Expires'] ?? q['expires'];
    if (expires != null) epoch = int.tryParse(expires);
    final policy = q['Policy'];
    if (epoch == null && policy != null) {
      try {
        final norm = policy.replaceAll('-', '+').replaceAll('_', '=').replaceAll('~', '/');
        final text = utf8.decode(base64.decode(base64.normalize(norm)));
        final m = RegExp(r'"AWS:EpochTime"\s*:\s*(\d+)').firstMatch(text);
        if (m != null) epoch = int.parse(m.group(1)!);
      } catch (_) {}
    }
    final left = epoch == null
        ? 'expiry unknown'
        : 'expires in ${DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true).difference(now).inSeconds}s';
    return '${u.host}, $kind, $left';
  }

  void _onBackendError(String error) {
    _lastError = _scrubUrls(error);
    _lastErrorAt = _clock();
    final track = current;
    DiagLog.write('player: backend error on ${track?.id}: ${_scrubUrls(error)}');
    if (track == null || _loading || !_loaded) return;
    if (_rawPosition - _openedAt > const Duration(seconds: 1)) {
      onMessage?.call('Playback problem');
      return;
    }
    _onLoadFailure('backend error');
  }

  // A stream that fails to start is never a finished or removed track: retry once, then stop in place.
  void _onLoadFailure(String why) {
    final track = current;
    if (track == null) return;
    final at = _openedAt;
    if (!_retried) {
      _retried = true;
      _keepAt = at;
      if (at > Duration.zero) {
        DiagLog.write('player: ${track.id} failed to start at ${at.inSeconds}s ($why); fresh stream from 0, one retry');
      } else {
        DiagLog.write('player: ${track.id} failed to start ($why); fresh stream, one retry');
      }
      _playIndex(queue.index, retry: true);
      return;
    }
    DiagLog.write('player: ${track.id} failed to start again ($why); stopped');
    _request++;
    _backend.stop();
    _loading = false;
    _loaded = false;
    _playing = false;
    final keep = _keepAt > at ? _keepAt : at;
    _setResume(track, keep > Duration.zero ? keep : null);
    position.value = keep;
    _controls?.setPlaying(false);
    onMessage?.call(friendlyError(const ScStreamFailed()));
    _saveSoon();
    notifyListeners();
  }

  static String _scrubUrls(String text) => DiagLog.scrub(
      text.replaceAll(RegExp(r'https?://\S+'), '[url]'));

  Future<void> restore() async {
    final data = await _store?.read(stateName);
    if (data == null) return;
    try {
      final tracks = ((data['queue'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Track.fromJson(e.cast<String, dynamic>()))
          .toList();
      queue.restore(tracks, (data['index'] as int?) ?? 0,
          shuffle: (data['shuffle'] as bool?) ?? false);
      queue.repeat = LoopMode.values
              .where((r) => r.name == data['repeat'])
              .firstOrNull ??
          LoopMode.off;
      _volume = ((data['volume'] as num?) ?? 70).toDouble();
      _muted = (data['muted'] as bool?) ?? false;
      final pos = Duration(milliseconds: (data['positionMs'] as int?) ?? 0);
      final cur = queue.current;
      if (cur != null) {
        _setResume(cur, pos);
        position.value = pos;
        duration.value = Duration(
            milliseconds: cur.isPreviewOnly ? 30000 : cur.durationMs);
        await _controls?.setTrack(cur);
        await _controls?.setPlaying(false);
      }
      await _backend.setVolume(_muted ? 0 : _volume);
      notifyListeners();
    } catch (_) {}
  }

  Map<String, dynamic> snapshot() {
    final items = queue.items;
    final from = (queue.index - 50).clamp(0, items.length);
    final to = (queue.index + 1000).clamp(0, items.length);
    return {
      'queue': items.sublist(from, to).map((t) => t.toJson()).toList(),
      'index': queue.index - from,
      'positionMs': (_loaded ? _rawPosition : (_resumeAt ?? Duration.zero))
          .inMilliseconds,
      'shuffle': queue.shuffle,
      'repeat': queue.repeat.name,
      'volume': _volume,
      'muted': _muted,
    };
  }

  void _saveSoon() {
    if (_store == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), save);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    final store = _store;
    if (store == null) return;
    if (queue.isEmpty) {
      await store.delete(stateName);
      return;
    }
    await store.write(stateName, snapshot());
  }

  Future<void> shutdown() async {
    _saveTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    await _backend.dispose();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _backend.dispose();
    position.dispose();
    duration.dispose();
    super.dispose();
  }
}
