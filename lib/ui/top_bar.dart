import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_services.dart';
import '../app/ui_state.dart';
import 'shell.dart' show confirmLogout;
import 'theme/tokens.dart';
import 'widgets/art_image.dart';
import 'widgets/glass.dart';
import 'widgets/icons.dart';
import 'widgets/interactive.dart';

class DragZone extends StatelessWidget {
  const DragZone({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => app.window.startDrag(),
      onDoubleTap: app.window.toggleMaximize,
      child: child ?? const SizedBox.expand(),
    );
  }
}

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  static const _winW = Dp.winBtn * 3;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Dp.topBar,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          const avR = _winW + 10;
          return Stack(
            children: [
              const Positioned.fill(child: DragZone()),
              const Positioned(
                left: 20,
                top: 0,
                bottom: 0,
                child: IgnorePointer(child: Center(child: Wordmark())),
              ),
              Positioned(
                left: (w - Dp.tabsW) / 2,
                top: (Dp.topBar - Dp.tabsH) / 2,
                child: const NavTabs(),
              ),
              const Positioned(
                right: avR + Dp.avatar + 10,
                top: (Dp.topBar - Dp.searchH) / 2,
                width: Dp.searchW,
                child: SearchField(),
              ),
              const Positioned(
                right: avR,
                top: (Dp.topBar - Dp.avatar) / 2,
                child: AvatarButton(),
              ),
              const Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: WindowButtons(height: Dp.topBar),
              ),
            ],
          );
        },
      ),
    );
  }
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size.square(20),
          painter: MarkPainter(c.wordmark),
        ),
        const SizedBox(width: 8),
        Text('scglow', style: AgType.doto(20, c.wordmark)),
      ],
    );
  }
}

class MarkPainter extends CustomPainter {
  MarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 7;
    final s = size.shortestSide;
    final cell = s / (n + 0.4);
    final dot = cell * 0.62;
    final off = (s - cell * n) / 2;
    final paint = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if ((i == 0 || i == n - 1) && (j == 0 || j == n - 1)) continue;
        final cx = off + (j + 0.5) * cell;
        final cy = off + (i + 0.5) * cell;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy), width: dot, height: dot),
            Radius.circular(dot * 0.2),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(MarkPainter old) => old.color != color;
}

class NavTabs extends StatelessWidget {
  const NavTabs({super.key});

