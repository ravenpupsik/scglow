import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../app/app_services.dart';
import '../../core/web_session.dart';
import '../shell.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';

enum LoginKind { signIn, changed, expired }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.kind});

  final LoginKind kind;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _web = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return WindowFrame(
      child: Column(
        children: [
          const LoginBar(),
          Expanded(
            child: _web && app.web != null
                ? SignInWebView(
                    web: app.web!,
                    onCancel: () => setState(() => _web = false),
                    onToken: (t) async {
                      await app.session.onSignedIn(t);
                    },
                  )
                : _Message(
                    kind: widget.kind,
                    status: app.session.changedStatus,
                    onPrimary: widget.kind == LoginKind.changed
                        ? app.session.start
                        : () => setState(() => _web = true),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.kind, required this.onPrimary, this.status});

  final LoginKind kind;
  final VoidCallback onPrimary;
  final int? status;

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return LayoutBuilder(builder: (context, box) {
      final top = ((box.maxHeight + Dp.loginBar) * 0.275 - Dp.loginBar)
          .clamp(24.0, 400.0);
      Widget at(double y, Widget child) =>
          Positioned(top: top + y, left: 0, right: 0, child: Center(child: child));
      final children = <Widget>[
        at(-9, Text('scglow', style: AgType.doto(44, c.ink))),
        at(62, Text('A personal SoundCloud client for the desktop.',
            style: AgType.ui(14, c.ink2))),
      ];
      if (kind == LoginKind.signIn) {
        children.addAll([
          at(130, PrimaryButton(
              label: 'Sign in with SoundCloud',
              height: 44,
              fontSize: 14,
              onTap: onPrimary)),
          at(193, Text(
            'Opens a SoundCloud window to sign in. The token stays on this computer.',
            style: AgType.ui(12, c.muted),
          )),
        ]);
      } else {
        final changed = kind == LoginKind.changed;
        children.addAll([
          at(110, Container(width: 80, height: 1, color: c.winLine)),
          at(135, Text(
              changed
                  ? 'SoundCloud changed something${status == null ? '' : '  ·  $status'}'
                  : 'Session expired',
              style: AgType.ui(24, c.ink, weight: 600))),
          at(181, Text(
            changed
                ? 'The usual sign-in path is unavailable. Nothing on this computer was lost.'
                : 'Sign in again to keep playing. Your likes on this computer are still here.',
            style: AgType.ui(13, c.ink2),
          )),
          at(224, changed
              ? PrimaryButton(
                  label: 'Retry', width: 140, height: 40, onTap: onPrimary)
              : PrimaryButton(
                  label: 'Sign in again',
                  height: 44,
                  fontSize: 14,
                  onTap: onPrimary)),
        ]);
      }
      return Stack(children: children);
    });
  }
}

class SignInWebView extends StatefulWidget {
  const SignInWebView({
    super.key,
    required this.web,
    required this.onToken,
    required this.onCancel,
  });

  final WebSession web;
  final Future<void> Function(String token) onToken;
  final VoidCallback onCancel;

  @override
  State<SignInWebView> createState() => _SignInWebViewState();
}

class _SignInWebViewState extends State<SignInWebView> {
  InAppWebViewController? _controller;
  Timer? _poll;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _checkToken());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _checkToken() async {
    if (_done) return;
    String? token;
    try {
      token = await widget.web.readOAuthToken();
    } catch (_) {}
    if (token == null && _controller != null) {
      try {
        final cookie =
            await _controller!.evaluateJavascript(source: 'document.cookie');
        token = WebSession.tokenFromDocumentCookie(cookie?.toString());
      } catch (_) {}
    }
    if (token == null || _done || !mounted) return;
    _done = true;
    _poll?.cancel();
    await widget.onToken(token);
  }

  @override
  Widget build(BuildContext context) {
    final c = AgColors.of(context);
    return Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: Dp.hPad),
          decoration: BoxDecoration(
            color: c.glass,
            border: Border(bottom: BorderSide(color: c.hairline)),
          ),
          child: Row(
            children: [
              Text('Sign in with SoundCloud', style: AgType.ui(13, c.ink2, weight: 500)),
              const Spacer(),
              SecondaryButton(
                  label: 'Cancel', height: 28, fontSize: 12, onTap: widget.onCancel),
            ],
          ),
        ),
        Expanded(
          child: _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('No connection', style: AgType.ui(26, c.ink, weight: 600)),
                      const SizedBox(height: 10),
                      Text(_error!, style: AgType.ui(13, c.ink2)),
                      const SizedBox(height: 22),
                      PrimaryButton(
                        label: 'Retry',
                        width: 120,
                        onTap: () => setState(() => _error = null),
                      ),
                    ],
                  ),
                )
              : InAppWebView(
                  webViewEnvironment: widget.web.environment,
                  initialUrlRequest: URLRequest(url: WebSession.signInUrl),
                  onWebViewCreated: (ctl) => _controller = ctl,
                  onLoadStop: (_, _) => _checkToken(),
                  onUpdateVisitedHistory: (_, _, _) => _checkToken(),
                  onReceivedError: (_, request, error) {
                    if (request.isForMainFrame == true && mounted) {
                      setState(() => _error = 'Could not open SoundCloud.');
                    }
                  },
                ),
        ),
      ],
    );
  }
}
