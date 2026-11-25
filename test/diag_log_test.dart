import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/core/diag_log.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('diag');
    DiagLog.pathOverride = '${dir.path}/log.txt';
  });

  tearDown(() {
    DiagLog.pathOverride = null;
    dir.deleteSync(recursive: true);
  });

  test('error writes the message and stack frames, scrubbed', () {
    final stack = StackTrace.fromString(
        '#0 load (package:x/a.dart:1)\n#1 call client_id=abc123 (package:x/b.dart:2)');
    DiagLog.error('zone', StateError('bad OAuth 2-123456-789-abcdefg'), stack);
    final text = File(DiagLog.path).readAsStringSync();
    expect(text, contains('error (zone): Bad state: bad [hidden]'));
    expect(text, contains('    #0 load (package:x/a.dart:1)'));
    expect(text, contains('#1 call [hidden]'));
    expect(text, isNot(contains('abc123')));
    expect(text, isNot(contains('abcdefg')));
  });
}
