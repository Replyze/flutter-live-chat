/// The Replyze live chat and AI assistant inside your Flutter app, on iOS
/// and Android.
///
/// Configure it once, put [ReplyzeHost] around your app's navigator, and
/// open the chat with [Replyze.show]:
///
/// ```dart
/// Replyze.configure(const ReplyzeOptions(widgetToken: 'wgt_...'));
/// MaterialApp(builder: (context, child) => ReplyzeHost(child: child!));
/// Replyze.show(context);
/// ```
///
/// [ReplyzeChat] is the chat as one of your own screens. [Replyze.identify]
/// says who the user is, [Replyze.unreadCount] counts unread replies.
library;

export 'src/protocol.dart'
    show
        ReplyzeConfigError,
        ReplyzeError,
        ReplyzeInsets,
        ReplyzeMessage,
        ReplyzeOptions,
        ReplyzeUser,
        replyzeProtocolVersion;
export 'src/replyze.dart' show Replyze, ReplyzeHostHandle;
export 'src/replyze_chat.dart' show ReplyzeChat, ReplyzeChatState;
export 'src/replyze_host.dart' show ReplyzeHost;
export 'src/session.dart' show ReplyzeConnection, ReplyzeConnectionHandlers, ReplyzeSession;
