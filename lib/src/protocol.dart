// The page the chat runs in and the bridge to it, in plain Dart (no
// Flutter), so the tests cover it. The widget's side of the bridge is
// the widget's in-app mode (data-embedded="app" in widget.js). Keep this
// file in step with src/protocol.ts in Replyze/react-native-live-chat.

import 'dart:convert';

const int replyzeProtocolVersion = 1;
const String defaultApiUrl = 'https://client.replyze.chat';
const String defaultCdnUrl = 'https://cdn.replyze.chat';

/// The page address when the app gives none: fine while the widget has no
/// allowed-domains list. With a list, use a URL on one of its domains.
const String defaultBaseUrl = 'https://cdn.replyze.chat/in-app';
const String defaultPageTitle = 'In-app chat';

/// Replyze.configure()'s options.
class ReplyzeOptions {
  const ReplyzeOptions({
    required this.widgetToken,
    this.baseUrl,
    this.apiUrl,
    this.cdnUrl,
    this.language,
    this.tracking = true,
    this.showCloseButton = true,
    this.pageTitle,
  });

  /// The widget's embed token, "wgt_..." (Settings → Integrations → Install widget).
  final String widgetToken;

  /// The address the chat page runs at: the inbox shows it as the visitor's
  /// page and the Replyze API sees its domain as the Origin. When the widget
  /// has an allowed-domains list, use a URL on one of those domains, e.g.
  /// "https://yourshop.com/app". Nothing is loaded from it.
  final String? baseUrl;

  /// The Replyze API (default https://client.replyze.chat).
  final String? apiUrl;

  /// Where widget.js is served from (default https://cdn.replyze.chat).
  final String? cdnUrl;

  /// The interface language ("de", "sr", "pt-BR"...).
  final String? language;

  /// Visitor presence (the Visitors page). Default true.
  final bool tracking;

  /// The chat's close buttons. False when the chat is one of your own screens.
  final bool showCloseButton;

  /// The page title the team sees next to the conversation.
  final String? pageTitle;

  ReplyzeOptions copyWith({
    String? widgetToken,
    String? baseUrl,
    String? apiUrl,
    String? cdnUrl,
    String? language,
    bool? tracking,
    bool? showCloseButton,
    String? pageTitle,
  }) {
    return ReplyzeOptions(
      widgetToken: widgetToken ?? this.widgetToken,
      baseUrl: baseUrl ?? this.baseUrl,
      apiUrl: apiUrl ?? this.apiUrl,
      cdnUrl: cdnUrl ?? this.cdnUrl,
      language: language ?? this.language,
      tracking: tracking ?? this.tracking,
      showCloseButton: showCloseButton ?? this.showCloseButton,
      pageTitle: pageTitle ?? this.pageTitle,
    );
  }
}

/// The options checked, with the defaults filled in.
class ResolvedOptions {
  const ResolvedOptions({
    required this.widgetToken,
    required this.baseUrl,
    required this.apiUrl,
    required this.cdnUrl,
    required this.language,
    required this.tracking,
    required this.showCloseButton,
    required this.pageTitle,
  });

  final String widgetToken;
  final String baseUrl;
  final String apiUrl;
  final String cdnUrl;
  final String? language;
  final bool tracking;
  final bool showCloseButton;
  final String pageTitle;
}

/// Who the user is. With identity verification on, [userHash] is the
/// HMAC-SHA256 your server computes.
class ReplyzeUser {
  const ReplyzeUser({this.email, this.name, this.userId, this.userHash});

  final String? email;
  final String? name;

  /// Your own id for this user (a String or an int).
  final Object? userId;

  /// HMAC-SHA256(userId, or email without one, the widget's identity
  /// secret), hex. Compute it on your server; never ship the secret.
  final String? userHash;
}

/// A reply from the AI or the team.
class ReplyzeMessage {
  const ReplyzeMessage({
    required this.id,
    required this.text,
    required this.sender,
    this.senderName,
    this.createdAt,
    this.type = 'text',
  });

  final String id;
  final String text;

  /// "bot" or "agent".
  final String sender;
  final String? senderName;
  final String? createdAt;

  /// "text", or e.g. "rating_request" for the rating card.
  final String type;

  @override
  bool operator ==(Object other) =>
      other is ReplyzeMessage &&
      other.id == id &&
      other.text == text &&
      other.sender == sender &&
      other.senderName == senderName &&
      other.createdAt == createdAt &&
      other.type == type;

  @override
  int get hashCode => Object.hash(id, text, sender, senderName, createdAt, type);

  @override
  String toString() => 'ReplyzeMessage($id, $sender: $text)';
}

/// load_timeout, help_unavailable, unknown_command, invalid_options
class ReplyzeError {
  const ReplyzeError(this.code, this.message);

  final String code;
  final String message;

  @override
  bool operator ==(Object other) => other is ReplyzeError && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'ReplyzeError($code: $message)';
}

/// Safe-area insets in logical pixels (CSS pixels in the page).
class ReplyzeInsets {
  const ReplyzeInsets({this.top, this.right, this.bottom, this.left});

