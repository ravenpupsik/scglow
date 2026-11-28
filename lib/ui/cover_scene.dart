import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/app_services.dart';
import '../core/diag_log.dart';
import '../core/models.dart';
import '../player/player_controller.dart';
import 'focus_view.dart';
import 'theme/tokens.dart';
import 'widgets/art_image.dart';
import 'widgets/glass.dart';

abstract final class CoverColor {
  static const satCap = 0.28;
  static const darkL = (11.0, 35.0);
  static const lightL = (80.0, 94.0);
  static const chromaCap = 22.0;

  static Color? dominant(Uint8List rgba, int size) {
    if (size < 16 || rgba.length < size * size * 4) return null;
    final block = size ~/ 16;
    final cells = <List<double>>[];
    for (var by = 0; by < 16; by++) {
      for (var bx = 0; bx < 16; bx++) {
        double r = 0, g = 0, b = 0;
        for (var y = by * block; y < (by + 1) * block; y++) {
          for (var x = bx * block; x < (bx + 1) * block; x++) {
            final i = (y * size + x) * 4;
            r += rgba[i];
            g += rgba[i + 1];
            b += rgba[i + 2];
          }
        }
        final n = (block * block).toDouble();
        cells.add([r / n, g / n, b / n]);
      }
    }
    final mid = cells.where((c) {
      final l = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
      return l > 18 && l < 240;
    }).toList();
    final use = mid.length >= 8 ? mid : cells;
    double r = 0, g = 0, b = 0;
    for (final c in use) {
      r += c[0];
      g += c[1];
      b += c[2];
    }
    final n = use.length;
    return Color.fromARGB(
      255,
      (r / n).round(),
      (g / n).round(),
      (b / n).round(),
    );
  }

  // Two or three distinct colours of the cover, most prominent first, for the
  // Focus backdrop. Weighted by area and saturation; near-duplicates merge.
  static List<Color> palette(Uint8List rgba, int size, {int count = 3}) {
    if (size < 16 || rgba.length < size * size * 4) return const [];
    final buckets = <int, List<double>>{};
    for (var i = 0; i < size * size; i++) {
      final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
      final (h, s, l) = _rgbToHsl((r, g, b));
      if (l < 0.06 || l > 0.96) continue;
      final hb = s < 0.12 ? 12 : (h * 12).floor() % 12;
      final lb = (l * 3).floor().clamp(0, 2);
      final key = hb * 3 + lb;
      final w = 0.25 + s;
      final e = buckets.putIfAbsent(key, () => [0, 0, 0, 0]);
      e[0] += r * w;
      e[1] += g * w;
      e[2] += b * w;
      e[3] += w;
    }
    final ranked = buckets.values.toList()..sort((a, b) => b[3].compareTo(a[3]));
    final out = <Color>[];
    for (final e in ranked) {
      final c = Color.fromARGB(255, (e[0] / e[3]).round(), (e[1] / e[3]).round(),
          (e[2] / e[3]).round());
      if (out.every((o) => _distance(o, c) > 40)) out.add(c);
      if (out.length == count) break;
    }
    if (out.isEmpty) return const [];
    final (h, s, l) = _rgbToHsl(_rgb(out.first));
    while (out.length < 2) {
      final rgb = _hslToRgb(h, s, (l * 0.45).clamp(0.05, 1.0));
      out.add(Color.fromARGB(255, rgb.$1, rgb.$2, rgb.$3));
    }
    return out;
  }

  static double _distance(Color a, Color b) {
    final (l1, a1, b1) = _rgbToLab(_rgb(a));
    final (l2, a2, b2) = _rgbToLab(_rgb(b));
    return math.sqrt((l1 - l2) * (l1 - l2) + (a1 - a2) * (a1 - a2) + (b1 - b2) * (b1 - b2)) *
        2.55;
  }

  // A palette colour toned for the full-window Focus backdrop: rich but never
  // glaring behind the sharp cover.
  static Color glow(Color c, {required bool night}) {
    final (h, s, l) = _rgbToHsl(_rgb(c));
    final ss = math.min(s, 0.78);
    final ll = night ? l.clamp(0.16, 0.42) : l.clamp(0.55, 0.80);
    final rgb = _hslToRgb(h, ss, ll);
    return Color.fromARGB(255, rgb.$1, rgb.$2, rgb.$3);
  }

  static Color glowBase(Color c, {required bool night}) {
    final (h, s, l) = _rgbToHsl(_rgb(c));
    final rgb = _hslToRgb(h, math.min(s, 0.6), night ? 0.07 + 0.06 * l : 0.86 + 0.06 * l);
    return Color.fromARGB(255, rgb.$1, rgb.$2, rgb.$3);
  }

