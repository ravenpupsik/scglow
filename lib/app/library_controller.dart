import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../core/json_store.dart';
import '../core/models.dart';
import '../core/sc_api.dart';
import 'search_index.dart';

enum LibraryStatus { empty, loading, ready }

class LibraryController extends ChangeNotifier {
  LibraryController({
    required ScApi api,
    required JsonStore store,
    required this.onAuthExpired,
    this.onError,
    this.pageDelay = const Duration(milliseconds: 400),
    DateTime Function()? clock,
  })  : _api = api,
        _store = store,
        _clock = clock ?? DateTime.now;

  static const cacheName = 'library_v1';

  final ScApi _api;
  final JsonStore _store;
  final VoidCallback onAuthExpired;
  final void Function(ScException error)? onError;
  final Duration pageDelay;
  final DateTime Function() _clock;

  static const focusMinInterval = Duration(minutes: 2);

  int? _userId;
  List<LikedTrack> _likes = [];
  List<Playlist> _playlists = [];
  final Map<int, Track> _tracks = {};
  final Set<int> likedIds = {};
  final Map<int, Unavailable> _runtimeUnavailable = {};

  LibraryStatus status = LibraryStatus.empty;
  bool refreshing = false;
  bool playlistsLoaded = false;
  ScException? error;
  int? totalLikes;

  LikesSort _sort = LikesSort.dateLiked;
  List<Track>? _sortedLikes;
  SearchIndex? _index;
  int _generation = 0;
  Future<void>? _refreshing;
  DateTime? _lastRefreshAt;
  final Set<int> _loadingPlaylists = {};

  int? get userId => _userId;
  LikesSort get sort => _sort;
  List<Playlist> get playlists => _playlists;
  int get likesCount => _likes.length;
  bool get hasData => _likes.isNotEmpty || _playlists.isNotEmpty;

  set sort(LikesSort value) {
    if (value == _sort) return;
    _sort = value;
    _sortedLikes = null;
    notifyListeners();
  }

  List<Track> get likes =>
      _sortedLikes ??= sortLikes(_likes, _sort).map((e) => e.track).toList();

  bool isLiked(Track t) => likedIds.contains(t.id);

  Unavailable? unavailableOf(Track t) =>
      _runtimeUnavailable[t.id] ?? t.unavailable;

  bool isPreview(Track t) => unavailableOf(t) == null && t.isPreviewOnly;

  List<Track>? playlistTracks(int playlistId) {
    final pl = _playlists.where((p) => p.id == playlistId).firstOrNull;
    if (pl == null) return null;
    if (pl.trackIds.isEmpty) return pl.trackCount == 0 ? const [] : null;
    final out = <Track>[];
    for (final id in pl.trackIds) {
      final t = _tracks[id];
      if (t == null) return null;
      out.add(t);
    }
    return out;
  }

  Track? trackById(int id) => _tracks[id];

  Playlist? playlistById(int id) =>
      _playlists.where((p) => p.id == id).firstOrNull;

  SearchIndex get index => _index ??= SearchIndex([
        ...likes,
        for (final p in _playlists) ...?playlistTracks(p.id),
      ]);

  List<Track> search(String query) => index.search(query);

  Future<void> open(int userId) async {
    if (_userId == userId && status != LibraryStatus.empty) {
      unawaited(refresh());
      return;
    }
    _userId = userId;
    await _loadCache(userId);
    unawaited(refresh());
  }

  Future<int?> openCached() async {
    final data = await _store.read(cacheName);
    final uid = data?['userId'] as int?;
    if (uid == null) return null;
    _userId = uid;
    _applyCache(data!);
    return uid;
  }

  void markOffline() {
    error = const ScNetworkError();
    status = LibraryStatus.empty;
    notifyListeners();
  }