  final double? top;
  final double? right;
  final double? bottom;
  final double? left;
}

class ReplyzeConfigError implements Exception {
  ReplyzeConfigError(String message) : message = '[Replyze] $message';

  final String message;

  @override
  String toString() => 'ReplyzeConfigError: $message';
}

// ---- events from the widget ----

sealed class WidgetEvent {
  const WidgetEvent();
}

class ReadyEvent extends WidgetEvent {
  const ReadyEvent(this.version);
  final int version;
}

class CloseEvent extends WidgetEvent {
  const CloseEvent();
}

class UnreadEvent extends WidgetEvent {
  const UnreadEvent(this.count);
  final int count;
}

class MessageEvent extends WidgetEvent {
  const MessageEvent(this.message);
  final ReplyzeMessage message;
}

class IdentifiedEvent extends WidgetEvent {
  const IdentifiedEvent(this.verified);
  final bool verified;
}

class OpenUrlEvent extends WidgetEvent {
  const OpenUrlEvent(this.url);
  final String url;
}

class ErrorEvent extends WidgetEvent {
  const ErrorEvent(this.error);
  final ReplyzeError error;
}

class LogEvent extends WidgetEvent {
  const LogEvent(this.level, this.message);
  final String level;
  final String message;
}

final RegExp _token = RegExp(r'^[A-Za-z0-9_-]{4,128}$');
final RegExp _language = RegExp(r'^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8}){0,3}$');
final RegExp _unsafeUrlChars = RegExp('["\'<>\\\\`\\s]');

/// Plain http only for a backend on the developer's own machine (10.0.2.2
/// is the Android emulator's host).
const List<String> _devHosts = ['localhost', '127.0.0.1', '10.0.2.2'];

String _checkUrl(String name, String value) {
  final trimmed = value.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      _unsafeUrlChars.hasMatch(trimmed)) {
    throw ReplyzeConfigError('$name must be an absolute http(s) URL without credentials, got "$value".');
  }
  if (uri.scheme != 'https' && !_devHosts.contains(uri.host)) {
    throw ReplyzeConfigError('$name must use https (http only for localhost), got "$value".');
  }
  return trimmed;
}

String _stripSlash(String url) => url.replaceAll(RegExp(r'/+$'), '');

/// Checks the options and fills in the defaults; throws [ReplyzeConfigError].
ResolvedOptions resolveOptions(ReplyzeOptions? options) {
  final token = options?.widgetToken.trim() ?? '';
  if (!_token.hasMatch(token)) {
    throw ReplyzeConfigError('widgetToken is missing or invalid. Copy it from Settings → Integrations → Install widget ("wgt_...").');
  }
  final o = options!;
  final language = (o.language ?? '').trim();
  if (language.isNotEmpty && !_language.hasMatch(language)) {
    throw ReplyzeConfigError('language must be a language code like "de" or "pt-BR", got "$language".');
  }
  final title = (o.pageTitle ?? '').trim();
  return ResolvedOptions(
    widgetToken: token,
    baseUrl: _checkUrl('baseUrl', o.baseUrl ?? defaultBaseUrl),
    apiUrl: _stripSlash(_checkUrl('apiUrl', o.apiUrl ?? defaultApiUrl)),
    cdnUrl: _stripSlash(_checkUrl('cdnUrl', o.cdnUrl ?? defaultCdnUrl)),
    language: language.isEmpty ? null : language,
    tracking: o.tracking,
    showCloseButton: o.showCloseButton,
    pageTitle: title.isEmpty ? defaultPageTitle : (title.length > 120 ? title.substring(0, 120) : title),
  );
}

/// For text and double-quoted attributes (every attribute here is double-quoted).
String _escape(String value) =>
    value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// The chat page: widget.js in in-app mode, configured by data attributes,
/// so there is no inline script and the page's CSP allows scripts from the
/// widget's CDN only. Loaded with loadHtmlString(html, baseUrl: baseUrl).
String buildChatHtml(ResolvedOptions o) {
  final cdn = Uri.parse(o.cdnUrl);
  final cdnOrigin = '${cdn.scheme}://${cdn.host}${cdn.hasPort ? ':${cdn.port}' : ''}';
  final dev = o.apiUrl.startsWith('http:') || o.cdnUrl.startsWith('http:');
  final csp = [
    "default-src 'none'",
    'script-src $cdnOrigin',
    "style-src 'unsafe-inline'",
    'img-src https: data: blob:${dev ? ' http:' : ''}',
    'media-src https: data: blob:',
    'font-src https: data:',
    'connect-src https: wss:${dev ? ' http: ws:' : ''}',
    'frame-src https:',
    "object-src 'none'",
    "base-uri 'none'",
    "form-action 'none'",
  ].join('; ');

  final attrs = <List<String>>[
    ['src', '${o.cdnUrl}/widget.js'],
    ['data-token', o.widgetToken],
    ['data-embedded', 'app'],
    ['data-api-url', o.apiUrl],
    if (o.language != null) ['data-language', o.language!],
    if (!o.tracking) ['data-tracking', 'false'],
    if (!o.showCloseButton) ['data-close-button', 'false'],
  ];
  final script = attrs.map((a) => '${a[0]}="${_escape(a[1])}"').join(' ');

  return [
    '<!doctype html>',
    '<html lang="${_escape(o.language ?? 'en')}">',
    '<head>',
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">',
    '<meta http-equiv="Content-Security-Policy" content="${_escape(csp)}">',
    '<meta name="referrer" content="strict-origin-when-cross-origin">',
    '<title>${_escape(o.pageTitle)}</title>',
    '<style>html,body{margin:0;height:100%;overflow:hidden;background:#fff}@media (prefers-color-scheme:dark){html,body{background:#0f172a}}</style>',
    '</head>',
    '<body>',
    '<script $script></script>',
    '</body>',
    '</html>',
  ].join('\n');
}

