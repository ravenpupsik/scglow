import 'dart:math' as math;

import 'package:flutter/material.dart';

@immutable
class AgColors extends ThemeExtension<AgColors> {
  const AgColors({
    required this.bg,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.disabled,
    required this.accent,
    required this.barPlayed,
    required this.barRest,
    required this.wordmark,
    required this.focus,
    required this.winLine,
    required this.closeHover,
    required this.closeGlyph,
    required this.glass,
    required this.glassHover,
    required this.glassPressed,
    required this.glassTile,
    required this.rim,
    required this.hairline,
    required this.skeleton,
    required this.headerFill,
    required this.pillFill,
    required this.playCircle,
    required this.playCircleRim,
    required this.dialogFill,
    required this.scrim,
    required this.markFill,
    required this.primaryHover,
    required this.primaryPressed,
    required this.pillShadow,
    required this.menuShadow,
    required this.dialogShadow,
    required this.liftShadow,
    required this.smokeAsset,
    required this.blobAsset,
    required this.isNight,
    required this.artist,
    required this.heartRest,
    required this.playingFill,
    required this.menuFill,
    required this.tabThumb,
    required this.tabThumbRim,
    required this.tabDivider,
    required this.switchTrack,
    required this.switchRim,
    required this.switchKnob,
    required this.switchOn,
    required this.tipFill,
    required this.gridDot,
    required this.hitZone,
    required this.cardShadow,
    required this.dropTop,
    required this.dropMid,
    required this.dropBottom,
    required this.dropHighlight,
    required this.dropRim,
    required this.dropGlyph,
    required this.artTile,
    required this.artNote,
    required this.panelScrim,
    required this.offIcon,
    required this.likedFill,
  });

  final Color bg, ink, ink2, muted, disabled, accent;
  final Color barPlayed, barRest, wordmark, focus, winLine, closeHover, closeGlyph;
  final Color glass, glassHover, glassPressed, glassTile, rim, hairline;
  final Color skeleton, headerFill, pillFill, playCircle, playCircleRim;
  final Color dialogFill, scrim, markFill, primaryHover, primaryPressed;

  final Color pillShadow, menuShadow, dialogShadow, liftShadow;

  final Color artist, heartRest, playingFill, menuFill;
  final Color tabThumb, tabThumbRim, tabDivider;
  final Color switchTrack, switchRim, switchKnob, switchOn;
  final Color tipFill, gridDot, hitZone, cardShadow;

  final Color dropTop, dropMid, dropBottom, dropHighlight, dropRim, dropGlyph;

  final Color artTile, artNote;

  final Color panelScrim, offIcon, likedFill;

  final String smokeAsset;
  final String blobAsset;
  final bool isNight;

  Color get hover => glassHover;

  Color get pressed => glassPressed;

  Color get coverRim => ink.withValues(alpha: 0.5);

  Color get cardGlass =>
      isNight ? const Color.fromARGB(140, 18, 18, 22) : const Color.fromARGB(128, 255, 255, 255);

  // The main-screen wash and the Focus mode base share this dark colour.
  static const nightWash = Color(0xFF121317);

  Color get washBase => isNight ? nightWash : const Color(0xFFE4E4EA);
  Color get washDot =>
      isNight ? const Color.fromARGB(16, 255, 255, 255) : const Color.fromARGB(18, 26, 26, 30);

  static double lstar(Color c) {
    double lin(double v) =>
        v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    final y = 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
    return y > 0.008856 ? 116 * math.pow(y, 1 / 3).toDouble() - 16 : 903.3 * y;
  }

  List<BoxShadow> get pillShadows => [
    BoxShadow(color: pillShadow, blurRadius: 16, offset: const Offset(0, 3)),
  ];
  List<BoxShadow> get cardShadows => [
    BoxShadow(color: cardShadow, blurRadius: 16, offset: const Offset(0, 3)),
  ];
  List<BoxShadow> get menuShadows => [
    BoxShadow(color: menuShadow, blurRadius: 12, offset: const Offset(0, 3)),
  ];
  List<BoxShadow> get dialogShadows => [
    BoxShadow(color: dialogShadow, blurRadius: 12, offset: const Offset(0, 3)),
  ];
  List<BoxShadow> get liftShadows => [
    BoxShadow(color: liftShadow, blurRadius: 12, offset: const Offset(0, 4)),
  ];

