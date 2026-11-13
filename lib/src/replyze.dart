import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'protocol.dart';
import 'session.dart';

/// What ReplyzeHost gives the API so [Replyze.show] and [Replyze.hide] can
/// reach it.
abstract class ReplyzeHostHandle {
  /// Shows the full-screen chat; with a [context], the back button closes it.
  void show(BuildContext? context);

  /// Hides the chat (it keeps running).
  void hide();

  /// Whether the chat is on screen.
  bool get isVisible;
}

/// The Replyze API: configure once, then show the chat, say who the user
/// is, and listen for replies and the unread count. The chat itself is
/// drawn by ReplyzeHost (around your app) or by a ReplyzeChat placed in
/// one of your screens; both join this session.
class Replyze {
  Replyze._();

  /// The bridge state shared by every chat view.
  static final ReplyzeSession session = ReplyzeSession();

  static final ValueNotifier<ReplyzeOptions?> _options =
      ValueNotifier<ReplyzeOptions?>(null);
  static final List<ReplyzeHostHandle> _hosts = [];
  static final ValueNotifier<int> _unread = _followUnread();

  static ValueNotifier<int> _followUnread() {
    final notifier = ValueNotifier<int>(session.unreadCount);
    session.unreadCountChanges.listen((count) => notifier.value = count);
    return notifier;
  }

  /// Once, before the chat is shown (e.g. in main()). Throws [ReplyzeConfigError] on a bad option.
  static void configure(ReplyzeOptions options) {
    resolveOptions(options);
    _options.value = options;
  }

  /// The options given to [configure], or null before it.
  static ReplyzeOptions? get options => _options.value;

  /// For the chat views: changes of [configure]'s options.
  static ValueListenable<ReplyzeOptions?> get optionsListenable => _options;

  /// Opens the chat full-screen (needs ReplyzeHost). Pass a context from
  /// under your Navigator so Android's back button closes the chat.
  static void show([BuildContext? context]) {
    final host = _host;
    if (host == null) {
      debugPrint(
          '[Replyze] show(): wrap your app in ReplyzeHost first (MaterialApp.builder).');
      return;
    }
    host.show(context);
  }

  /// Closes the full-screen chat. It keeps running, so replies count as
  /// unread.
  static void hide() => _host?.hide();

  /// Whether the full-screen chat is on screen.
  static bool get isVisible => _host?.isVisible ?? false;

  /// Who the user is. With identity verification, pass userId and the userHash from your server.
  static void identify(ReplyzeUser user) => session.identify(user);

  /// The user's custom data: keys matching a contact field fill it, others
  /// are kept as extra data; null removes. Text, numbers and booleans only.
  static void setData(Map<String, Object?> data) => session.setData(data);

  /// An event on the user's timeline in the inbox.
  static void pushEvent(String name, [Map<String, Object?>? data]) =>
      session.pushEvent(name, data);

  /// The chat's language ("de", "sr", "ar"...), over the device's.
  static void setLanguage(String language) => session.setLanguage(language);

  /// Opens the chat on a help article (needs the widget's Home or Help tab).
  static void openArticle(int id, [BuildContext? context]) {
    session.openArticle(id);
    show(context);
  }

  /// Sends a message as the user.
  static void sendMessage(String text) => session.sendMessage(text);

  /// The user signed out of your app: the chat forgets them.
  static void reset() => session.reset();

  /// Unread replies while the chat is closed (a ValueListenableBuilder fits).
  static ValueListenable<int> get unreadCount => _unread;

  /// Every reply from the AI or the team.
  static Stream<ReplyzeMessage> get messages => session.messages;

  /// load_timeout, help_unavailable, invalid_options...
  static Stream<ReplyzeError> get errors => session.errors;

  /// After identify(): whether the identity was verified.
  static Stream<bool> get identified => session.identified;

  /// Used by ReplyzeHost; the last one attached wins. Not for apps.
  static VoidCallback attachHost(ReplyzeHostHandle host) {
    _hosts.add(host);
    return () => _hosts.remove(host);
  }

  static ReplyzeHostHandle? get _host => _hosts.isEmpty ? null : _hosts.last;
}
