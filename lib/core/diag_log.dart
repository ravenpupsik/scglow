import 'dart:io';

class DiagLog {
  DiagLog._();

  static String? pathOverride;
  static const _maxBytes = 512 * 1024;

  static String get path =>
      pathOverride ??
      '${Directory.systemTemp.path}${Platform.pathSeparator}scglow.log';

  // Logs carry method, path and status only; tokens and client ids are scrubbed.
  static final _secretRe = RegExp(
      r'(OAuth\s+\S+|\b\d-\d{6}-\d{3,}-[A-Za-z0-9]{6,}\b|client_id=[A-Za-z0-9]+|oauth_token=[^&;\s"]+)');

  static String scrub(String text) =>
      text.replaceAll(_secretRe, '[hidden]').replaceAll(RegExp(r'\s+'), ' ');

  static void apiFailure({
    required String method,
    required Uri uri,
    required int status,
    String body = '',
    String via = 'direct',
  }) {
    final excerpt = body.length > 300 ? body.substring(0, 300) : body;
    write('$method ${uri.path} -> $status [$via] ${scrub(excerpt)}');
  }

  static void error(String source, Object error, StackTrace? stack) {
    final frames = (stack?.toString() ?? '')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(40)
        .map((l) => '    ${scrub(l)}')
        .join('\n');
    write('error ($source): ${scrub('$error')}${frames.isEmpty ? '' : '\n$frames'}');
  }

  static void write(String line) {
    try {
      final f = File(path);
      if (f.existsSync() && f.lengthSync() > _maxBytes) {
        f.writeAsStringSync('');
      }
      f.writeAsStringSync('${DateTime.now().toIso8601String()} $line\n',
          mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}
