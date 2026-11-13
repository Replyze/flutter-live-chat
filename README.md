<p align="center">
  <a href="https://replyze.chat/?utm_source=github&utm_medium=flutter-live-chat">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Replyze/.github/main/assets/logo-on-dark.png">
      <img src="https://raw.githubusercontent.com/Replyze/.github/main/assets/logo-on-light.png" alt="Replyze" height="48">
    </picture>
  </a>
</p>

# Live chat and AI support for Flutter apps

`replyze_flutter` puts the [Replyze](https://replyze.chat/?utm_source=github&utm_medium=flutter-live-chat) live chat and AI assistant inside your Flutter app, on iOS and Android. It is the same chat as the Replyze widget on your website, running in a WebView (`webview_flutter`): AI answers, your team's replies, help articles, the visitor's language, file attachments and identity verification all work, and new widget features reach your app without an app update.

**[Create a free account](https://client.replyze.chat/register?utm_source=github&utm_medium=flutter-live-chat&utm_content=cta-top)** · [Live demo](https://replyze.chat/?utm_source=github&utm_medium=flutter-live-chat&utm_content=live-demo) · [Docs](https://github.com/Replyze/replyze)

The live demo is replyze.chat itself: the chat bubble in the bottom-right corner is the widget this package runs in your app.

## Quickstart

1. **Get your widget token.** [Create a free account](https://client.replyze.chat/register?utm_source=github&utm_medium=flutter-live-chat&utm_content=quickstart), then copy the token (`wgt_...`) from **Settings → Integrations → Install widget**.
2. **Add the package** from GitHub to `pubspec.yaml`, then run `flutter pub get`:
   ```yaml
   dependencies:
     replyze_flutter:
       git:
         url: https://github.com/Replyze/flutter-live-chat.git
         ref: main
   ```
3. **Configure it and put `ReplyzeHost` around your app.** `Replyze.show(context)` opens the chat from any button:
   ```dart
   import 'package:material_ui/material_ui.dart';
   import 'package:replyze_flutter/replyze_flutter.dart';

   void main() {
     Replyze.configure(const ReplyzeOptions(widgetToken: 'wgt_YOUR_TOKEN'));
     runApp(
       MaterialApp(
         builder: (context, child) => ReplyzeHost(child: child!),
         home: const HomePage(),
       ),
     );
   }

   class HomePage extends StatelessWidget {
     const HomePage({super.key});

     @override
     Widget build(BuildContext context) {
       return Scaffold(
         body: Center(
           child: FilledButton(
             onPressed: () => Replyze.show(context),
             child: const Text('Chat with us'),
           ),
         ),
       );
     }
   }
   ```

Tap the button and the chat opens full screen. If your widget has an allowed-domains list, add `baseUrl` (see [Allowed domains](#allowed-domains)). The same app is [`example/lib/quickstart.dart`](example/lib/quickstart.dart). On Flutter older than 3.47, import `package:flutter/material.dart` instead of `material_ui`, as your app already does.

## Contents

[Install](#install) · [Open the chat](#open-the-chat) · [The chat as one of your screens](#the-chat-as-one-of-your-screens) · [Allowed domains](#allowed-domains) · [Who the user is](#who-the-user-is) · [API](#api) · [Notes](#notes) · [Example app](#example-app) · [Development](#development)

## Install

`replyze_flutter` is not on pub.dev yet. Add it from GitHub as in the Quickstart; pin a commit or tag with `ref:`. After the first pub.dev release (not yet), the install will be `flutter pub add replyze_flutter`.

Requirements:

- Flutter 3.19 or newer (Dart 3.3). The package uses only Flutter's widgets library, so it works in Material, Cupertino and other apps, before and after Flutter 3.47 moved Material into the `material_ui` package.
- The current `webview_flutter` needs Android `minSdkVersion` 24 and iOS 13. New Flutter projects already target these; in an older project set `minSdk = 24` in `android/app/build.gradle(.kts)` and `platform :ios, '13.0'` in `ios/Podfile`.
- For camera and photo attachments on iOS, add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` to `ios/Runner/Info.plist`.
- A Replyze account ([sign up](https://client.replyze.chat/register?utm_source=github&utm_medium=flutter-live-chat&utm_content=install)).

## Open the chat

`ReplyzeHost` loads the chat hidden when the app starts, so replies that arrive while it is closed count as unread (`preload: false` loads it on the first `show()`). `Replyze.show(context)` also puts an empty route on your navigator, so Android's back button closes the chat; the close button in the chat closes it too. Without a context, give `ReplyzeHost` your app's `navigatorKey`.

A Help button with the unread count:

```dart
ValueListenableBuilder<int>(
  valueListenable: Replyze.unreadCount,
  builder: (context, unread, _) => IconButton(
    onPressed: () => Replyze.show(context),
    icon: Badge(
      isLabelVisible: unread > 0,
      label: Text('$unread'),
      child: const Icon(Icons.support_agent),
    ),
  ),
)
```

## The chat as one of your screens

```dart
Scaffold(
  appBar: AppBar(title: const Text('Support')),
  body: ReplyzeChat(
    options: Replyze.options!.copyWith(showCloseButton: false),
  ),
)
```

## Allowed domains

The Replyze API checks the widget's allowed-domains list (**Settings → Chat Widget**) against the page's address. In an app that address is `baseUrl`; nothing is loaded from it. With an empty list any `baseUrl` works and you can leave it out. With domains on the list, set `baseUrl` to a URL on one of them:

```dart
Replyze.configure(const ReplyzeOptions(
  widgetToken: 'wgt_YOUR_TOKEN',
  baseUrl: 'https://yourshop.com/app',
));
```

The inbox shows `baseUrl` as the page the visitor wrote from, titled "In-app chat" (`pageTitle`). If the domain isn't allowed, the chat stays empty and, in debug builds, the log says `[Replyze] Widget blocked: this domain (...) is not in the widget's allowed-domains list`.

## Who the user is

```dart
// After sign-in. With identity verification on (Settings → Chat Widget →
// Identity), userHash is the HMAC-SHA256 of the user id (or, without one,
// of the email in lower case), keyed with the identity secret, as hex.
// Compute it on YOUR server. Never ship the identity secret in the app.
Replyze.identify(ReplyzeUser(
  userId: user.id,
  email: user.email,
  name: user.name,
  userHash: hashFromYourServer,
));

// On sign-out: the chat forgets the user and starts as a new visitor.
Replyze.reset();
```

A verified user is the same contact on every device and on your website, with their past conversations. `Replyze.identified` emits `true` when the hash matched. A hash that doesn't match changes nothing; in debug builds the log says `[Replyze] Failed to identify user`.

## API

| Call | What it does |
| --- | --- |
| `Replyze.configure(ReplyzeOptions(...))` | Once, before the chat is shown. Throws `ReplyzeConfigError` on a bad option. |
| `Replyze.show([context])`, `hide()`, `isVisible` | The full-screen chat (needs `ReplyzeHost`). |
| `Replyze.identify(ReplyzeUser(...))` | Who the user is. |
| `Replyze.setData({'plan': 'pro'})` | Custom data: keys matching a contact field fill it, others are kept as extra data, `null` removes. Text, numbers and booleans only. |
| `Replyze.pushEvent('Upgraded', {'plan': 'pro'})` | An event on the user's timeline in the inbox. |
| `Replyze.setLanguage('de')` | The chat's language, over the device's. |
| `Replyze.openArticle(12, context)` | Opens the chat on a help article (needs the widget's Home or Help tab). |
| `Replyze.sendMessage('...')` | Sends a message as the user. |
| `Replyze.reset()` | Sign-out. |
| `Replyze.unreadCount` | `ValueListenable<int>`: unread replies while the chat is closed. |
| `Replyze.messages` | `Stream<ReplyzeMessage>`: every reply from the AI or the team. |
| `Replyze.errors` | `Stream<ReplyzeError>`: `load_timeout`, `help_unavailable`, `invalid_options`. |
| `Replyze.identified` | `Stream<bool>`: whether `identify()` was verified. |

Calls made before the chat has loaded wait for it; who the user is, their data and the language are sent again whenever the WebView reloads.

`ReplyzeOptions`: `widgetToken` (required), `baseUrl`, `language`, `tracking` (visitor presence, default true), `showCloseButton` (default true), `pageTitle`, and `apiUrl`/`cdnUrl` for a staging or local backend only (plain http is allowed for localhost and 10.0.2.2).

`ReplyzeChat` also takes `visible` (while false the chat keeps running and replies count as unread), `insets`, `onClose`, `onReady`, `onMessage`, `onUnreadCountChange`, `onError`, `onOpenUrl` (default: url_launcher, outside the app), `errorBuilder` and `backgroundColor`. `ReplyzeHost` passes your app's safe-area padding to the chat itself.

The API reference is generated from the dartdoc comments in [`lib/`](lib/).

## Notes

- Links in the chat open outside the app (browser, mail, phone); the WebView never leaves the chat.
- On Android, attachments use the system file picker (`file_selector`).
- The strip under the status bar takes the widget's brand colour; use a light status bar style while the chat is open if it is dark.
- The chat runs while the app is in the foreground. Notifications for replies while the app is closed are not part of this package yet; [doc/push-notifications.md](doc/push-notifications.md) shows how to send them from your server with a webhook.

## How it works

The package builds a small HTML page that loads `widget.js` from Replyze's CDN with `data-embedded="app"` and loads it into a WebView at `baseUrl`. The page has no inline script and a content security policy that allows scripts from the CDN only. The widget posts its events to the `ReplyzeFlutter` JavaScript channel; the package sends commands with `runJavaScript`. Both sides speak the same small, versioned JSON bridge as the [React Native SDK](https://github.com/Replyze/react-native-live-chat).

## Example app

[`example/`](example/) has a Support button with the unread count, a help article, sign-in and sign-out, and the chat as one of the app's screens. See its [README](example/README.md).

## Development

```sh
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test           # the bridge (protocol, session) and the widgets on a fake WebView
dart pub publish --dry-run
```

CI runs these on Flutter stable and on Flutter 3.19 (the oldest the package allows), runs [pana](https://pub.dev/packages/pana) (the pub.dev score), and analyzes, tests and builds the example app for Android and iOS (the example needs Flutter 3.47 or newer). Releases: [RELEASING.md](RELEASING.md).

## Links

- [Replyze](https://replyze.chat/?utm_source=github&utm_medium=flutter-live-chat&utm_content=footer): AI customer support and live chat
- [Pricing](https://replyze.chat/pricing?utm_source=github&utm_medium=flutter-live-chat&utm_content=footer)
- [React Native version](https://github.com/Replyze/react-native-live-chat)
- [Changelog](CHANGELOG.md)

## License

MIT