  static Color windowTint(Color cover, {required bool night}) {
    final (h, s0, l0) = _rgbToHsl(_rgb(cover));
    final (sl, a0, b0) = _rgbToLab(_hslToRgb(h, math.min(s0, satCap), l0));
    final (lo, hi) = night ? darkL : lightL;
    var l = night
        ? lo + (hi - lo) * (0.25 + 0.55 * ((sl - 10) / 70).clamp(0.0, 1.0))
        : lo + (hi - lo) * (0.35 + 0.55 * ((sl - 10) / 80).clamp(0.0, 1.0));
    l = l.clamp(lo, hi);
    var a = a0, b = b0;
    final c = math.sqrt(a * a + b * b);
    if (c > chromaCap) {
      a *= chromaCap / c;
      b *= chromaCap / c;
    }
    var out = _labToRgb(l, a, b);
    for (var i = 0; i < 16; i++) {
      if (_rgbToHsl(out).$2 <= satCap) break;
      final mean = (out.$1 + out.$2 + out.$3) / 3;
      int mix(int v) => (v * 0.85 + mean * 0.15).round();
      out = (mix(out.$1), mix(out.$2), mix(out.$3));
    }
    return Color.fromARGB(255, out.$1, out.$2, out.$3);
  }

  static (int, int, int) _rgb(Color c) =>
      ((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round());

  static (double, double, double) _rgbToHsl((int, int, int) c) {
    final r = c.$1 / 255, g = c.$2 / 255, b = c.$3 / 255;
    final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
    final l = (mx + mn) / 2;
    if (mx == mn) return (0, 0, l);
    final d = mx - mn;
    final s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    double h;
    if (mx == r) {
      h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
    } else if (mx == g) {
      h = ((b - r) / d + 2) / 6;
    } else {
      h = ((r - g) / d + 4) / 6;
    }
    return (h, s, l);
  }

  static (int, int, int) _hslToRgb(double h, double s, double l) {
    if (s == 0) {
      final v = (l * 255).round();
      return (v, v, v);
    }
    double hue(double p, double q, double t) {
      if (t < 0) t += 1;
      if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    }

    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    return (
      (hue(p, q, h + 1 / 3) * 255).round(),
      (hue(p, q, h) * 255).round(),
      (hue(p, q, h - 1 / 3) * 255).round(),
    );
  }

  static const _wx = 0.95047, _wz = 1.08883;

  static (double, double, double) _rgbToLab((int, int, int) c) {
    double lin(int v) {
      final x = v / 255;
      return x <= 0.04045
          ? x / 12.92
          : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = lin(c.$1), g = lin(c.$2), b = lin(c.$3);
    final x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375;
    final y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750;
    final z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041;
    double f(double t) =>
        t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
    final fx = f(x / _wx), fy = f(y), fz = f(z / _wz);
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
  }

  static (int, int, int) _labToRgb(double l, double a, double b) {
    final fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - b / 200;
    double inv(double t) {
      final t3 = t * t * t;
      return t3 > 0.008856 ? t3 : (t - 16 / 116) / 7.787;
    }

    final x = inv(fx) * _wx, y = inv(fy), z = inv(fz) * _wz;
    int enc(double c) {
      final v = c <= 0.0031308
          ? 12.92 * c
          : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
      return (v.clamp(0.0, 1.0) * 255).round();
    }

    return (
      enc(x * 3.2404542 + y * -1.5371385 + z * -0.4985314),
      enc(x * -0.9692660 + y * 1.8760108 + z * 0.0415560),
      enc(x * 0.0556434 + y * -0.2040259 + z * 1.0572252),
    );
  }
}

class CoverArt {
  const CoverArt({
    required this.url,
    required this.spot,
    required this.bright,
    required this.glow,
    this.dominant,
    this.palette = const [],
  });

  final String url;

  final ui.Image spot, bright;

  // A more heavily blurred copy for the halo under the Focus cover; its
  // opaque body is FocusGeo.haloBody of the image and the edge is feathered.
  final ui.Image glow;
  final Color? dominant;
  final List<Color> palette;

  static const source = 64;

  static const sigma = 4.0;
  static const out = 256;
  static const brightGain = 1.08;

  static Uint8List blur(Uint8List rgba, int size, {double sigma = sigma}) {
    final r = (sigma * 3).ceil();
    final k = List<double>.generate(
      2 * r + 1,
      (i) => math.exp(-((i - r) * (i - r)) / (2 * sigma * sigma)),
    );
    final sum = k.reduce((a, b) => a + b);
    for (var i = 0; i < k.length; i++) {
      k[i] /= sum;
    }
    final n = size * size;
    final tmp = Float64List(n * 3), res = Float64List(n * 3);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        double a = 0, b = 0, c = 0;
        for (var j = -r; j <= r; j++) {
          final xx = (x + j).clamp(0, size - 1);
          final i = (y * size + xx) * 4;
          final w = k[j + r];
          a += rgba[i] * w;
          b += rgba[i + 1] * w;
          c += rgba[i + 2] * w;
        }
        final o = (y * size + x) * 3;
        tmp[o] = a;
        tmp[o + 1] = b;
        tmp[o + 2] = c;
      }
    }
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        double a = 0, b = 0, c = 0;
        for (var j = -r; j <= r; j++) {
          final yy = (y + j).clamp(0, size - 1);
          final o = (yy * size + x) * 3;
          final w = k[j + r];
          a += tmp[o] * w;
          b += tmp[o + 1] * w;
          c += tmp[o + 2] * w;
        }
        final o = (y * size + x) * 3;
        res[o] = a;
        res[o + 1] = b;
        res[o + 2] = c;
      }
    }
    final px = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      px[i * 4] = res[i * 3].round().clamp(0, 255);
      px[i * 4 + 1] = res[i * 3 + 1].round().clamp(0, 255);
      px[i * 4 + 2] = res[i * 3 + 2].round().clamp(0, 255);
      px[i * 4 + 3] = 255;
    }
    return px;
  }

  static const inset = 0.06, corner = 0.12, featherSigma = 0.025;
  static const glowSigma = 7.0, glowOut = 128, glowFeather = 0.07;

  // Pixel work runs in a background isolate, so a track change never costs a
  // frame on the UI thread; only the GPU upload happens here.
  static Future<CoverArt> build(String url, Uint8List rgba64) async {
    final (blurred, wide, dominant, palette) = await Isolate.run(() {
      final d = CoverColor.dominant(rgba64, source);
      final p = CoverColor.palette(rgba64, source);
      return (
        blur(rgba64, source),
        blur(rgba64, source, sigma: glowSigma),
        d?.toARGB32(),
        [for (final c in p) c.toARGB32()],
      );
    });
    Future<ui.Image> upload(Uint8List px) {
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(px, source, source, ui.PixelFormat.rgba8888, done.complete);
      return done.future;
    }

    final img = await upload(blurred);
    final spot = await _feathered(img, 1);
    final bright = await _feathered(img, brightGain);
    img.dispose();
    final wideImg = await upload(wide);
    final glow = await _feathered(
      wideImg,
      1,
      out: glowOut,
      inset: (1 - FocusGeo.haloBody) / 2,
      feather: glowFeather,
    );
    wideImg.dispose();
    return CoverArt(
      url: url,
      spot: spot,
      bright: bright,
      glow: glow,
      dominant: dominant == null ? null : Color(dominant),
      palette: [for (final v in palette) Color(v)],
    );
  }

  static Future<ui.Image> _feathered(
    ui.Image small,
    double gain, {
    int out = out,
    double inset = inset,
    double feather = featherSigma,
  }) {
    final s = out * 1.0;
    final rect = Rect.fromLTWH(0, 0, s, s);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, rect)..saveLayer(rect, Paint());
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (gain != 1) {
      paint.colorFilter = ColorFilter.matrix(<double>[
        gain, 0, 0, 0, 0,
        0, gain, 0, 0, 0,
        0, 0, gain, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    }
    canvas.drawImageRect(
      small,
      Rect.fromLTWH(0, 0, small.width.toDouble(), small.height.toDouble()),
      rect,
      paint,
    );
    final inner = rect.deflate(s * inset);
    canvas
      // A separate dstIn layer also clears pixels outside the rounded square.
      ..saveLayer(rect, Paint()..blendMode = BlendMode.dstIn)
      ..drawRRect(
        RRect.fromRectAndRadius(inner, Radius.circular(inner.width * corner)),
        Paint()
          ..color = Colors.white
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * feather),
      )
      ..restore()
      ..restore();
    return rec.endRecording().toImage(out, out);
  }
}

