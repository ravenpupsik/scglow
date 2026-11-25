import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../core/models.dart';
import '../core/sc_api.dart';

class TrackDetails {
  TrackDetails(this.track);

  Track track;
  List<TrackComment>? comments;
  List<Track>? related;
  ScException? error;
  bool get loading => (comments == null || related == null) && error == null;
}

class TrackDetailsController extends ChangeNotifier {
  TrackDetailsController({required ScApi api, required this.onAuthProblem})
      : _api = api;

  final ScApi _api;
  final void Function(String source, ScAuthExpired error) onAuthProblem;
  final Map<int, TrackDetails> _cache = {};

  TrackDetails of(Track track) {
    final existing = _cache[track.id];
    if (existing != null) return existing;
    final d = TrackDetails(track);
    _cache[track.id] = d;
    _load(d);
    return d;
  }

  void retry(Track track) {
    _cache.remove(track.id);
    of(track);
    notifyListeners();
  }

  Future<void> _load(TrackDetails d) async {
    try {
      if (d.track.isStub || d.track.title.isEmpty) {
        d.track = await _api.track(d.track.id);
        notifyListeners();
      }
      d.comments = await _api.comments(d.track.id);
      notifyListeners();
      d.related = await _api.related(d.track.id);
    } on ScException catch (e) {
      if (e is ScAuthExpired) onAuthProblem('details.load', e);
      d.error = e;
      d.comments ??= const [];
      d.related ??= const [];
    }
    notifyListeners();
  }
}
