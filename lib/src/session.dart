// The app's side of the bridge, in plain Dart: commands wait until the
// widget says it is ready, who the user is (identify, language, data) is
// sent again whenever a WebView (re)loads, and the unread count and the
// widget's events reach the app. Same behaviour as
// src/session.ts in Replyze/react-native-live-chat.

import 'dart:async';

import 'protocol.dart';

/// Runs JavaScript in one WebView (WebViewController.runJavaScript).
typedef ReplyzeInjector = void Function(String script);

/// What one chat view hears from its WebView.
class ReplyzeConnectionHandlers {
  /// Handlers for one connection; each is optional.
  const ReplyzeConnectionHandlers(
      {this.onReady, this.onClose, this.onOpenUrl, this.onError});

  /// The widget in this WebView is ready (also after a reload).
  final void Function()? onReady;

  /// The visitor tapped close in the chat.
  final void Function()? onClose;

  /// A link in the chat, for the app to open outside the WebView.
  final void Function(String url)? onOpenUrl;

  /// An error from this WebView, e.g. `load_timeout`.
  final void Function(ReplyzeError error)? onError;
}

const int _maxQueue = 100;
const Set<String> _sticky = {'identify', 'setLanguage', 'setData'};

/// One WebView's end of the bridge, from [ReplyzeSession.connect]. Only
/// needed for a WebView of your own; ReplyzeChat makes its own.
class ReplyzeConnection {
  ReplyzeConnection._(
      this._session, this._inject, this._handlers, this._timeout) {
    _startTimer();
  }

  final ReplyzeSession _session;
  final ReplyzeInjector _inject;
  final ReplyzeConnectionHandlers _handlers;
  final Duration _timeout;

  bool _ready = false;
  bool _gone = false;
  bool _visible = false;
  bool _pendingReset = false;
  Map<String, Object?>? _insets;
  final List<Map<String, Object?>> _queue = [];
  Timer? _timer;

  /// Whether the widget in this WebView has said it is ready.
  bool get isReady => _ready;

  /// A message from the WebView (the JavaScript channel's message).
  void receive(Object? raw) {
    if (_gone) return;
    final event = parseEvent(raw);
    if (event == null) return;
    if (event is ReadyEvent) {
      _becomeReady();
      return;
    }
    _session._handleEvent(event, _handlers);
  }

  /// Whether the chat is on screen: messages then count as read.
  void setVisible(bool visible) {
    _visible = visible;
    if (_ready) _run({'cmd': visible ? 'open' : 'close'});
  }

  /// The safe-area insets for the page; null uses the page's own.
  void setInsets(ReplyzeInsets? insets) {
    _insets = insets == null ? null : insetsCommand(insets);
    if (_ready && _insets != null) _run(_insets!);
  }

  /// The WebView started loading again: wait for the next ready.
  void reloaded() {
    if (_gone) return;
    _ready = false;
    _startTimer();
  }

  /// The view is gone.
  void disconnect() {
    _gone = true;
    _timer?.cancel();
    _queue.clear();
    _session._connections.remove(this);
  }

  void _send(Map<String, Object?> command) {
    if (_gone) return;
    final cmd = command['cmd'];
    if (_ready) {
      if (_run(command) && cmd == 'reset') _session._resetPending = false;
    } else if (cmd == 'reset') {
      // Goes first when the widget is ready, before the new user's state.
      _pendingReset = true;
    } else if (_sticky.contains(cmd)) {
      // Sent with the session's latest state when ready (no duplicates).
    } else if (_queue.length < _maxQueue) {
      _queue.add(command);
    }
  }

  void _becomeReady() {
    _timer?.cancel();
    _ready = true;
    // The page started over: a sign-out asked for meanwhile (or one no chat
    // page has carried out yet), the insets, who the user is, whether the
    // chat is on screen, then the rest.
    final reset = _pendingReset || _session._resetPending;
    _pendingReset = false;
    if (reset && _run({'cmd': 'reset'})) _session._resetPending = false;
    if (_insets != null) _run(_insets!);
    for (final command in _session._stickyCommands()) {
      _run(command);
    }
    _run({'cmd': _visible ? 'open' : 'close'});
    final queued = List<Map<String, Object?>>.of(_queue);
    _queue.clear();
    for (final command in queued) {
      _run(command);
    }
    _handlers.onReady?.call();
    _session._readyController.add(null);
  }