class WaveformCache {
  WaveformCache(this._fetch, {this.capacity = 48});

  final Future<String?> Function(Uri url) _fetch;
  final int capacity;
  final _cache = <String, Future<List<double>?>>{};

  static Uri? jsonUri(String? waveformUrl) {
    if (waveformUrl == null) return null;
    final u = Uri.tryParse(waveformUrl);
    if (u == null ||
        u.scheme != 'https' ||
        !(u.host == 'sndcdn.com' || u.host.endsWith('.sndcdn.com'))) {
      return null;
    }
    final path = u.path.endsWith('.png')
        ? '${u.path.substring(0, u.path.length - 4)}.json'
        : u.path;
    return path.endsWith('.json')
        ? Uri(scheme: 'https', host: u.host, path: path)
        : null;
  }

  static List<double>? parse(String? body) {
    if (body == null) return null;
    try {
      final j = jsonDecode(body);
      final raw = j is Map ? j['samples'] : null;
      if (raw is! List || raw.length < 64) return null;
      final s = [for (final v in raw) v is num ? v.toDouble() : 0.0];
      final mx = s.reduce(math.max);
      if (mx <= 0) return null;
      return [for (final v in s) v / mx];
    } catch (_) {
      return null;
    }
  }

  Future<List<double>?> load(String? waveformUrl) {
    final uri = jsonUri(waveformUrl);
    if (uri == null) return Future.value(null);
    final key = uri.toString();
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit;
    if (_cache.length >= capacity) _cache.remove(_cache.keys.first);
    return _cache[key] = _fetch(uri).then(parse, onError: (_) => null);
  }
}

