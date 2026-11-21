import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/tokens.dart';
import 'icons.dart';

enum ArtSize { large, t300, t500 }

String? artUrl(String? url, ArtSize size) {
  if (url == null || url.isEmpty) return null;
  return switch (size) {
    ArtSize.large => url,
    ArtSize.t300 => url.replaceAll('-large.', '-t300x300.'),
    ArtSize.t500 => url.replaceAll('-large.', '-t500x500.'),
  };
}

abstract final class ArtCache {
  static Directory? dir;
  static http.Client client = http.Client();

  static ImageProvider Function(String url)? override;

  static int _active = 0;
  static final _waiting = <Completer<void>>[];

  static Future<Uint8List> load(String url) async {
    final d = dir;
    final name = sha1.convert(url.codeUnits).toString();
    final file = d == null ? null : File('${d.path}${Platform.pathSeparator}$name');
    if (file != null && await file.exists()) return file.readAsBytes();
    await _slot();
    try {
      final res = await client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
      if (file != null) {
        try {
          await d!.create(recursive: true);
          await file.writeAsBytes(res.bodyBytes, flush: false);
        } catch (_) {}
      }
      return res.bodyBytes;
    } finally {
      _release();
    }
  }

  static Future<void> _slot() async {
    if (_active < 6) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
  }

  static void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _active--;
    }
  }
}

@immutable
class CachedArt extends ImageProvider<CachedArt> {
  const CachedArt(this.url);

  final String url;

  @override
  Future<CachedArt> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CachedArt key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(decode),
        scale: 1,
        debugLabel: url,
      );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await ArtCache.load(url);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is CachedArt && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

final ColorFilter _muted = () {
  const g = [0.3, 0.59, 0.11];
  const keep = 0.18, dark = 0.42;
  final m = <double>[];
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      final v = (1 - keep) * g[col] + (row == col ? keep : 0);
      m.add((1 - dark) * v);
    }
    m.addAll([0, dark * (row == 2 ? 22 : 20)]);
  }
  m.addAll([0, 0, 0, 1, 0]);
  return ColorFilter.matrix(m);
}();

bool isDefaultArt(String? url) =>
    url == null || url.isEmpty || url.contains('default_avatar');

class ArtPlaceholder extends StatelessWidget {
  const ArtPlaceholder({super.key, required this.size, this.radius = Dp.rCover});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.artTile,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: AgIcon(AgGlyph.note, color: c.artNote, size: size * 0.5),
    );
  }
}

class ArtImage extends StatelessWidget {
  const ArtImage({
    super.key,
    required this.url,
    required this.size,
    this.artSize = ArtSize.large,
    this.dimmed = false,
    this.radius = Dp.rCover,
  });

  final String? url;
  final double size;
  final ArtSize artSize;
  final bool dimmed;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = ArtPlaceholder(size: size, radius: radius);
    final u = isDefaultArt(url) ? null : artUrl(url, artSize);
    if (u == null) return placeholder;
    final px = (size * 2).round();
    final base = ArtCache.override?.call(u) ?? CachedArt(u);
    Widget img = Image(
      image: ResizeImage(base, width: px, height: px, allowUpscaling: false),
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, sync) =>
          frame == null && !sync ? placeholder : child,
      errorBuilder: (context, error, stack) => placeholder,
    );
    if (dimmed) {
      img = ColorFiltered(colorFilter: _muted, child: img);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: img),
    );
  }
}
