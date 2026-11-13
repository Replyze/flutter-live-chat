import 'dart:async';

import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'protocol.dart';
import 'replyze.dart';
import 'session.dart';

/// The Replyze chat in a view of its own: a screen of your app, a tab, or
/// (inside ReplyzeHost) the full-screen chat [Replyze.show] opens. Uses
/// [Replyze.configure]'s options unless [options] is given.
///
/// ```dart
/// Scaffold(
///   appBar: AppBar(title: const Text('Support')),
///   body: ReplyzeChat(
///     options: Replyze.options!.copyWith(showCloseButton: false),
///   ),
/// )
/// ```
class ReplyzeChat extends StatefulWidget {
  /// A chat view; every argument is optional.
  const ReplyzeChat({
    super.key,
    this.options,
    this.visible = true,
    this.insets,
    this.onClose,
    this.onReady,
    this.onMessage,
    this.onUnreadCountChange,
    this.onError,
    this.onOpenUrl,
    this.errorBuilder,
    this.backgroundColor = Colors.white,
  });

  /// Instead of Replyze.configure()'s options.
  final ReplyzeOptions? options;

  /// Whether the chat is on screen. While false it keeps running and
  /// replies count as unread.
  final bool visible;

  /// Safe-area insets for the page, e.g. from MediaQuery.paddingOf(context).
  /// Without them the page uses its own env(safe-area-inset-*).
  final ReplyzeInsets? insets;

  /// The visitor tapped close in the chat (e.g. pop the route).
  final VoidCallback? onClose;

  /// The chat has loaded (again after a reload).
  final VoidCallback? onReady;

  /// Every reply from the AI or the team.
  final ValueChanged<ReplyzeMessage>? onMessage;

  /// The unread count changed.
  final ValueChanged<int>? onUnreadCountChange;

  /// `load_timeout`, `help_unavailable`, `invalid_options`...
  final ValueChanged<ReplyzeError>? onError;

  /// A link in the chat; default: url_launcher, outside the app.
  final ValueChanged<String>? onOpenUrl;

  /// What to show when the chat can't load (no connection, wrong token).
  /// Default: a short message and "Try again".
  final Widget Function(BuildContext context, VoidCallback retry, ReplyzeError error)? errorBuilder;

  /// The colour behind the page while it loads. Default white.
  final Color backgroundColor;

  @override
  State<ReplyzeChat> createState() => ReplyzeChatState();
}