typedef Beat = ({double ms, double intensity});

class BeatDetector {
  BeatDetector(this.samples, this.durationMs)
    : beats = detect(samples, durationMs);

  final List<double> samples;
  final int durationMs;
  final List<Beat> beats;

  static const floor = 0.12;
  static const minGapMs = 250.0;

  static const minRise = 0.025;
  static const fillIntensity = 0.35;
  static const loud = 0.55;

  static const lateMs = 250.0;

  int get detected => beats.where((b) => b.intensity != fillIntensity).length;

  // Rise peaks above mean + 0.4σ (±2 s); loud beatless stretches get fill pulses.
  static List<Beat> detect(List<double> raw, int durationMs) {
    final n = raw.length;
    if (n < 8 || durationMs <= 0) return const [];
    final mx = raw.reduce(math.max);
    if (mx <= 0) return const [];
    final s = [for (final v in raw) v / mx];
    final msPer = durationMs / n;
    final rise = List<double>.filled(n, 0);
    for (var i = 2; i < n; i++) {
      rise[i] = math.max(0, s[i] - math.min(s[i - 1], s[i - 2]));
    }
    final w = math.max(4, (2000 / msPer).round());
    final sum = <double>[0], sq = <double>[0];
    for (final v in rise) {
      sum.add(sum.last + v);
      sq.add(sq.last + v * v);
    }
    final found = <Beat>[];
    var last = double.negativeInfinity;
    for (var i = 2; i < n - 1; i++) {
      final a = math.max(0, i - w), b = math.min(n, i + w + 1);
      final mean = (sum[b] - sum[a]) / (b - a);
      final sd = math.sqrt(
        math.max(0, (sq[b] - sq[a]) / (b - a) - mean * mean),
      );
      final thr = math.max(minRise, mean + 0.4 * sd);
      final t = i * msPer;
      final o = rise[i];
      if (s[i] >= floor &&
          o > thr &&
          o >= rise[i - 1] &&
          o >= rise[i + 1] &&
          t - last >= minGapMs) {
        final k = (0.5 + 0.5 * (o - thr) / thr).clamp(0.45, 1.2);
        found.add((ms: t, intensity: k * math.min(1.0, 0.4 + s[i])));
        last = t;
      }
    }
    final gaps = [
      for (var i = 1; i < found.length; i++)
        if (found[i].ms - found[i - 1].ms < 900) found[i].ms - found[i - 1].ms,
    ]..sort();
    final step = gaps.length >= 8
        ? gaps[gaps.length ~/ 2].clamp(400.0, 700.0)
        : 500.0;
    final level = <double>[0];
    for (final v in s) {
      level.add(level.last + v);
    }
    final l = math.max(1, (1000 / msPer).round());
    final fill = <Beat>[];
    final marks = [double.negativeInfinity, for (final b in found) b.ms];
    for (var m = 0; m < marks.length; m++) {
      final end = m + 1 < marks.length ? marks[m + 1] : durationMs.toDouble();
      for (
        var t = math.max(marks[m] + step, 0.0);
        t < end - step * 0.6;
        t += step
      ) {
        final i = math.min(n - 1, t ~/ msPer);
        final a = math.max(0, i - l), b = math.min(n, i + l + 1);
        if ((level[b] - level[a]) / (b - a) < loud) continue;
        var j = i;
        for (final q in [i - 1, i + 1]) {
          if (q >= 0 && q < n && s[q] > s[j]) j = q;
        }
        fill.add((ms: j * msPer, intensity: fillIntensity));
      }
    }
    final all = [...found, ...fill]..sort((x, y) => x.ms.compareTo(y.ms));
    final out = <Beat>[];
    for (var i = 0; i < all.length; i++) {
      final b = all[i];
      if (b.intensity == fillIntensity) {
        final next = i + 1 < all.length ? all[i + 1].ms : double.infinity;
        if ((out.isNotEmpty && b.ms - out.last.ms < minGapMs) ||
            next - b.ms < minGapMs) {
          continue;
        }
      }
      out.add(b);
    }
    return out;
  }