  /// False when the WebView threw: it is going away, and the next ready
  /// replays what matters.
  bool _run(Map<String, Object?> command) {
    try {
      _inject(commandScript(command));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (_timeout <= Duration.zero) return;
    _timer = Timer(_timeout, () {
      _timer = null;
      if (_ready || _gone) return;
      const error = ReplyzeError('load_timeout',
          'The chat did not load. Check the connection and the widget token.');
      _handlers.onError?.call(error);
      _session._errorController.add(error);
    });
  }
}

/// The bridge state shared by every chat view: who the user is, their data,
/// the language, the unread count, and the commands that wait for a WebView
/// to be ready. `Replyze.session` is the app's one session.
class ReplyzeSession {
  /// A session; [readyTimeout] is how long a WebView may take to load, and
  /// [log] gets the widget's warnings (default: printed in debug builds).
  ReplyzeSession(
      {this.readyTimeout = const Duration(seconds: 20),
      void Function(String level, String message)? log})
      : _log = log ?? _defaultLog;

  /// How long a WebView may take to say it is ready.
  final Duration readyTimeout;
  final void Function(String level, String message) _log;

  final Set<ReplyzeConnection> _connections = {};

  /// reset() was called and no chat page has carried it out yet: no chat was
  /// loaded, or its page was loading, reloading or loaded again with "Try
  /// again". The next page that becomes ready resets first, so the next
  /// person never sees the previous user's chat, which the WebView keeps in
  /// its storage.
  bool _resetPending = false;
  Map<String, Object?>? _identity;
  Map<String, Object?>? _language;
  Map<String, Object?> _data = {};
  int _unread = 0;

  final StreamController<int> _unreadController =
      StreamController<int>.broadcast(sync: true);
  final StreamController<ReplyzeMessage> _messageController =
      StreamController<ReplyzeMessage>.broadcast(sync: true);
  final StreamController<void> _closeController =
      StreamController<void>.broadcast(sync: true);
  final StreamController<void> _readyController =
      StreamController<void>.broadcast(sync: true);
  final StreamController<ReplyzeError> _errorController =
      StreamController<ReplyzeError>.broadcast(sync: true);
  final StreamController<bool> _identifiedController =
      StreamController<bool>.broadcast(sync: true);

  /// A WebView joins: it gets every command from now on, and the user's state when ready.
  ReplyzeConnection connect(ReplyzeInjector inject,
      [ReplyzeConnectionHandlers handlers =
          const ReplyzeConnectionHandlers()]) {
    final connection =
        ReplyzeConnection._(this, inject, handlers, readyTimeout);
    _connections.add(connection);
    return connection;
  }

  /// How many WebViews are attached (one per chat view on screen or kept
  /// loaded).
  int get connectionCount => _connections.length;

  /// Unread replies while the chat is closed.
  int get unreadCount => _unread;

  /// Whether a reset() still waits for a chat page to carry it out.
  bool get isResetPending => _resetPending;

  /// Changes of [unreadCount].
  Stream<int> get unreadCountChanges => _unreadController.stream;

  /// Every reply from the AI or the team.
  Stream<ReplyzeMessage> get messages => _messageController.stream;

  /// The visitor tapped close in a chat.
  Stream<void> get closeRequests => _closeController.stream;

  /// A WebView's widget became ready (each load).
  Stream<void> get readyEvents => _readyController.stream;

  /// Errors from every WebView: `load_timeout`, `help_unavailable`...
  Stream<ReplyzeError> get errors => _errorController.stream;

  /// After identify(): whether the identity was verified.
  Stream<bool> get identified => _identifiedController.stream;

  /// Who the user is; kept and sent again whenever a WebView loads.
  void identify(ReplyzeUser user) {
    final command = identifyCommand(user);
    if (command == null) {
      _log('warn', '[Replyze] identify: give an email, a name or a userId.');
      return;
    }
    _identity = command;
    _broadcast(command);
  }

