import 'dart:async';
import 'package:flutter/material.dart';

import '../app/app_services.dart';
import '../app/update_controller.dart';
import '../core/update_check.dart';
import '../app/ui_state.dart';
import 'cover_scene.dart';
import 'focus_view.dart';
import 'player_dock.dart';
import 'theme/tokens.dart';
import 'top_bar.dart';
import 'track_panel.dart';
import 'widgets/buttons.dart';
import 'widgets/glass.dart';

export 'top_bar.dart' show SearchFocus;

class WindowFrame extends StatelessWidget {
  const WindowFrame({super.key, required this.child, this.scene, this.focus});

  final Widget child;
  final CoverScene? scene;
  final Animation<double>? focus;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: app.window.maximized,
      builder: (context, max, child) => Container(
        color: c.bg,
        foregroundDecoration: max
            ? null
            : BoxDecoration(
                border: Border.all(color: c.winLine),
                borderRadius: BorderRadius.circular(Dp.rWindow),
              ),
        child: child,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverBackground(scene: scene, focus: focus),
          child,
        ],
      ),
    );
  }
}

class LoginBar extends StatelessWidget {
  const LoginBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Container(
      height: Dp.loginBar,
      decoration: BoxDecoration(
        color: c.headerFill,
        border: Border(bottom: BorderSide(color: c.winLine)),
      ),
      child: const Row(
        children: [
          Expanded(child: DragZone()),
          WindowButtons(height: Dp.loginBar - 1),
        ],
      ),
    );
  }
}

Future<void> confirmLogout(BuildContext context) async {
  final app = AppScope.of(context);
  final c = AgColors.of(context);
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: c.scrim,
    builder: (context) => const LogoutDialog(),
  );
  if (ok == true) await app.logout();
}