  int _next = 0;
  double? _lastPos;

  double? step(double posMs) {
    final prev = _lastPos;
    _lastPos = posMs;
    if (prev == null || (posMs - prev).abs() > 1000) {
      _next = 0;
      while (_next < beats.length && beats[_next].ms <= posMs) {
        _next++;
      }
      return null;
    }
    double? hit;
    while (_next < beats.length && beats[_next].ms <= posMs) {
      if (posMs - beats[_next].ms <= lateMs) hit = beats[_next].intensity;
      _next++;
    }
    return hit;
  }
}

@immutable
class PulseFrame {
  const PulseFrame(this.scale, this.bright);

  static const rest = PulseFrame(1, 0);

  final double scale, bright;

  bool get isRest => scale == 1 && bright == 0;

  @override
  bool operator ==(Object other) =>
      other is PulseFrame && other.scale == scale && other.bright == bright;

  @override
  int get hashCode => Object.hash(scale, bright);

  @override
  String toString() => 'PulseFrame($scale, +$bright)';
}

class PulseEnvelope {
  static const riseMs = 80.0, decayMs = 300.0, releaseMs = 400.0;
  static const scaleMax = 0.06, brightMax = 0.08;

  static double ease(double t) {
    final u = 1 - t.clamp(0.0, 1.0);
    return 1 - u * u * u;
  }

  static PulseFrame beatAt(double t, {double intensity = 1}) {
    final env = t < 0
        ? 0.0
        : t < riseMs
        ? ease(t / riseMs)
        : t < riseMs + decayMs
        ? 1 - ease((t - riseMs) / decayMs)
        : 0.0;
    return PulseFrame(
      1 + math.min(scaleMax, 0.04 * intensity) * env,
      math.min(brightMax, 0.07 * intensity) * env,
    );
  }

  bool _release = false;
  double _start = 0;
  double _fromS = 0, _fromB = 0, _peakS = 0, _peakB = 0;
  bool _idle = true;

  PulseFrame at(double now) {
    if (_idle) return PulseFrame.rest;
    final t = now - _start;
    double s, b;
    if (_release) {
      final k = 1 - ease(t / releaseMs);
      s = _fromS * k;
      b = _fromB * k;
      if (t >= releaseMs) _idle = true;
    } else if (t < riseMs) {
      final k = ease(t / riseMs);
      s = _fromS + (_peakS - _fromS) * k;
      b = _fromB + (_peakB - _fromB) * k;
    } else if (t < riseMs + decayMs) {
      final k = 1 - ease((t - riseMs) / decayMs);
      s = _peakS * k;
      b = _peakB * k;
    } else {
      _idle = true;
      return PulseFrame.rest;
    }
    if (_idle) return PulseFrame.rest;
    return PulseFrame(1 + s, b);
  }

  bool isRest(double now) => at(now).isRest;

  void beat(double now, double intensity) {
    final cur = at(now);
    _fromS = cur.scale - 1;
    _fromB = cur.bright;
    _peakS = math.min(scaleMax, 0.04 * intensity);
    _peakB = math.min(brightMax, 0.07 * intensity);
    _start = now;
    _release = false;
    _idle = false;
  }

  void release(double now) {
    if (_idle || _release) return;
    final cur = at(now);
    if (_idle) return;
    _fromS = cur.scale - 1;
    _fromB = cur.bright;
    _start = now;
    _release = true;
  }
}

class CoverScene {
  CoverScene({required this.player, this.waveforms, this.waveformUrlOf}) {
    player.addListener(_sync);
    _sync();
  }

  final PlayerController player;
  final WaveformCache? waveforms;

  final Future<String?> Function(Track track)? waveformUrlOf;
  final art = ValueNotifier<CoverArt?>(null);
  final wave = ValueNotifier<List<double>?>(null);
  final pulse = ValueNotifier<PulseFrame>(PulseFrame.rest);