  /// The user's custom data (text, numbers, booleans; null removes a key).
  void setData(Map<String, Object?> data) {
    final clean = <String, Object?>{};
    data.forEach((key, value) {
      if (value == null || value is String || value is num || value is bool) {
        clean[key] = value;
      } else {
        _log('warn',
            '[Replyze] setData: "$key" must be text, a number, true/false or null.');
      }
    });
    if (clean.isEmpty) return;
    // Kept merged, for a WebView that loads later; null removes the key there too.
    _data = {..._data, ...clean};
    _broadcast({
      'cmd': 'setData',
      'args': {'data': clean},
    });
  }

  /// An event on the user's timeline in the inbox (a name of 1 to 64
  /// characters).
  void pushEvent(String name, [Map<String, Object?>? data]) {
    final eventName = name.trim();
    if (eventName.isEmpty || eventName.length > 64) {
      _log('warn', '[Replyze] pushEvent: the name must be 1 to 64 characters.');
      return;
    }
    _broadcast({
      'cmd': 'pushEvent',
      'args': {'name': eventName, if (data != null) 'data': data},
    });
  }

  /// The chat's language, e.g. "de"; kept for WebViews that load later.
  void setLanguage(String language) {
    if (language.trim().isEmpty) return;
    _language = {
      'cmd': 'setLanguage',
      'args': {'language': language.trim()},
    };
    _broadcast(_language!);
  }

  /// Opens a help article by its id.
  void openArticle(int id) {
    if (id <= 0) {
      _log('warn',
          '[Replyze] openArticle: the article id must be a positive whole number.');
      return;
    }
    _broadcast({
      'cmd': 'openArticle',
      'args': {'id': id},
    });
  }

  /// Sends a message as the user.
  void sendMessage(String text) {
    if (text.trim().isEmpty) return;
    _broadcast({
      'cmd': 'sendMessage',
      'args': {'text': text},
    });
  }

  /// The user signed out: forget them in the chat too. With no chat loaded,
  /// the next chat that loads does it before anything else.
  void reset() {
    _resetPending = true;
    _identity = null;
    _data = {};
    for (final connection in _connections) {
      connection._queue.clear();
    }
    _broadcast({'cmd': 'reset'});
    _setUnread(0);
  }

  List<Map<String, Object?>> _stickyCommands() {
    return [
      if (_language != null) _language!,
      if (_identity != null) _identity!,
      if (_data.isNotEmpty)
        {
          'cmd': 'setData',
          'args': {'data': Map<String, Object?>.of(_data)},
        },
    ];
  }

  void _handleEvent(WidgetEvent event, ReplyzeConnectionHandlers handlers) {
    switch (event) {
      case CloseEvent():
        handlers.onClose?.call();
        _emit(() => _closeController.add(null));
      case UnreadEvent(:final count):
        _setUnread(count);
      case MessageEvent(:final message):
        _emit(() => _messageController.add(message));
      case IdentifiedEvent(:final verified):
        _emit(() => _identifiedController.add(verified));
      case OpenUrlEvent(:final url):
        handlers.onOpenUrl?.call(url);
      case ErrorEvent(:final error):
        handlers.onError?.call(error);
        _emit(() => _errorController.add(error));
      case LogEvent(:final level, :final message):
        _log(level, message);
      case ReadyEvent():
        break;
    }
  }

  void _broadcast(Map<String, Object?> command) {
    for (final connection in List<ReplyzeConnection>.of(_connections)) {
      connection._send(command);
    }
  }

  void _setUnread(int count) {
    if (count == _unread) return;
    _unread = count;
    _emit(() => _unreadController.add(count));
  }

  /// A listener that throws must not stop the bridge.
  void _emit(void Function() add) {
    try {
      add();
    } catch (error) {
      _log('warn', '[Replyze] A listener threw: $error');
    }
  }

  static void _defaultLog(String level, String message) {
    assert(() {
      // ignore: avoid_print
      print(message);
      return true;
    }());
  }
}
