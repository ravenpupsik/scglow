import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_services.dart';
import 'app/legacy_data.dart';
import 'app/ui_state.dart';
import 'selftest.dart';
import 'ui/app_root.dart';
import 'ui/theme/tokens.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (args.contains('--selftest')) return runSelfTest();

  if (Platform.isWindows) {
    await LegacyData.migrate(await getApplicationSupportDirectory());
  }
  final prefs = await SharedPreferences.getInstance();
  final mode = ThemeController.read(prefs);
  final platformDark =
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
  final night = mode == ThemeMode.dark || (mode == ThemeMode.system && platformDark);

  final background = night ? AgColors.night.bg : AgColors.light.bg;

  final services = await AppServices.create(prefs);
  try {
    await services.player.restore();
  } catch (_) {}
  runApp(ScglowApp(services: services));
  unawaited(services.window.init(background: background));
  unawaited(services.session.start());
}