  final _done = <String, CoverArt>{};
  String? _artUrl;
  String? _warmUrl;
  int? _waveId;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageStream? _warmStream;
  ImageStreamListener? _warmListener;
  bool _disposed = false;

  void _sync() {
    final t = player.current;
    final u = t?.artworkUrl;
    final artUrl = u == null || isDefaultArt(u) ? null : u;
    if (artUrl != _artUrl) {
      _artUrl = artUrl;
      _loadArt(artUrl);
    }
    if (t?.id != _waveId) {
      _waveId = t?.id;
      wave.value = null;
      if (t != null && waveforms != null) unawaited(_loadWave(t));
      _warm(_nextArtUrl());
    }
  }

  String? _nextArtUrl() {
    final next = player.upNext;
    if (next.isEmpty) return null;
    final u = next.first.artworkUrl;
    return u == null || isDefaultArt(u) ? null : u;
  }

  // Builds the next track's art ahead of time, so the backdrop and the cover
  // halo have their colours ready the moment the track changes.
  void _warm(String? url) {
    if (url == _warmUrl) return;
    _dropWarm();
    _warmUrl = url;
    if (url == null || url == _artUrl || _done.containsKey(url)) return;
    final base = ArtCache.override?.call(url) ?? CachedArt(url);
    final stream = ResizeImage(
      base,
      width: CoverArt.source,
      height: CoverArt.source,
    ).resolve(ImageConfiguration.empty);
    _warmListener = ImageStreamListener((info, _) async {
      _dropWarm();
      final data = await info.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = info.image.width, h = info.image.height;
      info.dispose();
      if (_disposed || data == null) return;
      if (w != CoverArt.source || h != CoverArt.source) return;
      final result = await CoverArt.build(url, data.buffer.asUint8List());
      if (!_disposed) _remember(url, result);
    }, onError: (_, _) {});
    _warmStream = stream..addListener(_warmListener!);
  }

  void _dropWarm() {
    if (_warmListener != null) _warmStream?.removeListener(_warmListener!);
    _warmStream = null;
    _warmListener = null;
  }

  void _remember(String url, CoverArt art) {
    if (_done.length >= 8) _done.remove(_done.keys.first);
    _done[url] = art;
  }

  Future<void> _loadWave(Track t) async {
    var url = t.waveformUrl;
    if (url == null) {
      try {
        url = await waveformUrlOf?.call(t);
      } catch (_) {}
    }
    if (_disposed || _waveId != t.id) return;
    final s = await waveforms!.load(url);
    if (_disposed || _waveId != t.id) return;
    wave.value = s;
    DiagLog.write(
      'pulse: track ${t.id} waveform '
      '${url == null
          ? 'no url'
          : s == null
          ? 'failed'
          : '${s.length} samples'}'
      '${t.waveformUrl == null && url != null ? ' (url looked up)' : ''}',
    );
  }

  void _loadArt(String? url) {
    _stopStream();
    if (url == null) {
      art.value = null;
      return;
    }
    final hit = _done.remove(url);
    if (hit != null) {
      _done[url] = hit;
      art.value = hit;
      return;
    }
    final base = ArtCache.override?.call(url) ?? CachedArt(url);
    final stream = ResizeImage(
      base,
      width: CoverArt.source,
      height: CoverArt.source,
    ).resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener(
      (info, _) async {
        final data = await info.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final w = info.image.width, h = info.image.height;
        info.dispose();
        if (_disposed || _artUrl != url || data == null) return;
        if (w != CoverArt.source || h != CoverArt.source) return;
        final result = await CoverArt.build(url, data.buffer.asUint8List());
        if (_disposed) return;
        _remember(url, result);
        if (_artUrl == url) art.value = result;
      },
      onError: (_, _) {
        if (_artUrl == url) art.value = null;
      },
    );
    _stream = stream..addListener(_listener!);
  }

  void _stopStream() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  void dispose() {
    _disposed = true;
    player.removeListener(_sync);
    _stopStream();
    _dropWarm();
    art.dispose();
    wave.dispose();
    pulse.dispose();
  }
}

class CoverSceneHost extends StatefulWidget {
  const CoverSceneHost({super.key, required this.scene, required this.child});

  final CoverScene scene;
  final Widget child;

  @override
  State<CoverSceneHost> createState() => _CoverSceneHostState();
}

