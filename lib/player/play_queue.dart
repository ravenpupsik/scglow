import 'dart:math';

import '../core/models.dart';

enum LoopMode { off, all, one }

class PlayQueue {
  PlayQueue({Random? random}) : _random = random ?? Random();

  final Random _random;

  List<Track> _items = [];
  int _index = -1;
  bool _shuffle = false;
  LoopMode repeat = LoopMode.off;

  List<Track>? _unshuffled;

  List<Track> get items => List.unmodifiable(_items);
  int get index => _index;
  bool get shuffle => _shuffle;
  bool get isEmpty => _items.isEmpty;

  Track? get current =>
      _index >= 0 && _index < _items.length ? _items[_index] : null;

  List<Track> get upNext =>
      _index + 1 < _items.length ? _items.sublist(_index + 1) : const [];

  void setTracks(List<Track> tracks, {int start = 0, bool? shuffle}) {
    _items = [...tracks];
    _index = _items.isEmpty ? -1 : start.clamp(0, _items.length - 1);
    _unshuffled = null;
    if (shuffle != null) _shuffle = shuffle;
    if (_shuffle && _items.isNotEmpty) {
      final cur = _items[_index];
      final rest = [..._items]..removeAt(_index);
      _unshuffled = [..._items.sublist(_index + 1)];
      rest.shuffle(_random);
      _items = [cur, ...rest];
      _index = 0;
    }
  }

  void restore(List<Track> tracks, int index, {bool shuffle = false}) {
    _items = [...tracks];
    _index = _items.isEmpty ? -1 : index.clamp(0, _items.length - 1);
    _shuffle = shuffle;
    _unshuffled = null;
  }

  void setShuffle(bool on) {
    if (on == _shuffle) return;
    _shuffle = on;
    final head = _items.sublist(0, _index + 1);
    final rest = upNext;
    if (on) {
      _unshuffled = [...rest];
      final shuffled = [...rest]..shuffle(_random);
      _items = [...head, ...shuffled];
    } else {
      final saved = _unshuffled;
      _unshuffled = null;
      if (saved != null) {
        final remaining = rest.map((t) => t.id).toSet();
        final ordered = saved.where((t) => remaining.remove(t.id)).toList();
        ordered.addAll(rest.where((t) => remaining.contains(t.id)));
        _items = [...head, ...ordered];
      }
    }
  }

  void cycleRepeat() {
    repeat = LoopMode.values[(repeat.index + 1) % LoopMode.values.length];
  }

  int? nextIndex({bool auto = false}) {
    if (_items.isEmpty) return null;
    if (auto && repeat == LoopMode.one) return _index;
    if (_index + 1 < _items.length) return _index + 1;
    if (repeat != LoopMode.off) return 0;
    return null;
  }

  int? previousIndex() {
    if (_items.isEmpty) return null;
    if (_index > 0) return _index - 1;
    if (repeat == LoopMode.all) return _items.length - 1;
    return null;
  }

  void jumpTo(int i) {
    if (i >= 0 && i < _items.length) _index = i;
  }

  void moveUpNext(int from, int to) {
    final base = _index + 1;
    final n = _items.length - base;
    if (from < 0 || from >= n || to < 0 || to > n) return;
    final t = _items.removeAt(base + from);
    final dest = to > from ? to - 1 : to;
    _items.insert(base + dest, t);
    _unshuffled = null;
  }

  List<Track> clearUpNext() {
    final removed = upNext;
    _items = _items.sublist(0, _index + 1);
    return removed;
  }

  void restoreUpNext(List<Track> tracks) {
    final present = _items.map((t) => t.id).toSet();
    _items = [..._items, ...tracks.where((t) => !present.contains(t.id))];
  }

  void playNext(Track t) {
    _removeFromUpNext(t.id);
    if (_items.isEmpty) {
      _items = [t];
      _index = 0;
      return;
    }
    _items.insert(_index + 1, t);
  }

  void add(Track t) {
    _removeFromUpNext(t.id);
    _items.add(t);
    if (_index < 0) _index = 0;
  }

  bool remove(int trackId) {
    final i = _items.indexWhere((t) => t.id == trackId);
    if (i < 0) return false;
    _items.removeAt(i);
    final wasCurrent = i == _index;
    if (i < _index) _index--;
    if (_index >= _items.length) _index = _items.length - 1;
    return wasCurrent;
  }

  void _removeFromUpNext(int id) {
    for (var i = _items.length - 1; i > _index; i--) {
      if (_items[i].id == id) _items.removeAt(i);
    }
  }
}
