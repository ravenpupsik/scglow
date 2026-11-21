class ScUser {
  const ScUser({
    required this.id,
    required this.username,
    this.avatarUrl,
    this.likesCount,
  });

  final int id;
  final String username;
  final String? avatarUrl;
  final int? likesCount;

  factory ScUser.fromJson(Map<String, dynamic> json) => ScUser(
        id: json['id'] as int,
        username: (json['username'] as String?) ?? '',
        avatarUrl: json['avatar_url'] as String?,
        likesCount: json['likes_count'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (likesCount != null) 'likes_count': likesCount,
      };
}

class Transcoding {
  const Transcoding({
    required this.url,
    required this.protocol,
    required this.mimeType,
    required this.snipped,
    this.preset = '',
  });

  final String url;
  final String protocol;
  final String mimeType;
  final bool snipped;
  final String preset;

  bool get isEncrypted =>
      protocol.contains('encrypted') ||
      protocol.contains('cbc') ||
      protocol.contains('ctr') ||
      preset.contains('encrypted');

  factory Transcoding.fromJson(Map<String, dynamic> json) {
    final format = (json['format'] as Map?) ?? const {};
    return Transcoding(
      url: (json['url'] as String?) ?? '',
      protocol: (format['protocol'] as String?) ?? '',
      mimeType: (format['mime_type'] as String?) ?? '',
      snipped: (json['snipped'] as bool?) ?? false,
      preset: (json['preset'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'format': {'protocol': protocol, 'mime_type': mimeType},
        'snipped': snipped,
        if (preset.isNotEmpty) 'preset': preset,
      };
}

enum Unavailable {
  goPlusOnly('Go+ only'),
  removed('Removed');

  const Unavailable(this.label);
  final String label;
}

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.durationMs,
    this.artworkUrl,
    this.permalinkUrl,
    this.trackAuthorization,
    this.policy,
    this.monetizationModel,
    this.transcodings = const [],
    this.streamable = true,
    this.isStub = false,
    this.waveformUrl,
  });

  final int id;
  final String title;
  final String artist;
  final int durationMs;
  final String? artworkUrl;
  final String? permalinkUrl;
  final String? trackAuthorization;
  final String? policy;
  final String? monetizationModel;
  final List<Transcoding> transcodings;
  final bool streamable;

  final String? waveformUrl;

  final bool isStub;

  bool get isBlocked => policy == 'BLOCK' || !streamable;

  bool get isPreviewOnly =>
      policy == 'SNIP' ||
      (transcodings.isNotEmpty &&
          transcodings.where((t) => !t.isEncrypted).every((t) => t.snipped) &&
          transcodings.any((t) => !t.isEncrypted));

  Unavailable? get unavailable {
    if (isStub) return null;
    if (isBlocked) {
      return monetizationModel == 'SUB_HIGH_TIER'
          ? Unavailable.goPlusOnly
          : Unavailable.removed;
    }
    if (transcodings.isNotEmpty && transcodings.every((t) => t.isEncrypted)) {
      return Unavailable.goPlusOnly;
    }
    return null;
  }

  String? get largeArtworkUrl =>
      artworkUrl?.replaceAll('-large.', '-t500x500.');

  String? get smallArtworkUrl => artworkUrl;

  factory Track.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?) ?? const {};
    final media = (json['media'] as Map?) ?? const {};
    final list = (media['transcodings'] as List?) ?? const [];
    final publisher = json['publisher_metadata'];
    final publisherArtist =
        publisher is Map ? publisher['artist'] as String? : null;
    final isStub = !json.containsKey('title');
    return Track(
      id: json['id'] as int,
      title: (json['title'] as String?) ?? '',
      artist: (publisherArtist?.isNotEmpty ?? false)
          ? publisherArtist!
          : (user['username'] as String?) ?? '',
      durationMs:
          (json['full_duration'] as int?) ?? (json['duration'] as int?) ?? 0,
      artworkUrl:
          (json['artwork_url'] as String?) ?? (user['avatar_url'] as String?),
      permalinkUrl: json['permalink_url'] as String?,
      trackAuthorization: json['track_authorization'] as String?,
      policy: json['policy'] as String?,
      monetizationModel: json['monetization_model'] as String?,
      streamable: (json['streamable'] as bool?) ?? true,
      isStub: isStub,
      waveformUrl: json['waveform_url'] as String?,
      transcodings: list
          .whereType<Map>()
          .map((e) => Transcoding.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'publisher_metadata': {'artist': artist},
        'full_duration': durationMs,
        if (artworkUrl != null) 'artwork_url': artworkUrl,
        if (permalinkUrl != null) 'permalink_url': permalinkUrl,
        if (policy != null) 'policy': policy,
        if (monetizationModel != null) 'monetization_model': monetizationModel,
        'streamable': streamable,
        if (waveformUrl != null) 'waveform_url': waveformUrl,
        'media': {'transcodings': transcodings.map((t) => t.toJson()).toList()},
      };

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class LikedTrack {
  const LikedTrack(this.track, this.likedAt);

  final Track track;
  final DateTime likedAt;

  Map<String, dynamic> toJson() =>
      {'track': track.toJson(), 'at': likedAt.millisecondsSinceEpoch};

  factory LikedTrack.fromJson(Map<String, dynamic> json) => LikedTrack(
        Track.fromJson((json['track'] as Map).cast<String, dynamic>()),
        DateTime.fromMillisecondsSinceEpoch(json['at'] as int),
      );
}

class LikesPage {
  const LikesPage({required this.items, this.nextHref});

  final List<LikedTrack> items;
  final String? nextHref;

  List<Track> get tracks => items.map((e) => e.track).toList();
}

class Playlist {
  const Playlist({
    required this.id,
    required this.title,
    required this.trackCount,
    this.artworkUrl,
    this.owner = '',
    this.trackIds = const [],
    this.lastModified,
  });

  final int id;
  final String title;
  final int trackCount;
  final String? artworkUrl;
  final String owner;
  final List<int> trackIds;
  final String? lastModified;

  String? get largeArtworkUrl =>
      artworkUrl?.replaceAll('-large.', '-t500x500.');

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?) ?? const {};
    final tracks = (json['tracks'] as List?) ?? const [];
    String? art = json['artwork_url'] as String?;
    if (art == null) {
      for (final t in tracks.whereType<Map>()) {
        final a = t['artwork_url'] as String?;
        if (a != null) {
          art = a;
          break;
        }
      }
    }
    return Playlist(
      id: json['id'] as int,
      title: (json['title'] as String?) ?? 'Untitled',
      trackCount: (json['track_count'] as int?) ?? tracks.length,
      artworkUrl: art,
      owner: (user['username'] as String?) ?? '',
      lastModified: json['last_modified'] as String?,
      trackIds: [
        ...((json['track_ids'] as List?) ?? const []).whereType<int>(),
        ...tracks.whereType<Map>().map((t) => t['id']).whereType<int>(),
      ],
    );
  }

  Playlist copyWith({List<int>? trackIds, String? artworkUrl}) => Playlist(
        id: id,
        title: title,
        trackCount: trackCount,
        artworkUrl: artworkUrl ?? this.artworkUrl,
        owner: owner,
        trackIds: trackIds ?? this.trackIds,
        lastModified: lastModified,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'track_count': trackCount,
        if (artworkUrl != null) 'artwork_url': artworkUrl,
        'user': {'username': owner},
        if (lastModified != null) 'last_modified': lastModified,
        'track_ids': trackIds,
      };
}

class PlaylistPage {
  const PlaylistPage({required this.playlist, required this.tracks});

  final Playlist playlist;
  final List<Track> tracks;
}

class TrackComment {
  const TrackComment({
    required this.id,
    required this.atMs,
    required this.user,
    required this.body,
    this.avatarUrl,
  });

  final int id;

  final int? atMs;
  final String user;
  final String body;
  final String? avatarUrl;

  factory TrackComment.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?) ?? const {};
    return TrackComment(
      id: (json['id'] as int?) ?? 0,
      atMs: _ms(json['timestamp']),
      user: (user['username'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      avatarUrl: user['avatar_url'] as String?,
    );
  }

  static int? _ms(Object? v) => switch (v) {
        int() => v,
        num() => v.round(),
        String() => num.tryParse(v.trim())?.round(),
        _ => null,
      };
}

class ResolvedStream {
  const ResolvedStream({required this.url, required this.isPreview});

  final String url;
  final bool isPreview;
}