class _CoverSceneHostState extends State<CoverSceneHost>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _env = PulseEnvelope();
  AppServices? _app;
  BeatDetector? _beats;
  bool _reduce = false;
  double _now = 0;
  double _pos = 0, _posAt = 0;

  CoverScene get _scene => widget.scene;

  @override
  void initState() {
    super.initState();
    _scene.wave.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final app = AppScope.of(context);
    if (app != _app) {
      _unlisten();
      _app = app;
      app.player.addListener(_sync);
      app.player.position.addListener(_onPosition);
      app.window.active.addListener(_sync);
      app.pulse.addListener(_sync);
    }
    _sync();
  }

  @override
  void didUpdateWidget(CoverSceneHost old) {
    super.didUpdateWidget(old);
    if (old.scene != widget.scene) {
      old.scene.wave.removeListener(_sync);
      widget.scene.wave.addListener(_sync);
      _sync();
    }
  }

  void _unlisten() {
    final a = _app;
    if (a == null) return;
    a.player.removeListener(_sync);
    a.player.position.removeListener(_onPosition);
    a.window.active.removeListener(_sync);
    a.pulse.removeListener(_sync);
  }

  bool get _want {
    final a = _app;
    return a != null &&
        a.pulse.value &&
        !_reduce &&
        a.window.active.value &&
        a.player.playing &&
        _beats != null;
  }

  void _onPosition() {
    _pos = _app!.player.position.value.inMilliseconds.toDouble();
    _posAt = _now;
  }

  void _sync() {
    final a = _app;
    if (a == null) return;
    final wave = _scene.wave.value;
    final dur = a.player.current?.durationMs ?? 0;
    if (wave == null) {
      _beats = null;
    } else if (_beats?.samples != wave || _beats?.durationMs != dur) {
      final b = _beats = BeatDetector(wave, dur);
      final min = dur / 60000;
      DiagLog.write(
        'pulse: track ${a.player.current?.id} ${wave.length} samples, '
        '${b.beats.length} beats (${b.detected} detected), '
        '${min > 0 ? (b.beats.length / min).round() : 0}/min',
      );
    }
    _logGate(a);
    if (_want) {
      if (!_ticker.isActive) {
        _now = 0;
        _onPosition();
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _env.release(_now);
    }
  }

  String? _gate;

  void _logGate(AppServices a) {
    final g =
        'pulse=${a.pulse.value} reduceMotion=$_reduce '
        'focused=${a.window.active.value} playing=${a.player.playing} '
        'beats=${_beats != null}';
    if (g == _gate) return;
    _gate = g;
    DiagLog.write('pulse gate ${_want ? 'on' : 'off'}: $g');
  }

  void _tick(Duration elapsed) {
    _now = elapsed.inMicroseconds / 1000;
    if (_want) {
      final est = _pos + math.min(_now - _posAt, 500.0);
      final hit = _beats!.step(est);
      if (hit != null && hit > 0) _env.beat(_now, hit);
    } else {
      _env.release(_now);
    }
    final f = _env.at(_now);
    _scene.pulse.value = f;
    if (!_want && f.isRest) _ticker.stop();
  }

  @override
  void dispose() {
    _unlisten();
    _scene.wave.removeListener(_sync);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CoverSceneScope(scene: widget.scene, child: widget.child);
}

class CoverSceneScope extends InheritedWidget {
  const CoverSceneScope({super.key, required this.scene, required super.child});

  final CoverScene scene;

  static CoverScene? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CoverSceneScope>()?.scene;

  @override
  bool updateShouldNotify(CoverSceneScope old) => old.scene != scene;
}

Widget _crossfade(Widget child) => AnimatedSwitcher(
  duration: const Duration(milliseconds: 600),
  switchInCurve: Curves.linear,
  // The outgoing layer stays opaque until removed, so nothing shows through mid-fade.
  switchOutCurve: const Threshold(0),
  child: child,
);

class CoverBackground extends StatelessWidget {
  const CoverBackground({super.key, this.scene, this.focus, this.glow});

  final CoverScene? scene;

  // Focus mode progress, 0..1: the blurred spot zooms by FocusGeo.zoom.
  final Animation<double>? focus;

  // Focus backdrop progress, 0..1 over 400 ms: the square spot dissolves and
  // the palette glow takes the whole window.
  final Animation<double>? glow;

  static const coverShare = 0.70;

  static const nightGain = 0.58, lightGain = 0.68;

  static List<double> tone(bool night) {
    final k = night ? nightGain : lightGain;
    final o = night ? 0.0 : 255 * (1 - k);
    return <double>[
      k, 0, 0, 0, o,
      0, k, 0, 0, o,
      0, 0, k, 0, o,
      0, 0, 0, 1, 0,
    ];
  }

  static Rect coverRect(Size size) {
    final top = Dp.topBar, h = size.height - Dp.topBar - Dp.contentBottom;
    final side = math.min(h * coverShare, size.width * 0.9);
    return Rect.fromCenter(
      center: Offset(size.width / 2, top + h / 2),
      width: side,
      height: side,
    );
  }

  static final _zoom = Tween<double>(begin: 1, end: 1 + FocusGeo.zoom);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = scene;
    if (s == null) return SmokeBackground(active: app.window.active);
    final c = AgColors.of(context);
    final f = focus ?? kAlwaysDismissedAnimation;
    final g = glow ?? kAlwaysDismissedAnimation;
    return ListenableBuilder(
      listenable: Listenable.merge([app.tint, app.focus, s.art]),
      builder: (context, _) {
        final art = app.tint.value || app.focus.isOn ? s.art.value : null;
        final d = art?.dominant;
        final Widget base;
        if (art == null) {
          base = _crossfade(
            SmokeBackground(
              key: const ValueKey('smoke'),
              active: app.window.active,
            ),
          );
        } else {
          final tint = d == null
              ? c.washBase
              : CoverColor.windowTint(d, night: c.isNight);
          base = _crossfade(
            Stack(
              key: const ValueKey('cover'),
              fit: StackFit.expand,
              children: [
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: tint),
                  // Covered by the backdrop in Focus, so it jumps there instead
                  // of repainting the full-window wash for 600 ms.
                  duration: app.focus.isOn
                      ? Duration.zero
                      : const Duration(milliseconds: 600),
                  builder: (context, color, _) => RepaintBoundary(
                    child: CustomPaint(
                      painter: WashPainter(
                        tint: color ?? tint,
                        base: c.washBase,
                        dot: c.washDot,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, box) => Stack(
                    children: [
                      Positioned.fromRect(
                        rect: coverRect(box.biggest),
                        child: FadeTransition(
                          opacity: ReverseAnimation(g),
                          child: ScaleTransition(
                            scale: f.drive(_zoom),
                            child: RepaintBoundary(
                              child: ColorFiltered(
                                colorFilter: ColorFilter.matrix(tone(c.isNight)),
                                child: ValueListenableBuilder<CoverArt?>(
                                  valueListenable: s.art,
                                  builder: (context, a, _) => _crossfade(
                                    a == null
                                        ? const SizedBox.expand()
                                        : _Spot(
                                            key: ValueKey(a.url),
                                            art: a,
                                            pulse: s.pulse,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            base,
            AnimatedBuilder(
              animation: g,
              builder: (context, child) =>
                  g.value <= 0 ? const SizedBox.shrink() : child!,
              child: FocusBackdrop(art: s.art.value, visible: g, pulse: s.pulse),
            ),
          ],
        );
      },
    );
  }
}

class WashPainter extends CustomPainter {
  WashPainter({required this.tint, required this.base, required this.dot});

  final Color tint, base, dot;

  static double mixAt(double r) {
    final t = ((r - 0.15) / 1.05).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = Offset(size.width * 0.50, size.height * 0.42);
    final rx = size.width * 0.55, ry = size.height * 0.62;
    const steps = 24;
    final stops = [for (var i = 0; i <= steps; i++) i / steps];
    final m = Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(1, ry / rx, 1, 1)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          rx * 1.2,
          [for (final t in stops) Color.lerp(tint, base, mixAt(t * 1.2))!],
          stops,
          TileMode.clamp,
          m.storage,
        ),
    );
    DotGridPainter(dot, dot: 1.3).paint(canvas, size);
  }

  @override
  bool shouldRepaint(WashPainter old) =>
      old.tint != tint || old.base != base || old.dot != dot;
}

class _Spot extends StatelessWidget {
  const _Spot({super.key, required this.art, required this.pulse});

  final CoverArt art;
  final ValueListenable<PulseFrame> pulse;

  @override
  Widget build(BuildContext context) {
    Widget img(ui.Image i) => RawImage(
      image: i,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
    return ValueListenableBuilder<PulseFrame>(
      valueListenable: pulse,
      builder: (context, f, _) => Transform.scale(
        scale: f.scale,
        child: Stack(
          fit: StackFit.expand,
          children: [
            img(art.spot),
            if (f.bright > 0)
              Opacity(
                opacity: (f.bright / (CoverArt.brightGain - 1)).clamp(0.0, 1.0),
                child: img(art.bright),
              ),
          ],
        ),
      ),
    );
  }
}
