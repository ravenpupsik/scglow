import 'dart:io';

import '../core/diag_log.dart';

class LegacyData {
  LegacyData._();

  static const products = ['Afterglow', 'scdesk'];
  static const marker = '.migrated';
  static const _signs = [
    'flutter_secure_storage.dat',
    'shared_preferences.json',
  ];

  // Copies a pre-rename build's data folder (<roaming>\<vendor>\Afterglow) once; the old one stays.
  static Future<int> migrate(Directory target, {Directory? roaming}) async {
    try {
      final done = File(_join(target.path, marker));
      if (done.existsSync()) return 0;
      target.createSync(recursive: true);
      if (_signs.any((f) => File(_join(target.path, f)).existsSync())) {
        done.writeAsStringSync('');
        return 0;
      }
      final root = roaming ?? target.parent;
      final source = _find(root, target);
      var copied = 0;
      if (source != null) copied = _copy(source, target);
      done.writeAsStringSync('');
      DiagLog.write(
        source == null
            ? 'migration: no earlier data'
            : 'migration: copied $copied files from the earlier build',
      );
      return copied;
    } catch (e) {
      DiagLog.write('migration failed: ${e.runtimeType}');
      return 0;
    }
  }

  static Directory? _find(Directory root, Directory target) {
    if (!root.existsSync()) return null;
    final self = target.absolute.path.toLowerCase();
    for (final product in products) {
      final candidates = <Directory>[
        Directory(_join(root.path, product)),
        for (final vendor in root.listSync().whereType<Directory>())
          Directory(_join(vendor.path, product)),
      ];
      Directory? best;
      DateTime? newest;
      for (final d in candidates) {
        if (d.absolute.path.toLowerCase() == self) continue;
        for (final f in _signs) {
          final file = File(_join(d.path, f));
          if (!file.existsSync()) continue;
          final m = file.lastModifiedSync();
          if (newest == null || m.isAfter(newest)) {
            newest = m;
            best = d;
          }
        }
      }
      if (best != null) return best;
    }
    return null;
  }

  // Per-entry failures are skipped: browser cache files can vanish mid-copy.
  static int _copy(Directory from, Directory to) {
    var n = 0;
    List<FileSystemEntity> entries;
    try {
      entries = from.listSync(followLinks: false);
    } catch (_) {
      return 0;
    }
    for (final e in entries) {
      final dest = _join(to.path, e.path.substring(from.path.length + 1));
      if (e is Directory) {
        n += _copy(e, Directory(dest));
      } else if (e is File && !File(dest).existsSync()) {
        try {
          Directory(dest).parent.createSync(recursive: true);
          e.copySync(dest);
          n++;
        } catch (_) {}
      }
    }
    return n;
  }

  static String _join(String a, String b) => '$a${Platform.pathSeparator}$b';
}