final String _lineSeparator = String.fromCharCode(0x2028);
final String _paragraphSeparator = String.fromCharCode(0x2029);

/// The JavaScript that hands one command to the widget (for runJavaScript).
String commandScript(Map<String, Object?> command) {
  final json = jsonEncode(command)
      .replaceAll(_lineSeparator, r'\u2028')
      .replaceAll(_paragraphSeparator, r'\u2029');
  return '(function(){try{window.ReplyzeApp&&window.ReplyzeApp.receive($json);}catch(e){}})();';
}

String? _str(Object? v) => v is String ? v : null;

/// One message from the widget, checked; null for anything else.
WidgetEvent? parseEvent(Object? raw) {
  Object? value = raw;
  if (raw is String) {
    try {
      value = jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
  if (value is! Map) return null;
  if (value['replyze'] != replyzeProtocolVersion || value['type'] is! String) return null;
  final rawData = value['data'];
  final data = rawData is Map ? rawData : const <String, Object?>{};

  switch (value['type'] as String) {
    case 'ready':
      final version = data['version'];
      return ReadyEvent(version is int ? version : replyzeProtocolVersion);
    case 'close':
      return const CloseEvent();
    case 'unread':
      final count = data['count'];
      return UnreadEvent(count is num && count.isFinite ? (count < 0 ? 0 : count.floor()) : 0);
    case 'message':
      return MessageEvent(ReplyzeMessage(
        id: _str(data['id']) ?? '',
        text: _str(data['text']) ?? '',
        sender: data['sender'] == 'agent' ? 'agent' : 'bot',
        senderName: _str(data['senderName']),
        createdAt: _str(data['createdAt']),
        type: _str(data['type']) ?? 'text',
      ));
    case 'identified':
      return IdentifiedEvent(data['verified'] == true);
    case 'openUrl':
      final url = _str(data['url']);
      return url != null && isExternalUrl(url) ? OpenUrlEvent(url) : null;
    case 'error':
      return ErrorEvent(ReplyzeError(_str(data['code']) ?? 'unknown', _str(data['message']) ?? ''));
    case 'log':
      return LogEvent(_str(data['level']) ?? 'info', _str(data['message']) ?? '');
    default:
      return null;
  }
}

final RegExp _external = RegExp(r'^(https?://|mailto:|tel:|sms:)', caseSensitive: false);

/// Links the app opens itself: web pages, email, phone and SMS.
bool isExternalUrl(String url) => _external.hasMatch(url.trim());

/// Whether the WebView may load this URL itself: only the chat page.
bool isChatPage(String url, String baseUrl) {
  if (url.isEmpty || url == 'about:blank' || url.startsWith('about:srcdoc') || url.startsWith('data:')) return true;
  String strip(String u) => u.split('#').first.replaceAll(RegExp(r'/+$'), '');
  return strip(url) == strip(baseUrl);
}

Map<String, Object?> insetsCommand(ReplyzeInsets? insets) {
  final args = <String, Object?>{};
  void put(String side, double? v) {
    if (v != null && v.isFinite) args[side] = v < 0 ? 0 : v.round();
  }

  put('top', insets?.top);
  put('right', insets?.right);
  put('bottom', insets?.bottom);
  put('left', insets?.left);
  return {'cmd': 'setInsets', 'args': args};
}

/// The widget's identify command from the SDK's user; null without an email, name or id.
Map<String, Object?>? identifyCommand(ReplyzeUser user) {
  final args = <String, Object?>{};
  final email = user.email?.trim() ?? '';
  final name = user.name?.trim() ?? '';
  if (email.isNotEmpty) args['email'] = email;
  if (name.isNotEmpty) args['name'] = name;
  final id = user.userId;
  if (id is int) {
    args['user_id'] = id;
  } else if (id is String && id.trim().isNotEmpty) {
    args['user_id'] = id.trim();
  }
  final hash = user.userHash?.trim() ?? '';
  if (hash.isNotEmpty) args['user_hash'] = hash;
  if (!args.containsKey('email') && !args.containsKey('name') && !args.containsKey('user_id')) return null;
  return {'cmd': 'identify', 'args': args};
}