  BoxDecoration card({Color? fill, double radius = Dp.rCard}) => BoxDecoration(
    color: fill ?? glass,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: rim),
  );

  BoxDecoration tile({double radius = Dp.rButton}) => card(fill: glassTile, radius: radius);

  static const light = AgColors(
    bg: Color(0xFFE4E4EA),
    ink: Color(0xFF1A1A1E),
    ink2: Color(0xFF4A4A52),
    artist: Color(0xFF38383E),
    muted: Color(0xFF6A6A72),
    disabled: Color(0xFF7A7A82),
    accent: Color(0xFFD71921),
    barPlayed: Color(0xFF1A1A1E),
    barRest: Color.fromRGBO(26, 26, 30, 0.20),
    wordmark: Color(0xFF3A3A42),
    focus: Color(0xFF1A1A1E),
    winLine: Color(0xFFC4C4CA),
    closeHover: Color(0xFFC42B1C),
    closeGlyph: Color(0xFFFFFFFF),
    glass: Color.fromARGB(186, 255, 255, 255),
    glassHover: Color.fromRGBO(26, 26, 30, 0.06),
    glassPressed: Color.fromRGBO(26, 26, 30, 0.10),
    glassTile: Color.fromARGB(210, 255, 255, 255),
    rim: Color.fromARGB(23, 26, 26, 30),
    hairline: Color.fromARGB(23, 26, 26, 30),
    skeleton: Color.fromRGBO(26, 26, 30, 0.12),
    artTile: Color(0xFFE6E6EB),
    artNote: Color(0xFF8A8A92),
    headerFill: Color.fromRGBO(255, 255, 255, 0.90),
    pillFill: Color.fromARGB(217, 255, 255, 255),
    playCircle: Color.fromRGBO(255, 255, 255, 0.78),
    playCircleRim: Color.fromRGBO(26, 26, 30, 0.14),
    dialogFill: Color.fromRGBO(255, 255, 255, 0.96),
    scrim: Color.fromRGBO(20, 20, 24, 0.20),
    markFill: Color(0xFFF5F5F7),
    primaryHover: Color(0xFF34343A),
    primaryPressed: Color(0xFF0E0E10),
    pillShadow: Color.fromRGBO(0, 0, 0, 0.16),
    menuShadow: Color.fromRGBO(0, 0, 0, 0.16),
    dialogShadow: Color.fromRGBO(0, 0, 0, 0.20),
    liftShadow: Color.fromRGBO(0, 0, 0, 0.22),
    cardShadow: Color.fromRGBO(0, 0, 0, 0.10),
    heartRest: Color.fromRGBO(26, 26, 30, 0.40),
    playingFill: Color.fromRGBO(26, 26, 30, 0.07),
    menuFill: Color.fromRGBO(255, 255, 255, 0.96),
    tabThumb: Color.fromRGBO(26, 26, 30, 0.14),
    tabThumbRim: Color.fromRGBO(26, 26, 30, 0.20),
    tabDivider: Color.fromRGBO(26, 26, 30, 0.16),
    switchTrack: Color.fromRGBO(26, 26, 30, 0.07),
    switchRim: Color.fromRGBO(26, 26, 30, 0.16),
    switchKnob: Color(0xFFFFFFFF),
    switchOn: Color(0xFF1A1A1E),
    tipFill: Color(0xFFFAFAFC),
    gridDot: Color.fromRGBO(26, 26, 30, 0.07),
    hitZone: Color.fromRGBO(26, 26, 30, 0.04),
    dropTop: Color.fromRGBO(240, 50, 58, 1),
    dropMid: Color(0xFFE5232B),
    dropBottom: Color.fromRGBO(176, 20, 28, 1),
    dropHighlight: Color.fromRGBO(255, 255, 255, 0.31),
    dropRim: Color.fromRGBO(255, 255, 255, 0.22),
    dropGlyph: Color(0xFFFFFFFF),
    panelScrim: Color.fromARGB(40, 0, 0, 0),
    offIcon: Color.fromARGB(115, 26, 26, 30),
    likedFill: Color.fromARGB(12, 26, 26, 30),
    smokeAsset: 'assets/bg/smoke_light.png',
    blobAsset: 'assets/bg/blob_light.png',
    isNight: false,
  );

  static const night = AgColors(
    bg: Color(0xFF08090B),
    ink: Color(0xFFF3F3F5),
    ink2: Color(0xFFC6C6CC),
    artist: Color(0xFFC4C4CA),
    muted: Color(0xFF8A8A92),
    disabled: Color(0xFF7A7A82),
    accent: Color(0xFFE5232B),
    barPlayed: Color(0xFFF3F3F5),
    barRest: Color.fromRGBO(243, 243, 245, 0.20),
    wordmark: Color(0xFFD8D8DE),
    focus: Color(0xFFF3F3F5),
    winLine: Color(0xFF2A2A30),
    closeHover: Color(0xFFC42B1C),
    closeGlyph: Color(0xFFFFFFFF),
    glass: Color.fromARGB(210, 22, 22, 26),
    glassHover: Color.fromRGBO(255, 255, 255, 0.06),
    glassPressed: Color.fromRGBO(255, 255, 255, 0.10),
    glassTile: Color.fromARGB(220, 32, 32, 38),
    rim: Color.fromARGB(36, 255, 255, 255),
    hairline: Color.fromRGBO(255, 255, 255, 0.06),
    skeleton: Color.fromRGBO(255, 255, 255, 0.10),
    artTile: Color(0xFF1E1E23),
    artNote: Color(0xFF8A8A92),
    headerFill: Color.fromARGB(230, 24, 24, 28),
    pillFill: Color.fromARGB(230, 24, 24, 28),
    playCircle: Color.fromRGBO(255, 255, 255, 0.10),
    playCircleRim: Color.fromARGB(36, 255, 255, 255),
    dialogFill: Color.fromARGB(245, 22, 22, 26),
    scrim: Color.fromRGBO(0, 0, 0, 0.30),
    markFill: Color(0xFF24242A),
    primaryHover: Color(0xFFDCDCE0),
    primaryPressed: Color(0xFFC6C6CC),
    pillShadow: Color.fromARGB(90, 0, 0, 0),
    menuShadow: Color.fromARGB(80, 0, 0, 0),
    dialogShadow: Color.fromARGB(90, 0, 0, 0),
    liftShadow: Color.fromRGBO(0, 0, 0, 0.31),
    cardShadow: Color.fromARGB(70, 0, 0, 0),
    heartRest: Color.fromARGB(102, 243, 243, 245),
    playingFill: Color.fromRGBO(255, 255, 255, 0.07),
    menuFill: Color.fromARGB(245, 22, 22, 26),
    tabThumb: Color.fromARGB(36, 255, 255, 255),
    tabThumbRim: Color.fromARGB(50, 255, 255, 255),
    tabDivider: Color.fromARGB(40, 255, 255, 255),
    switchTrack: Color.fromRGBO(255, 255, 255, 0.07),
    switchRim: Color.fromRGBO(255, 255, 255, 0.16),
    switchKnob: Color(0xFFE8E8EE),
    switchOn: Color(0xFFF3F3F5),
    tipFill: Color(0xFF141418),
    gridDot: Color.fromARGB(18, 255, 255, 255),
    hitZone: Color.fromRGBO(255, 255, 255, 0.04),
    dropTop: Color.fromRGBO(240, 50, 58, 1),
    dropMid: Color(0xFFE5232B),
    dropBottom: Color.fromRGBO(176, 20, 28, 1),
    dropHighlight: Color.fromRGBO(255, 255, 255, 0.31),
    dropRim: Color.fromRGBO(255, 255, 255, 0.22),
    dropGlyph: Color(0xFFFFFFFF),
    panelScrim: Color.fromARGB(72, 0, 0, 0),
    offIcon: Color.fromARGB(115, 243, 243, 245),
    likedFill: Color.fromARGB(22, 255, 255, 255),
    smokeAsset: 'assets/bg/smoke_night.png',
    blobAsset: 'assets/bg/blob_night.png',
    isNight: true,
  );

  static AgColors of(BuildContext context) => Theme.of(context).extension<AgColors>()!;

  @override
  AgColors copyWith() => this;

  @override
  AgColors lerp(AgColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

abstract final class Dp {
  static const topBar = 52.0;
  static const loginBar = 40.0;
  static const column = 1140.0;
  static const trackColumn = 1000.0;
  static const pagePad = 24.0;
  static const hPad = 24.0;
  static const titleRow = 44.0;
  static const row = 45.0;
  static const rowCover = 32.0;
  static const dotCol = 16.0;
  static const commentRow = 52.0;
  static const relatedRow = 48.0;
  static const searchW = 168.0;
  static const searchH = 28.0;
  static const avatar = 28.0;
  static const tabsW = 250.0;
  static const tabsH = 34.0;
  static const chipH = 28.0;
  static const winBtn = 46.0;
  static const iconBtn = 32.0;
  static const pageIconBtn = 28.0;
  static const playBtn = 36.0;
  static const transportIcon = 22.0;
  static const playerMinW = 560.0;
  static const playerMaxW = 720.0;
  static const playerH = 76.0;
  static const playerBottom = 16.0;
  static const playerCover = 44.0;
  static const seek = 3.5;
  static const seekHover = 5.5;
  static const seekThumb = 10.0;
  static const seekHit = 12.0;
  static const volW = 80.0;
  static const switchW = 36.0;
  static const switchH = 20.0;
  static const focus = 2.0;
  static const cardPadY = 6.0;

  static const fadeH = 24.0;
  static const trackBreakpoint = 1200.0;

  static const panelBreakpoint = 1280.0;
  static const listOpenFrac = 0.55;
  static const panelPad = 40.0;
  static const panelGutter = 28.0;
  static const panelTop = topBar + 8;
  static const panelNarrowW = 420.0;
  static const rPanelSide = 20.0;
  static const queueRow = 56.0;
  static const panelAnim = Duration(milliseconds: 280);
  static const minWindow = Size(960, 600);

  static const contentBottom = playerBottom + playerH;

  static const rWindow = 8.0;
  static const rCard = 18.0;
  static const rPanel = 16.0;
  static const rPill = 14.0;
  static const rPlayer = 20.0;
  static const rMenu = 12.0;
  static const rSortMenu = 10.0;
  static const rButton = 10.0;
  static const rChip = 8.0;
  static const rIconBtn = 8.0;
  static const rRowCover = 6.0;
  static const rCover = 8.0;
  static const rCoverLarge = 14.0;
  static const rBezel = 18.0;
  static const rBadge = 4.0;
  static const rTooltip = 6.0;
  static const rDialog = 14.0;
}

abstract final class AgType {
  static TextStyle ui(double size, Color color, {int weight = 400}) => TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    fontWeight: _nearest(weight),
    fontVariations: [FontVariation('wght', weight.toDouble())],
    color: color,
    height: 1.2,
    letterSpacing: 0,
  );

  static TextStyle tnum(double size, Color color, {int weight = 500}) =>
      ui(size, color, weight: weight).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle doto(double size, Color color) {
    assert(size >= 20, 'Doto is only used from 20 dp');
    return TextStyle(
      fontFamily: 'Doto',
      fontSize: size,
      fontWeight: FontWeight.w900,
      color: color,
      height: 1.1,
      letterSpacing: 0,
    );
  }

  static FontWeight _nearest(int w) => FontWeight.values[((w / 100).round() - 1).clamp(0, 8)];
}

ThemeData buildTheme(AgColors c) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: c.isNight ? Brightness.dark : Brightness.light,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: c.hover,
    focusColor: Colors.transparent,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.ink,
      brightness: c.isNight ? Brightness.dark : Brightness.light,
      surface: c.bg,
      onSurface: c.ink,
      primary: c.ink,
      onPrimary: c.bg,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.ink,
      selectionColor: c.ink.withValues(alpha: 0.18),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.tipFill,
        borderRadius: BorderRadius.circular(Dp.rTooltip),
        border: Border.all(color: Color.alphaBlend(c.rim, c.bg)),
      ),
      textStyle: AgType.ui(11, c.ink, weight: 500),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      waitDuration: const Duration(milliseconds: 250),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.menuFill,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Dp.rMenu),
        side: BorderSide(color: c.rim),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.rim),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
    ),
  );
  return base.copyWith(extensions: [c]);
}
