import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'protocol.dart';
import 'replyze.dart';
import 'replyze_chat.dart';

/// The full-screen chat that Replyze.show() opens, drawn over your app.
/// Put it around the app's navigator:
///
/// ```dart
/// MaterialApp(builder: (context, child) => ReplyzeHost(child: child!))
/// ```
///
/// While hidden it stays loaded, so replies are counted as unread.
/// Replyze.show(context) also puts an empty route on your navigator, so
/// Android's back button closes the chat.
class ReplyzeHost extends StatefulWidget {
  const ReplyzeHost({
    super.key,
    required this.child,
    this.preload = true,
    this.navigatorKey,
    this.onClose,
    this.onError,
    this.errorBuilder,
  });

  final Widget child;

  /// Load the chat when the app starts (hidden). False loads it on the first show().
  final bool preload;

  /// Your MaterialApp's navigatorKey, for show() without a context.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// The visitor closed the chat.
  final VoidCallback? onClose;
  final ValueChanged<ReplyzeError>? onError;
  final Widget Function(BuildContext context, VoidCallback retry, ReplyzeError error)? errorBuilder;

  @override
  State<ReplyzeHost> createState() => _ReplyzeHostState();
}

class _ReplyzeHostState extends State<ReplyzeHost> implements ReplyzeHostHandle {
  bool _visible = false;
  late bool _loaded = widget.preload;
  Route<void>? _backRoute;
  VoidCallback? _detach;

  @override
  void initState() {
    super.initState();
    _detach = Replyze.attachHost(this);
    Replyze.optionsListenable.addListener(_optionsChanged);
  }

  @override
  void dispose() {
    _detach?.call();
    Replyze.optionsListenable.removeListener(_optionsChanged);
    super.dispose();
  }

  void _optionsChanged() {
    if (mounted) setState(() {});
  }

  @override
  bool get isVisible => _visible;

  @override
  void show(BuildContext? context) {
    if (_visible) return;
    setState(() {
      _loaded = true;
      _visible = true;
    });
    final navigator = context != null ? Navigator.maybeOf(context, rootNavigator: true) : widget.navigatorKey?.currentState;
    if (navigator == null) return;
    // An empty, see-through route: the back button pops it, which closes the chat.
    final route = PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox.shrink(),
    );
    _backRoute = route;
    navigator.push(route).then((_) {
      if (!identical(_backRoute, route)) return;
      _backRoute = null;
      if (mounted && _visible) {
        setState(() => _visible = false);
        widget.onClose?.call();
      }
    });
  }

  @override
  void hide() {
    if (!_visible) return;
    setState(() => _visible = false);
    final route = _backRoute;
    _backRoute = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    // Android doesn't shrink a WebView inside Flutter for the keyboard: the
    // chat is padded instead. iOS's WebView moves its page itself.
    final keyboard = defaultTargetPlatform == TargetPlatform.android ? (media?.viewInsets.bottom ?? 0.0) : 0.0;
    final padding = media?.padding ?? EdgeInsets.zero;

    return Stack(
      alignment: Alignment.topLeft,
      children: [
        widget.child,
        if (_loaded && Replyze.options != null)
          Positioned.fill(
            child: Offstage(
              offstage: !_visible,
              child: Padding(
                padding: EdgeInsets.only(bottom: keyboard),
                child: ReplyzeChat(
                  visible: _visible,
                  insets: ReplyzeInsets(
                    top: padding.top,
                    right: padding.right,
                    bottom: keyboard > 0 ? 0.0 : padding.bottom,
                    left: padding.left,
                  ),
                  onClose: () {
                    Replyze.hide();
                    widget.onClose?.call();
                  },
                  onError: widget.onError,
                  errorBuilder: widget.errorBuilder,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
