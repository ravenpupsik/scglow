import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/app/legacy_data.dart';
import 'package:scglow/core/diag_log.dart';

void main() {
  late Directory roaming;

  setUp(() {
    roaming = Directory.systemTemp.createTempSync('scglow_roaming');
    DiagLog.pathOverride = '${roaming.path}/log.txt';
  });

  tearDown(() {
    DiagLog.pathOverride = null;
    roaming.deleteSync(recursive: true);
  });

  File at(String path) => File('${roaming.path}/$path');

  void seedLegacy(String vendor) {
    at('$vendor/Afterglow/shared_preferences.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"flutter.pulse_to_beat":false}');
    at('$vendor/Afterglow/flutter_secure_storage.dat')
        .writeAsBytesSync([1, 2, 3, 4]);
    at('$vendor/Afterglow/data/player_v1.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"queue":[]}');
    at('$vendor/Afterglow/art/a.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([9]);
  }

  test('copies the earlier build data once and leaves it in place', () async {
    seedLegacy('legacy.vendor');
    final target = Directory('${roaming.path}/scglow');
    expect(await LegacyData.migrate(target, roaming: roaming), 4);
    expect(
      at('scglow/shared_preferences.json').readAsStringSync(),
      '{"flutter.pulse_to_beat":false}',
    );
    expect(at('scglow/flutter_secure_storage.dat').readAsBytesSync(), [
      1,
      2,
      3,
      4,
    ]);
    expect(at('scglow/data/player_v1.json').existsSync(), isTrue);
    expect(at('scglow/art/a.jpg').existsSync(), isTrue);
    expect(
      at('legacy.vendor/Afterglow/flutter_secure_storage.dat').existsSync(),
      isTrue,
    );
    expect(at('scglow/${LegacyData.marker}').existsSync(), isTrue);

    at('legacy.vendor/Afterglow/data/user.json').writeAsStringSync('{}');
    expect(await LegacyData.migrate(target, roaming: roaming), 0);
    expect(at('scglow/data/user.json').existsSync(), isFalse);
  });

  test('never overwrites data the new build already has', () async {
    seedLegacy('legacy.vendor');
    at('scglow/shared_preferences.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"own":true}');
    final target = Directory('${roaming.path}/scglow');
    expect(await LegacyData.migrate(target, roaming: roaming), 0);
    expect(
      at('scglow/shared_preferences.json').readAsStringSync(),
      '{"own":true}',
    );
    expect(at('scglow/flutter_secure_storage.dat').existsSync(), isFalse);
  });

  test('fresh install: nothing to copy, marker written', () async {
    final target = Directory('${roaming.path}/scglow');
    expect(await LegacyData.migrate(target, roaming: roaming), 0);
    expect(at('scglow/${LegacyData.marker}').existsSync(), isTrue);
  });
}