/// The state of a [ReplyzeChat]; with a `GlobalKey<ReplyzeChatState>` you
/// can call [reload].
class ReplyzeChatState extends State<ReplyzeChat> {
  WebViewController? _controller;
  ReplyzeConnection? _connection;
  ReplyzeError? _failure;
  String? _html;
  int _generation = 0;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    Replyze.optionsListenable.addListener(_optionsChanged);
    _subscriptions.add(Replyze.session.messages.listen((message) => widget.onMessage?.call(message)));
    _subscriptions.add(Replyze.session.unreadCountChanges.listen((count) => widget.onUnreadCountChange?.call(count)));
    _load();
  }

  @override
  void didUpdateWidget(ReplyzeChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_htmlFor(_mergedOptions()) != _html) {
      _load();
      return;
    }
    if (oldWidget.visible != widget.visible) _connection?.setVisible(widget.visible);
    if (!_sameInsets(oldWidget.insets, widget.insets)) _connection?.setInsets(widget.insets);
  }

  @override
  void dispose() {
    Replyze.optionsListenable.removeListener(_optionsChanged);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _connection?.disconnect();
    super.dispose();
  }

  /// Loads the chat page again in a fresh WebView.
  void reload() => setState(_load);

  void _optionsChanged() {
    if (widget.options == null && _htmlFor(_mergedOptions()) != _html) setState(_load);
  }

  ReplyzeOptions? _mergedOptions() => widget.options ?? Replyze.options;

  String? _htmlFor(ReplyzeOptions? options) {
    try {
      return buildChatHtml(resolveOptions(options));
    } on ReplyzeConfigError {
      return null;
    }
  }

  void _load() {
    _connection?.disconnect();
    _connection = null;
    _controller = null;
    _failure = null;

    final ResolvedOptions resolved;
    try {
      resolved = resolveOptions(_mergedOptions());
    } on ReplyzeConfigError catch (e) {
      _html = null;
      debugPrint(e.message);
      widget.onError?.call(ReplyzeError('invalid_options', e.message));
      return;
    }
    final html = buildChatHtml(resolved);
    _html = html;

    final controller = WebViewController();
    final connection = Replyze.session.connect(
      (script) => controller.runJavaScript(script).catchError((Object _) {}),
      ReplyzeConnectionHandlers(
        onReady: () {
          if (mounted && _failure != null) setState(() => _failure = null);
          widget.onReady?.call();
        },
        onClose: () => widget.onClose?.call(),
        onOpenUrl: _openUrl,
        onError: (error) {
          if (error.code == 'load_timeout' && mounted) setState(() => _failure = error);
          widget.onError?.call(error);
        },
      ),
    );

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(widget.backgroundColor)
      // The widget posts its events to window.ReplyzeFlutter (widget/src/embed/app.ts)
      ..addJavaScriptChannel('ReplyzeFlutter', onMessageReceived: (message) => connection.receive(message.message))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          // Only the chat page itself (and frames inside it, e.g. a video in
          // a help article); links open outside the app's chat.
          if (!request.isMainFrame || isChatPage(request.url, resolved.baseUrl)) {
            return NavigationDecision.navigate;
          }
          _openUrl(request.url);
          return NavigationDecision.prevent;
        },
      ));

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
      // Android's WebView has no file picker of its own: attachments need one.
      platform.setOnShowFileSelector(_pickFiles);
    }

    controller.loadHtmlString(html, baseUrl: resolved.baseUrl);
    connection.setVisible(widget.visible);
    connection.setInsets(widget.insets);

    _controller = controller;
    _connection = connection;
    _generation++;
  }

  void _openUrl(String url) {
    if (!isExternalUrl(url)) return;
    final handler = widget.onOpenUrl;
    if (handler != null) {
      handler(url);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri != null) {
      launchUrl(uri, mode: LaunchMode.externalApplication).catchError((Object _) => false);
    }
  }

  static Future<List<String>> _pickFiles(FileSelectorParams params) async {
    final mimeTypes = params.acceptTypes.where((t) => t.contains('/')).toList();
    final extensions = params.acceptTypes.where((t) => t.startsWith('.')).map((t) => t.substring(1)).toList();
    final groups = mimeTypes.isEmpty && extensions.isEmpty
        ? const <files.XTypeGroup>[]
        : [files.XTypeGroup(label: 'Files', mimeTypes: mimeTypes, extensions: extensions)];
    try {
      if (params.mode == FileSelectorMode.openMultiple) {
        final picked = await files.openFiles(acceptedTypeGroups: groups);
        return picked.map((f) => Uri.file(f.path).toString()).toList();
      }
      final picked = await files.openFile(acceptedTypeGroups: groups);
      return picked == null ? const <String>[] : [Uri.file(picked.path).toString()];
    } catch (_) {
      return const <String>[];
    }
  }

  static bool _sameInsets(ReplyzeInsets? a, ReplyzeInsets? b) =>
      a?.top == b?.top && a?.right == b?.right && a?.bottom == b?.bottom && a?.left == b?.left;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return ColoredBox(color: widget.backgroundColor);
    final failure = _failure;
    return Stack(
      alignment: Alignment.topLeft,
      children: [
        Positioned.fill(child: WebViewWidget(key: ValueKey<int>(_generation), controller: controller)),
        if (failure != null)
          Positioned.fill(
            child: widget.errorBuilder?.call(context, reload, failure) ??
                _DefaultError(onRetry: reload, background: widget.backgroundColor),
          ),
      ],
    );
  }
}

class _DefaultError extends StatelessWidget {
  const _DefaultError({required this.onRetry, required this.background});

  final VoidCallback onRetry;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("The chat couldn't load.", style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