class LogoutDialog extends StatelessWidget {
  const LogoutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Center(
      child: FrostedGlass(
        width: 248,
        radius: Dp.rDialog,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Log out?', style: AgType.ui(16, c.ink, weight: 600)),
              const SizedBox(height: 8),
              Text(
                "You'll need to sign in with SoundCloud again. "
                'Local likes stay on this computer.',
                style: AgType.ui(11, c.artist).copyWith(height: 1.4),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SecondaryButton(
                    label: 'Cancel',
                    width: 80,
                    height: Dp.chipH,
                    fontSize: 12,
                    weight: 500,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 8),
                  PrimaryButton(
                    label: 'Log out',
                    width: 80,
                    height: Dp.chipH,
                    fontSize: 12,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


Future<void> showUpdateDialog(BuildContext context) async {
  final app = AppScope.of(context);
  if (app.updates.offer == null && app.updates.phase == UpdatePhase.idle) {
    unawaited(app.updates.check());
  }
  await showDialog<void>(
    context: context,
    barrierColor: AgColors.of(context).scrim,
    builder: (context) => const UpdateDialog(),
  );
}

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  Future<void> _update(BuildContext context) async {
    final app = AppScope.of(context);
    if (app.player.playing) {
      final ok = await showDialog<bool>(
        context: context,
        barrierColor: AgColors.of(context).scrim,
        builder: (context) => const UpdateConfirmDialog(),
      );
      if (ok != true) return;
    }
    await app.updates.apply();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    return Center(
      child: ListenableBuilder(
        listenable: app.updates,
        builder: (context, _) {
          final u = app.updates;
          final offer = u.offer;
          final checking = u.phase == UpdatePhase.checking;
          final busy = u.phase == UpdatePhase.downloading ||
              u.phase == UpdatePhase.applying;
          final title = offer == null
              ? 'Updates'
              : 'Version ${offer.version.label} available';
          final body = u.message ??
              (checking ? 'Checking…' : '');
          final notes = offer?.notes ?? '';
          return FrostedGlass(
            width: 360,
            radius: Dp.rDialog,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AgType.ui(16, c.ink, weight: 600)),
                  const SizedBox(height: 8),
                  Text(
                    'Current version ${u.current.label}',
                    style: AgType.ui(11, c.artist),
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(body, style: AgType.ui(12, c.ink).copyWith(height: 1.4)),
                  ],
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: SingleChildScrollView(
                        child: Text(
                          notes,
                          style: AgType.ui(11, c.artist).copyWith(height: 1.4),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SecondaryButton(
                        label: busy ? 'Working…' : 'Close',
                        width: 88,
                        height: Dp.chipH,
                        fontSize: 12,
                        weight: 500,
                        onTap: busy ? null : () => Navigator.of(context).pop(),
                      ),
                      if (offer != null && !checking) ...[
                        const SizedBox(width: 8),
                        PrimaryButton(
                          label: busy
                              ? (u.percent == null
                                  ? 'Update'
                                  : '${u.percent}%')
                              : 'Update',
                          width: 88,
                          height: Dp.chipH,
                          fontSize: 12,
                          onTap: busy ? null : () => _update(context),
                        ),
                      ] else if (u.phase == UpdatePhase.failed ||
                          (u.phase == UpdatePhase.idle && offer == null)) ...[
                        const SizedBox(width: 8),
                        PrimaryButton(
                          label: checking ? 'Checking…' : 'Check',
                          width: 88,
                          height: Dp.chipH,
                          fontSize: 12,
                          onTap: checking ? null : () => u.check(),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class UpdateConfirmDialog extends StatelessWidget {
  const UpdateConfirmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Center(
      child: FrostedGlass(
        width: 280,
        radius: Dp.rDialog,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Update now?', style: AgType.ui(16, c.ink, weight: 600)),
              const SizedBox(height: 8),
              Text(
                'A track is playing. Playback will stop while the update is installed.',
                style: AgType.ui(11, c.artist).copyWith(height: 1.4),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SecondaryButton(
                    label: 'Cancel',
                    width: 80,
                    height: Dp.chipH,
                    fontSize: 12,
                    weight: 500,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 8),
                  PrimaryButton(
                    label: 'Update',
                    width: 80,
                    height: Dp.chipH,
                    fontSize: 12,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SnackbarHost extends StatelessWidget {
  const SnackbarHost({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    return ListenableBuilder(
      listenable: app.messages,
      builder: (context, _) {
        final m = app.messages.current;
        if (m == null) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          right: 0,
          bottom: Dp.contentBottom + 12,
          child: Center(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: Color.alphaBlend(c.pillFill, c.bg),
                border: Border.all(color: Color.alphaBlend(c.rim, c.bg)),
                borderRadius: BorderRadius.circular(Dp.rMenu),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(m.text, style: AgType.ui(13, c.ink, weight: 450)),
                  if (m.action != null) ...[
                    Text('   ·   ', style: AgType.ui(13, c.muted, weight: 450)),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          app.messages.dismiss();
                          m.onAction?.call();
                        },
                        child: Text(
                          m.action!,
                          style: AgType.ui(13, c.ink, weight: 650),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with TickerProviderStateMixin {
  CoverScene? _scene;
  AppServices? _app;
  String? _offered;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: Dp.panelAnim,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _anim,
    curve: Curves.easeOutCubic,
  );
  late final AnimationController _focusAnim = AnimationController(
    vsync: this,
    duration: FocusGeo.enter,
    reverseDuration: FocusGeo.exit,
  );
  late final Animation<double> _f = CurvedAnimation(
    parent: _focusAnim,
    curve: Curves.easeOutCubic,
  );
  // 1 while the capsule and the close button are shown in focus mode.
  late final AnimationController _chrome = AnimationController(
    vsync: this,
    value: 1,
  );
  Timer? _idle;
  bool _overBar = false, _pressingBar = false;

  bool get _wantOpen =>
      (_app?.panel.isOpen ?? false) && _app?.player.current != null;

  bool get _reduce => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (_scene?.player != app.player || _scene?.waveforms != app.waveforms) {
      _scene?.dispose();
      _scene = CoverScene(
        player: app.player,
        waveforms: app.waveforms,
        waveformUrlOf: app.waveformUrlOf,
      );
    }
    if (app != _app) {
      _app?.panel.removeListener(_sync);
      _app?.player.removeListener(_sync);
      _app?.focus.removeListener(_syncFocus);
      _app?.updates.onSilentOffer = null;
      _app = app;
      app.panel.addListener(_sync);
      app.player.addListener(_sync);
      app.focus.addListener(_syncFocus);
      app.updates.onSilentOffer = _onSilentOffer;
      _anim.value = _wantOpen ? 1 : 0;
      _focusAnim.value = app.focus.isOn ? 1 : 0;
    }
  }

  void _sync() {
    final app = _app;
    if (app == null) return;
    if (app.player.current == null) {
      if (app.panel.isOpen) app.panel.close();
      app.focus.exit();
    }
    final target = _wantOpen ? 1.0 : 0.0;
    if (_anim.value == target && !_anim.isAnimating) return;
    if (_reduce) {
      _anim.value = target;
    } else if (target == 1) {
      _anim.forward();
    } else {
      _anim.reverse();
    }
  }

  void _syncFocus() {
    final app = _app;
    if (app == null) return;
    final on = app.focus.isOn;
    if (on && app.player.current == null) {
      app.focus.exit();
      return;
    }
    if (_reduce) {
      _focusAnim.value = on ? 1 : 0;
    } else if (on) {
      _focusAnim.forward();
    } else {
      _focusAnim.reverse();
    }
    _showChrome(instant: true);
  }

  void _showChrome({bool instant = false}) {
    _idle?.cancel();
    if (instant || _reduce) {
      _chrome.value = 1;
    } else if (_chrome.value < 1) {
      _chrome.animateTo(1, duration: FocusGeo.show);
    }
    if (_app?.focus.isOn ?? false) _idle = Timer(FocusGeo.idle, _hideChrome);
  }

  void _hideChrome() {
    if (!mounted || !(_app?.focus.isOn ?? false)) return;
    if (_overBar || _pressingBar) return;
    if (_reduce) {
      _chrome.value = 0;
    } else {
      _chrome.animateTo(0, duration: FocusGeo.hide);
    }
  }

  void _onPointer(PointerEvent e) {
    if (!(_app?.focus.isOn ?? false)) return;
    _showChrome();
  }

  void _onSilentOffer(UpdateOffer offer) {
    if (_offered == offer.version.label) return;
    _offered = offer.version.label;
    final app = _app;
    if (app == null) return;
    app.messages.show(
      'Version ${offer.version.label} is available',
      action: 'Update',
      onAction: () {
        app.messages.dismiss();
        if (!mounted) return;
        showUpdateDialog(context);
      },
    );
  }

  @override
  void dispose() {
    _idle?.cancel();
    _app?.panel.removeListener(_sync);
    _app?.player.removeListener(_sync);
    _app?.focus.removeListener(_syncFocus);
    _app?.updates.onSilentOffer = null;
    _anim.dispose();
    _focusAnim.dispose();
    _chrome.dispose();
    _scene?.dispose();
    super.dispose();
  }

  // Fades a layer out as focus mode comes in, shifted by [shift] dp.
  // The tree shape stays the same at f == 0 so nothing below loses its state.
  static Widget _recede(double f, double shift, Widget child) {
    return IgnorePointer(
      ignoring: f > 0,
      child: Opacity(
        opacity: 1 - f,
        child: Transform.translate(offset: Offset(0, shift * f), child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = AgColors.of(context);
    final content = ClipRect(child: widget.child);
    return WindowFrame(
      scene: _scene,
      focus: _f,
      child: CoverSceneHost(
        scene: _scene!,
        child: PanelScope(
          animation: _t,
          child: LayoutBuilder(
            builder: (context, box) {
              final size = box.biggest;
              final panel = TrackPanelView(
                narrow: size.width <= Dp.panelBreakpoint,
              );
              final capsule = MouseRegion(
                onEnter: (_) => _overBar = true,
                onExit: (_) {
                  _overBar = false;
                  if (app.focus.isOn) _showChrome();
                },
                child: Listener(
                  onPointerDown: (_) => _pressingBar = true,
                  onPointerUp: (_) {
                    _pressingBar = false;
                    if (app.focus.isOn) _showChrome();
                  },
                  onPointerCancel: (_) => _pressingBar = false,
                  child: FloatingPlayer(width: PlayerGeo.width(size.width)),
                ),
              );
              final bars = const TopBar();
              return ListenableBuilder(
                listenable: app.nav,
                builder: (context, _) {
                  final maxCol = app.nav.route is TrackRoute
                      ? Dp.trackColumn
                      : Dp.column;
                  return AnimatedBuilder(
                    animation: Listenable.merge([_t, _f, _chrome, app.focus]),
                    builder: (context, _) {
                      final g = PanelGeo(size, _t.value, maxColumn: maxCol);
                      final shown = _anim.value > 0;
                      final f = _f.value;
                      final focusOn = app.focus.isOn;
                      final chrome = focusOn || f > 0 ? _chrome.value : 1.0;
                      final restBottom = Dp.playerBottom;
                      final focusBottom =
                          size.height - FocusGeo.barTop(size) - Dp.playerH;
                      final hidden = focusOn && _chrome.value == 0;
                      return MouseRegion(
                        cursor: hidden ? SystemMouseCursors.none : MouseCursor.defer,
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerHover: _onPointer,
                          onPointerMove: _onPointer,
                          onPointerDown: _onPointer,
                          child: Stack(
                            children: [
                              Column(
                                children: [
                                  _recede(f, -12, bars),
                                  Expanded(
                                    child: _recede(
                                      f,
                                      16,
                                      Stack(
                                        children: [
                                          Positioned(
                                            left: g.columnLeft - Dp.hPad,
                                            width: g.columnInner + 2 * Dp.hPad,
                                            top: 0,
                                            bottom: Dp.contentBottom,
                                            child: content,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (shown && g.overlay)
                                Positioned(
                                  key: const ValueKey('panel-scrim'),
                                  left: 0,
                                  right: 0,
                                  top: Dp.topBar,
                                  bottom: 0,
                                  child: _recede(
                                    f,
                                    0,
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: app.panel.close,
                                      child: ColoredBox(
                                        color: c.panelScrim.withValues(
                                          alpha: c.panelScrim.a * _t.value,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (shown)
                                Positioned(
                                  key: const ValueKey('panel'),
                                  left: g.panelLeft,
                                  top: g.panelTop,
                                  width: g.panelWidth,
                                  height: g.panelBottom - g.panelTop,
                                  child: _recede(f, 0, panel),
                                ),
                              if (f > 0) ...[
                                const Positioned(
                                  key: ValueKey('focus-drag'),
                                  left: 0,
                                  right: 0,
                                  top: 0,
                                  height: Dp.topBar,
                                  child: DragZone(),
                                ),
                                Positioned.fromRect(
                                  key: const ValueKey('focus-art'),
                                  rect: FocusGeo.cover(size),
                                  child: IgnorePointer(
                                    child: Opacity(
                                      opacity: f,
                                      child: FocusCover(
                                        track: app.player.current,
                                        side: FocusGeo.side(size),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              Positioned(
                                key: const ValueKey('capsule'),
                                left: 0,
                                right: 0,
                                bottom: restBottom + (focusBottom - restBottom) * f,
                                child: Center(
                                  child: Opacity(opacity: chrome, child: capsule),
                                ),
                              ),
                              if (f > 0)
                                Positioned(
                                  key: const ValueKey('focus-x'),
                                  top: 10,
                                  right: 12,
                                  child: IgnorePointer(
                                    ignoring: !focusOn || _chrome.value == 0,
                                    child: Opacity(
                                      opacity: f * chrome,
                                      child: FocusCloseButton(onTap: app.focus.exit),
                                    ),
                                  ),
                                ),
                              const SnackbarHost(key: ValueKey('snackbar')),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
