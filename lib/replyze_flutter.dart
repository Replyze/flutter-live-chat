/// The Replyze live chat and AI assistant inside your Flutter app.
///
/// ```dart
/// Replyze.configure(const ReplyzeOptions(widgetToken: 'wgt_...'));
/// MaterialApp(builder: (context, child) => ReplyzeHost(child: child!));
/// Replyze.show(context);
/// ```
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