  static const _labels = ['Likes', 'Playlists', 'Queue'];
  static const _inset = 3.0;
  static const _selW = 86.0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    return ListenableBuilder(
      listenable: app.nav,
      builder: (context, _) {
        final sel = switch (app.nav.section) {
          Section.likes => 0,
          Section.playlists => 1,
          Section.queue => 2,
        };
        const restW = (Dp.tabsW - 2 * _inset - _selW) / 2;
        final widths = [for (var i = 0; i < 3; i++) i == sel ? _selW : restW];
        double leftOf(int i) =>
            _inset + widths.take(i).fold<double>(0, (a, b) => a + b);
        final routes = [
          () => app.nav.go(const LikesRoute()),
          () => app.nav.go(const PlaylistsRoute()),
          () => app.nav.go(const QueueRoute()),
        ];
        int? divider;
        if (sel == 0) divider = 2;
        if (sel == 2) divider = 1;
        return Container(
          width: Dp.tabsW,
          height: Dp.tabsH,
          decoration: c.card(radius: Dp.tabsH / 2),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                left: leftOf(sel) - 1,
                top: _inset - 1,
                width: widths[sel],
                height: Dp.tabsH - 2 * _inset,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.tabThumb,
                    borderRadius: BorderRadius.circular(Dp.tabsH / 2),
                    border: Border.all(color: c.tabThumbRim),
                  ),
                ),
              ),
              if (divider != null)
                Positioned(
                  left: leftOf(divider) - 1.5,
                  top: 9,
                  bottom: 9,
                  width: 1,
                  child: ColoredBox(color: c.tabDivider),
                ),
              for (var i = 0; i < 3; i++)
                Positioned(
                  left: leftOf(i) - 1,
                  top: _inset - 1,
                  width: widths[i],
                  height: Dp.tabsH - 2 * _inset,
                  child: Interactive(
                    onTap: routes[i],
                    builder: (context, s) => FocusRing(
                      show: s.focused,
                      radius: Dp.tabsH / 2,
                      child: Center(
                        child: Text(
                          _labels[i],
                          style: i == sel
                              ? AgType.ui(13, c.ink, weight: 600)
                              : AgType.ui(
                                  13,
                                  s.hovered ? c.ink : c.ink2,
                                  weight: 450,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class SearchField extends StatefulWidget {
  const SearchField({super.key});

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _controller = TextEditingController();
  late final FocusNode _focus = FocusNode(
    onKeyEvent: (node, e) {
      if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
        _controller.clear();
        AppScope.of(context).nav.query.value = '';
        node.unfocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
  AppNav? _nav;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = AppScope.of(context).nav;
    if (nav != _nav) {
      _nav?.query.removeListener(_sync);
      _nav = nav..query.addListener(_sync);
      SearchFocus.node = _focus;
      _sync();
    }
  }

  void _sync() {
    final q = _nav!.query.value;
    if (_controller.text != q) _controller.text = q;
  }

  @override
  void dispose() {
    _nav?.query.removeListener(_sync);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Container(
      height: Dp.searchH,
      decoration: c.tile(radius: Dp.searchH / 2),
      child: Stack(
        children: [
          Positioned(
            left: 7,
            top: 3,
            child: AgIcon(AgGlyph.search, color: c.muted, size: 20),
          ),
          Positioned(
            left: 29,
            right: 10,
            top: 0,
            bottom: 0,
            child: Center(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                onChanged: (v) => AppScope.of(context).nav.query.value = v,
                cursorHeight: 14,
                cursorWidth: 1.2,
                style: AgType.ui(12, c.ink, weight: 500),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search',
                  hintStyle: AgType.ui(12, c.muted),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

abstract final class SearchFocus {
  static FocusNode? node;
}

class AvatarButton extends StatelessWidget {
  const AvatarButton({super.key});

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox;
    final at = box.localToGlobal(Offset(box.size.width, box.size.height + 6));
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        at.dx - AvatarMenu.width,
        at.dy,
        at.dx,
        at.dy,
      ),
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      constraints: const BoxConstraints.tightFor(width: AvatarMenu.width),
      menuPadding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
      items: const [AvatarMenu()],
    );
    if (choice == 'logout' && context.mounted) await confirmLogout(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    return Interactive(
      onTap: () => _open(context),
      semanticLabel: 'Account',
      builder: (context, s) => FocusRing(
        show: s.focused,
        radius: Dp.avatar / 2,
        child: Container(
          width: Dp.avatar,
          height: Dp.avatar,
          foregroundDecoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: s.hovered ? c.ink2 : c.rim),
          ),
          child: ListenableBuilder(
            listenable: app.session,
            builder: (context, _) {
              final user = app.session.user;
              final url = user?.avatarUrl;
              if (!isDefaultArt(url)) {
                return ArtImage(
                  url: url,
                  size: Dp.avatar,
                  radius: Dp.avatar / 2,
                );
              }
              final name = user?.username ?? '';
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: c.glassTile,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    name.isEmpty ? '' : name[0].toUpperCase(),
                    style: AgType.ui(12, c.ink2, weight: 600),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class AvatarMenu extends PopupMenuEntry<String> {
  const AvatarMenu({super.key});

  static const width = 214.0;
  static const _pad = 6.0;

  @override
  double get height => _pad * 2 + 28 + 3 * 30 + 9 + 36 * 2 + _hintH + 9 + 32;

  static const _hintH = 30.0;

  @override
  bool represents(String? value) => value == 'logout';

  @override
  State<AvatarMenu> createState() => _AvatarMenuState();
}

class _AvatarMenuState extends State<AvatarMenu> {
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    Widget row(double h, Widget child, VoidCallback onTap) => Interactive(
      onTap: onTap,
      builder: (context, s) => Container(
        height: h,
        padding: const EdgeInsets.only(left: 10, right: 8),
        decoration: s.hovered || s.focused || s.pressed
            ? BoxDecoration(
                color: s.pressed ? c.pressed : c.hover,
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        child: child,
      ),
    );
    Widget line() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: SizedBox(height: 1, child: ColoredBox(color: c.hairline)),
    );
    return FrostedGlass(
      radius: Dp.rMenu,
      padding: const EdgeInsets.symmetric(
        vertical: AvatarMenu._pad,
        horizontal: AvatarMenu._pad,
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([app.theme, app.tint, app.pulse]),
        builder: (context, _) {
          final mode = app.theme.value;
          Widget themeRow(ThemeMode m, String label) => row(
            30,
            Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, style: AgType.ui(13, c.ink, weight: 500)),
                ),
                if (mode == m) AgIcon(AgGlyph.check, color: c.ink, size: 16),
              ],
            ),
            () => app.theme.set(m),
          );
          Widget toggle(String label, BoolPref pref) => row(
            36,
            Row(
              children: [
                Expanded(
                  child: Text(label, style: AgType.ui(13, c.ink, weight: 500)),
                ),
                GlassSwitch(value: pref.value),
              ],
            ),
            () => pref.set(!pref.value),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 28,
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Theme',
                      style: AgType.ui(12, c.artist, weight: 600),
                    ),
                  ),
                ),
              ),
              themeRow(ThemeMode.system, 'System'),
              themeRow(ThemeMode.light, 'Light'),
              themeRow(ThemeMode.dark, 'Night'),
              line(),
              toggle('Tint from cover', app.tint),
              toggle('Pulse to beat', app.pulse),
              SizedBox(
                height: AvatarMenu._hintH,
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, top: 2),
                  child: Text(
                    'Off automatically if Windows\nreduce animations is on.',
                    style: AgType.ui(10, c.artist).copyWith(height: 1.3),
                  ),
                ),
              ),
              line(),
              row(
                32,
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Log out…',
                    style: AgType.ui(13, c.ink, weight: 500),
                  ),
                ),
                () => Navigator.of(context).pop('logout'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class GlassSwitch extends StatelessWidget {
  const GlassSwitch({super.key, required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: Dp.switchW,
      height: Dp.switchH,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? c.switchOn : c.switchTrack,
        borderRadius: BorderRadius.circular(Dp.switchH / 2),
        border: Border.all(color: c.switchRim),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: Dp.switchH - 6,
          height: Dp.switchH - 6,
          decoration: BoxDecoration(
            color: value ? c.bg : c.switchKnob,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    Widget btn(
      AgGlyph g,
      VoidCallback onTap,
      String tip, {
      bool close = false,
    }) => Interactive(
      onTap: onTap,
      semanticLabel: tip,
      builder: (context, s) {
        final red = close && (s.hovered || s.pressed);
        return Container(
          width: Dp.winBtn,
          height: height,
          color: red
              ? c.closeHover.withValues(alpha: s.pressed ? 0.85 : 1)
              : s.pressed
              ? c.pressed
              : s.hovered
              ? c.hover
              : null,
          alignment: Alignment.center,
          child: AgIcon(g, color: red ? c.closeGlyph : c.ink2, size: 12),
        );
      },
    );
    return ValueListenableBuilder<bool>(
      valueListenable: app.window.maximized,
      builder: (context, max, _) => Row(
        children: [
          btn(AgGlyph.minimize, app.window.minimize, 'Minimize'),
          btn(
            max ? AgGlyph.restore : AgGlyph.maximize,
            app.window.toggleMaximize,
            max ? 'Restore' : 'Maximize',
          ),
          btn(
            AgGlyph.close,
            app.window.hideToTray,
            'Close to tray',
            close: true,
          ),
        ],
      ),
    );
  }
}
