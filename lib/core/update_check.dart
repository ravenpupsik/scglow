import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'app_version.dart';

const githubLatestRelease =
    'https://api.github.com/repos/ravenpupsik/scglow/releases/latest';

const updateCheckEvery = Duration(hours: 24);

const _notesLimit = 4000;

bool isCheckDue(DateTime now, DateTime? last,
        {Duration every = updateCheckEvery}) {
  if (last == null) return true;
  final elapsed = now.difference(last);
  if (elapsed.isNegative) return true;
  return elapsed >= every;
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    this.digest,
  });

  final String name;
  final String url;
  final String? digest;
}

class GithubRelease {
  const GithubRelease({
    required this.tag,
    required this.body,
    required this.assets,
  });

  final String tag;
  final String body;
  final List<ReleaseAsset> assets;

  factory GithubRelease.fromJson(Map<String, dynamic> json) {
    final assets = <ReleaseAsset>[];
    for (final raw in (json['assets'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final name = '${raw['name'] ?? ''}';
      final url = '${raw['browser_download_url'] ?? ''}';
      if (name.isEmpty || url.isEmpty) continue;
      assets.add(ReleaseAsset(
        name: name,
        url: url,
        digest: raw['digest'] as String?,
      ));
    }
    return GithubRelease(
      tag: '${json['tag_name'] ?? json['name'] ?? ''}',
      body: '${json['body'] ?? ''}',
      assets: assets,
    );
  }
}

class UpdateOffer {
  const UpdateOffer({
    required this.version,
    required this.notes,
    required this.assetName,
    required this.assetUrl,
    required this.sha256,
    this.checksumUrl,
  });

  final AppVersion version;
  final String notes;
  final String assetName;
  final String assetUrl;
  final String sha256;
  final String? checksumUrl;
}

class UpdateCheckResult {
  const UpdateCheckResult._(this.offer, this.error, this._latestTag);

  const UpdateCheckResult.latest(String tag) : this._(null, null, tag);
  const UpdateCheckResult.available(UpdateOffer offer) : this._(offer, null, null);
  const UpdateCheckResult.failed(String error) : this._(null, error, null);

  final UpdateOffer? offer;
  final String? error;
  final String? _latestTag;

  String? get latestTag => _latestTag ?? offer?.version.label;

  bool get isLatest => offer == null && error == null;
  bool get isAvailable => offer != null;
  bool get isFailed => error != null;
}

String truncateNotes(String body, {int limit = _notesLimit}) {
  var text = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (text.length <= limit) return text;
  var cut = text.substring(0, limit);
  final nl = cut.lastIndexOf('\n');
  if (nl >= limit ~/ 2) cut = cut.substring(0, nl);
  return '${cut.trimRight()}\n…';
}

String? sha256FromDigest(String? digest) {
  if (digest == null) return null;
  final s = digest.trim();
  final i = s.indexOf(':');
  if (i <= 0) return _hexOrNull(s);
  if (s.substring(0, i).toLowerCase() != 'sha256') return null;
  return _hexOrNull(s.substring(i + 1));
}

String? sha256FromFile(String text) {
  final line = text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (line.isEmpty) return null;
  final eq = RegExp(r'=\s*([A-Fa-f0-9]{64})\s*$').firstMatch(line);
  if (eq != null) return eq.group(1)!.toLowerCase();
  final hex = RegExp(r'^[A-Fa-f0-9]{64}').firstMatch(line);
  return hex?.group(0)!.toLowerCase();
}

String? _hexOrNull(String s) {
  final h = s.trim().toLowerCase();
  return RegExp(r'^[a-f0-9]{64}$').hasMatch(h) ? h : null;
}

String sha256OfBytes(List<int> bytes) => sha256.convert(bytes).toString();

Future<String> sha256OfFile(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

// Picks the Windows zip that matches the tag and a SHA-256 from the digest or a .sha256 asset.
UpdateOffer? offerFromRelease(GithubRelease release, AppVersion current) {
  final version = AppVersion.tryParse(release.tag);
  if (version == null) return null;
  if (version.compareTo(current) <= 0) return null;
  final zip = selectWindowsZip(release.assets, version);
  if (zip == null) return null;
  final digest = sha256FromDigest(zip.digest);
  if (digest != null) {
    return UpdateOffer(
      version: version,
      notes: truncateNotes(release.body),
      assetName: zip.name,
      assetUrl: zip.url,
      sha256: digest,
    );
  }
  final side = selectChecksumAsset(release.assets, zip.name);
  if (side == null) return null;
  return UpdateOffer(
    version: version,
    notes: truncateNotes(release.body),
    assetName: zip.name,
    assetUrl: zip.url,
    sha256: '',
    checksumUrl: side.url,
  );
}

ReleaseAsset? selectWindowsZip(List<ReleaseAsset> assets, AppVersion version) {
  final labels = {version.label, '${version.major}.${version.minor}.${version.patch}'};
  bool isZip(ReleaseAsset a) =>
      a.name.toLowerCase().endsWith('.zip') &&
      !a.name.toLowerCase().endsWith('.sha256');
  ReleaseAsset? named(String name) =>
      assets.where((a) => isZip(a) && a.name.toLowerCase() == name.toLowerCase()).firstOrNull;
  for (final v in labels) {
    final preferred = named('scglow-windows-$v.zip');
    if (preferred != null) return preferred;
  }
  for (final v in labels) {
    final legacy = named('scglow-$v-windows-x64.zip');
    if (legacy != null) return legacy;
  }
  final any = assets.where((a) {
    final n = a.name.toLowerCase();
    return isZip(a) && n.startsWith('scglow') && n.contains('windows');
  });
  return any.length == 1 ? any.first : any.where((a) {
    final n = a.name.toLowerCase();
    return labels.any((v) => n.contains(v.toLowerCase()));
  }).firstOrNull ?? (any.length == 1 ? any.first : null);
}

ReleaseAsset? selectChecksumAsset(List<ReleaseAsset> assets, String zipName) {
  final want = {
    '$zipName.sha256'.toLowerCase(),
    '${zipName.toLowerCase()}.sha256',
  };
  return assets.where((a) => want.contains(a.name.toLowerCase())).firstOrNull;
}

Future<UpdateCheckResult> checkLatestRelease({
  required http.Client client,
  AppVersion current = AppVersion.current,
  Uri? url,
}) async {
  http.Response res;
  try {
    res = await client.get(
      url ?? Uri.parse(githubLatestRelease),
      headers: {
        'User-Agent': 'scglow/${current.label}',
        'Accept': 'application/vnd.github+json',
      },
    ).timeout(const Duration(seconds: 20));
  } on SocketException {
    return const UpdateCheckResult.failed(
        "Couldn't check for updates. Check your connection and try again.");
  } on HttpException {
    return const UpdateCheckResult.failed(
        "Couldn't check for updates. Check your connection and try again.");
  } on TimeoutException {
    return const UpdateCheckResult.failed(
        "Couldn't check for updates. The request timed out.");
  } catch (_) {
    return const UpdateCheckResult.failed("Couldn't check for updates.");
  }
  if (res.statusCode == 404) {
    return const UpdateCheckResult.failed('No releases found.');
  }
  if (res.statusCode != 200) {
    return UpdateCheckResult.failed(
        "Couldn't check for updates (GitHub returned ${res.statusCode}).");
  }
  Map<String, dynamic> json;
  try {
    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) {
      return const UpdateCheckResult.failed("Couldn't read the release information.");
    }
    json = data;
  } catch (_) {
    return const UpdateCheckResult.failed("Couldn't read the release information.");
  }
  final release = GithubRelease.fromJson(json);
  final version = AppVersion.tryParse(release.tag);
  if (version == null) {
    return const UpdateCheckResult.failed("Couldn't read the latest version.");
  }
  if (version.compareTo(current) <= 0) {
    return UpdateCheckResult.latest(release.tag);
  }
  final zip = selectWindowsZip(release.assets, version);
  if (zip == null) {
    return const UpdateCheckResult.failed(
        'A newer version is out, but no Windows package was attached.');
  }
  var sha = sha256FromDigest(zip.digest);
  String? checksumUrl;
  if (sha == null) {
    final side = selectChecksumAsset(release.assets, zip.name);
    if (side == null) {
      return const UpdateCheckResult.failed(
          'A newer version is out, but it has no SHA-256 checksum.');
    }
    checksumUrl = side.url;
    try {
      final file = await client.get(Uri.parse(side.url), headers: {
        'User-Agent': 'scglow/${current.label}',
      }).timeout(const Duration(seconds: 20));
      if (file.statusCode != 200) {
        return const UpdateCheckResult.failed(
            "Couldn't download the SHA-256 checksum.");
      }
      sha = sha256FromFile(file.body);
    } catch (_) {
      return const UpdateCheckResult.failed(
          "Couldn't download the SHA-256 checksum.");
    }
    if (sha == null) {
      return const UpdateCheckResult.failed(
          "Couldn't read the SHA-256 checksum.");
    }
  }
  return UpdateCheckResult.available(UpdateOffer(
    version: version,
    notes: truncateNotes(release.body),
    assetName: zip.name,
    assetUrl: zip.url,
    sha256: sha,
    checksumUrl: checksumUrl,
  ));
}

class DownloadException implements Exception {
  const DownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<File> downloadAndVerify({
  required http.Client client,
  required UpdateOffer offer,
  required Directory dir,
  void Function(int received, int? total)? onProgress,
  AppVersion current = AppVersion.current,
}) async {
  await dir.create(recursive: true);
  final dest = File('${dir.path}${Platform.pathSeparator}${offer.assetName}');
  if (await dest.exists()) await dest.delete();
  http.StreamedResponse res;
  try {
    final req = http.Request('GET', Uri.parse(offer.assetUrl));
    req.headers['User-Agent'] = 'scglow/${current.label}';
    res = await client.send(req).timeout(const Duration(seconds: 30));
  } catch (_) {
    throw const DownloadException("Couldn't download the update.");
  }
  if (res.statusCode != 200) {
    throw DownloadException(
        "Couldn't download the update (GitHub returned ${res.statusCode}).");
  }
  final total = res.contentLength;
  final out = dest.openWrite();
  var got = 0;
  try {
    await for (final chunk in res.stream) {
      got += chunk.length;
      out.add(chunk);
      onProgress?.call(got, total);
    }
    await out.close();
  } catch (e) {
    try {
      await out.close();
    } catch (_) {}
    try {
      await dest.delete();
    } catch (_) {}
    if (e is DownloadException) rethrow;
    throw const DownloadException("Couldn't download the update.");
  }
  final actual = await sha256OfFile(dest);
  if (actual != offer.sha256.toLowerCase()) {
    try {
      await dest.delete();
    } catch (_) {}
    throw const DownloadException(
        'The download did not match its SHA-256 checksum, so it was deleted.');
  }
  return dest;
}
