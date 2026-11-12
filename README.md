<p align="center">
  <a href="https://replyze.chat/?utm_source=github&utm_medium=flutter-live-chat">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Replyze/.github/main/assets/logo-on-dark.png">
      <img src="https://raw.githubusercontent.com/Replyze/.github/main/assets/logo-on-light.png" alt="Replyze" height="48">
    </picture>
  </a>
</p>

# Live chat and AI support for Flutter apps

`replyze_flutter` puts the [Replyze](https://replyze.chat/?utm_source=github&utm_medium=flutter-live-chat) live chat and AI assistant inside your Flutter app, on iOS and Android.

It is the same chat as the Replyze widget on your website, running in a WebView (`webview_flutter`): AI answers, your team's replies, help articles, the visitor's language, file attachments and identity verification all work, and new widget features arrive without an app update.

## Install

`replyze_flutter` is coming to pub.dev. Until then, add it from GitHub in `pubspec.yaml`:

```yaml
dependencies:
  replyze_flutter:
    git:
      url: https://github.com/Replyze/flutter-live-chat.git
      ref: main
```

Then run `flutter pub get`. You need a Replyze account ([sign up](https://client.replyze.chat/register?utm_source=github&utm_medium=flutter-live-chat)).

Android: `minSdkVersion` 21 or higher (webview_flutter's). iOS 12 or higher. For camera and photo attachments on iOS add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` to `ios/Runner/Info.plist`.

## Quick start

```dart
import 'package:replyze_flutter/replyze_flutter.dart';

void main() {
  Replyze.configure(const ReplyzeOptions(
    widgetToken: 'wgt_...', // Settings → Integrations → Install widget
    baseUrl: 'https://yourshop.com/app', // see "Allowed domains" below
  ));
  runApp(MaterialApp(
    // the full-screen chat Replyze.show() opens, over every screen
    builder: (context, child) => ReplyzeHost(child: child!),
    home: const HomePage(),
  ));
}

// anywhere under your navigator
FilledButton(onPressed: () => Replyze.show(context), child: const Text('Help'));
```

`ReplyzeHost` loads the chat hidden when the app starts, so replies that arrive while it is closed count as unread (`preload: false` loads it on the first `show()`). `Replyze.show(context)` also puts an empty route on your navigator, so Android's back button closes the chat; the close button in the chat closes it too. Without a context, give `ReplyzeHost` your app's `navigatorKey`.

### Unread count

```dart
ValueListenableBuilder<int>(
  valueListenable: Replyze.unreadCount,
  builder: (context, unread, _) => Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.support_agent)),
)
```

### The chat as one of your screens

```dart
Scaffold(
  appBar: AppBar(title: const Text('Support')),
  body: ReplyzeChat(options: Replyze.options!.copyWith(showCloseButton: false)),
)
```

## Allowed domains

The Replyze API checks the widget's allowed-domains list (Settings → Chat Widget) against the page's address. In an app that address is `baseUrl`; nothing is loaded from it. With an empty list any `baseUrl` works and you can leave it out. With domains on the list, set `baseUrl` to a URL on one of them, e.g. `https://yourshop.com/app`. The inbox shows it as the page the visitor wrote from, titled "In-app chat" (`pageTitle`). If the domain isn't allowed the chat stays empty and, in debug builds, the log says `[Replyze] Widget blocked: this domain (...) is not in the widget's allowed-domains list`.

## Who the user is

```dart
// After sign-in. With identity verification on (Settings → Chat Widget →
// Identity), userHash = HMAC-SHA256(userId, identity secret), hex,
// computed on YOUR server. Never ship the identity secret in the app.
Replyze.identify(ReplyzeUser(userId: user.id, email: user.email, name: user.name, userHash: hashFromYourServer));

// On sign-out: the chat forgets the user.
Replyze.reset();
```

## API

| Call | What it does |
| --- | --- |
| `Replyze.configure(ReplyzeOptions(...))` | Once, before the chat is shown. Throws `ReplyzeConfigError` on a bad option. |
| `Replyze.show([context])`, `hide()`, `isVisible` | The full-screen chat (needs `ReplyzeHost`). |
| `Replyze.identify(ReplyzeUser(...))` | Who the user is. |
| `Replyze.setData({'plan': 'pro'})` | Custom data: keys matching a contact field fill it, others are kept as extra data, `null` removes. |
| `Replyze.pushEvent('Upgraded', {'plan': 'pro'})` | An event on the user's timeline in the inbox. |
| `Replyze.setLanguage('de')` | The chat's language. |
| `Replyze.openArticle(12, context)` | Opens the chat on a help article (needs the widget's Home or Help tab). |
| `Replyze.sendMessage('...')` | Sends a message as the user. |
| `Replyze.reset()` | Sign-out. |
| `Replyze.unreadCount` | `ValueListenable<int>`. |
| `Replyze.messages` | `Stream<ReplyzeMessage>`: every reply from the AI or the team. |
| `Replyze.errors` | `Stream<ReplyzeError>`: `load_timeout`, `help_unavailable`, `invalid_options`. |
| `Replyze.identified` | `Stream<bool>`: whether `identify()` was verified. |

Calls made before the chat has loaded wait for it; who the user is, their data and the language are sent again whenever the WebView reloads.

`ReplyzeOptions`: `widgetToken` (required), `baseUrl`, `language`, `tracking` (visitor presence, default true), `showCloseButton` (default true), `pageTitle`, and `apiUrl`/`cdnUrl` for a staging or local backend only.

`ReplyzeChat` also takes `visible` (while false the chat keeps running and replies count as unread), `insets`, `onClose`, `onReady`, `onMessage`, `onUnreadCountChange`, `onError`, `onOpenUrl` (default: url_launcher, outside the app) and `errorBuilder`.

## Notes

- Links in the chat open outside the app (browser, mail, phone); the WebView never leaves the chat.
- On Android, attachments use the system file picker (`file_selector`).
- The strip under the status bar takes the widget's brand colour; use a light status bar style while the chat is open if it is dark.
- The chat runs while the app is in the foreground. Notifications for replies while the app is closed are not part of this package yet; [doc/push-notifications.md](doc/push-notifications.md) shows how to send them from your server with a webhook.

## Example app

[`example/`](example/) has a Support button with the unread count, a help article, sign-in and sign-out, and the chat as one of the app's screens. See its README.

## Development

```sh
flutter pub get
flutter analyze
flutter test   # the bridge (protocol and session), in plain Dart
```

## Links

- [Replyze](https://replyze.chat/?utm_source=github&utm_medium=flutter-live-chat): AI customer support and live chat
- [Pricing](https://replyze.chat/pricing?utm_source=github&utm_medium=flutter-live-chat)
- [React Native version](https://github.com/Replyze/react-native-live-chat)

## License

MIT