  void reset({bool clearCache = false}) {
    _generation++;
    _userId = null;
    _likes = [];
    _playlists = [];
    _tracks.clear();
    likedIds.clear();
    _runtimeUnavailable.clear();
    status = LibraryStatus.empty;
    refreshing = false;
    playlistsLoaded = false;
    error = null;
    totalLikes = null;
    _refreshing = null;
    _lastRefreshAt = null;
    _invalidate();
    if (clearCache) unawaited(_store.delete(cacheName));
    notifyListeners();
  }

  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() {
        _refreshing = null;
      });

  Future<void> refreshOnFocus() {
    if (_refreshing != null) return Future.value();
    final last = _lastRefreshAt;
    if (last != null && _clock().difference(last) < focusMinInterval) {
      return Future.value();
    }
    return refresh();
  }

  Future<void> _refresh() async {
    final uid = _userId;
    if (uid == null) return;
    final gen = _generation;
    final hadCache = _likes.isNotEmpty;
    _lastRefreshAt = _clock();
    refreshing = true;
    error = null;
    if (!hadCache) status = LibraryStatus.loading;
    notifyListeners();
    try {
      final fresh = <LikedTrack>[];
      String? next;
      var first = true;
      var pages = 0;
      while ((first || next != null) && pages < 60) {
        if (!first) await Future<void>.delayed(pageDelay);
        final page = await _api.trackLikes(uid, nextHref: next);
        if (gen != _generation) return;
        fresh.addAll(page.items);
        next = page.nextHref;
        first = false;
        pages++;
        if (!hadCache) {
          _setLikes(fresh);
          notifyListeners();
        } else {
          _prependNewLikes(fresh);
        }
      }
      _setLikes(fresh);
      status = LibraryStatus.ready;
      notifyListeners();
      await _saveCache();

      final lists = await _api.playlists(uid);
      if (gen != _generation) return;
      final old = {for (final p in _playlists) p.id: p};
      _playlists = [
        for (final p in lists)
          if (old[p.id] != null &&
              old[p.id]!.lastModified == p.lastModified &&
              old[p.id]!.trackIds.isNotEmpty)
            p.copyWith(trackIds: old[p.id]!.trackIds)
          else
            p,
      ];
      playlistsLoaded = true;
      _invalidate();
      notifyListeners();
      for (final p in [..._playlists]) {
        if (playlistTracks(p.id) != null) continue;
        await Future<void>.delayed(pageDelay);
        if (gen != _generation) return;
        await _fetchPlaylist(p.id, gen);
      }
      await _saveCache();
    } on ScAuthExpired {
      onAuthExpired();
    } on ScException catch (e) {
      if (gen != _generation) return;
      error = e;
      if (_likes.isEmpty) {
        status = LibraryStatus.empty;
      } else {
        onError?.call(e);
      }
    } finally {
      if (gen == _generation) {
        refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadPlaylist(int id) async {
    if (playlistTracks(id) != null) return;
    try {
      await _fetchPlaylist(id, _generation);
      await _saveCache();
    } on ScAuthExpired {
      onAuthExpired();
    } on ScException catch (e) {
      onError?.call(e);
    }
  }

  Future<void> _fetchPlaylist(int id, int gen) async {
    if (!_loadingPlaylists.add(id)) return;
    try {
      final page = await _api.playlist(id);
      if (gen != _generation) return;
      for (final t in page.tracks) {
        if (!t.isStub || !_tracks.containsKey(t.id)) _tracks[t.id] = t;
      }
      _playlists = [
        for (final p in _playlists)
          if (p.id == id)
            p.copyWith(
              trackIds: page.playlist.trackIds,
              artworkUrl: p.artworkUrl ?? page.playlist.artworkUrl,
            )
          else
            p,
      ];
      _invalidate();
      notifyListeners();
    } finally {
      _loadingPlaylists.remove(id);
    }
  }

  Future<bool> toggleLike(Track track) async {
    final uid = _userId;
    if (uid == null) return false;
    final wasLiked = likedIds.contains(track.id);
    _applyLike(track, !wasLiked);
    try {
      if (wasLiked) {
        await _api.unlike(uid, track.id);
      } else {
        await _api.like(uid, track.id);
      }
      await _saveCache();
      return true;
    } on ScException catch (e) {
      _applyLike(track, wasLiked);
      if (e is ScAuthExpired) {
        onAuthExpired();
      } else {
        onError?.call(e);
      }
      return false;
    }
  }

  void _applyLike(Track track, bool liked) {
    if (liked) {
      likedIds.add(track.id);
      if (!_likes.any((l) => l.track.id == track.id)) {
        _likes = [LikedTrack(track, DateTime.now()), ..._likes];
        _tracks[track.id] = track;
      }
    } else {
      likedIds.remove(track.id);
    }
    _invalidate();
    notifyListeners();
  }

  void markUnavailable(Track track, Unavailable reason) {
    if (_runtimeUnavailable[track.id] == reason) return;
    _runtimeUnavailable[track.id] = reason;
    notifyListeners();
    unawaited(_saveCache());
  }

  void _prependNewLikes(List<LikedTrack> fresh) {
    final existing = likedIds;
    final newcomers = [for (final l in fresh) if (!existing.contains(l.track.id)) l];
    if (newcomers.isEmpty) return;
    _likes = [...newcomers, ..._likes];
    likedIds.addAll(newcomers.map((l) => l.track.id));
    for (final l in newcomers) {
      _tracks[l.track.id] = l.track;
    }
    _invalidate();
    notifyListeners();
  }

  void _setLikes(List<LikedTrack> items) {
    final seen = <int>{};
    _likes = [for (final l in items) if (seen.add(l.track.id)) l];
    likedIds
      ..clear()
      ..addAll(seen);
    for (final l in _likes) {
      _tracks[l.track.id] = l.track;
    }
    _invalidate();
  }

  void _invalidate() {
    _sortedLikes = null;
    _index = null;
  }

  Future<void> _loadCache(int userId) async {
    final data = await _store.read(cacheName);
    if (data == null || data['userId'] != userId) return;
    _applyCache(data);
  }

  void _applyCache(Map<String, dynamic> data) {
    try {
      final likes = ((data['likes'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => LikedTrack.fromJson(e.cast<String, dynamic>()))
          .toList();
      final tracks = ((data['tracks'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Track.fromJson(e.cast<String, dynamic>()));
      for (final t in tracks) {
        _tracks[t.id] = t;
      }
      _setLikes(likes);
      final liked = (data['liked'] as List?)?.whereType<int>();
      if (liked != null) {
        likedIds
          ..clear()
          ..addAll(liked);
      }
      _playlists = ((data['playlists'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Playlist.fromJson(e.cast<String, dynamic>()))
          .toList();
      playlistsLoaded = data.containsKey('playlists');
      final un = (data['unavailable'] as Map?) ?? const {};
      un.forEach((k, v) {
        final reason = Unavailable.values.where((u) => u.name == v).firstOrNull;
        final id = int.tryParse('$k');
        if (reason != null && id != null) _runtimeUnavailable[id] = reason;
      });
      totalLikes = data['total'] as int?;
      status = _likes.isEmpty && _playlists.isEmpty
          ? LibraryStatus.empty
          : LibraryStatus.ready;
      _invalidate();
      notifyListeners();
    } catch (_) {
    }
  }

  Future<void> _saveCache() async {
    final uid = _userId;
    if (uid == null) return;
    final playlistIds = {for (final p in _playlists) ...p.trackIds};
    final likedSet = {
      for (final l in _likes)
        if (likedIds.contains(l.track.id)) l.track.id,
    };
    await _store.write(cacheName, {
      'userId': uid,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'likes': [
        for (final l in _likes)
          if (likedIds.contains(l.track.id)) l.toJson(),
      ],
      'liked': likedIds.toList(),
      'tracks': [
        for (final id in playlistIds)
          if (!likedSet.contains(id) && _tracks[id] != null)
            _tracks[id]!.toJson(),
      ],
      if (playlistsLoaded) 'playlists': _playlists.map((p) => p.toJson()).toList(),
      'unavailable': {
        for (final e in _runtimeUnavailable.entries) '${e.key}': e.value.name,
      },
      if (totalLikes != null) 'total': totalLikes,
    });
  }
}
