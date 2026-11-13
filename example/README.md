# Replyze Flutter example

A Support button with the unread count, a help article, sign-in and sign-out, and the chat as one of the app's screens (`lib/main.dart`). `lib/quickstart.dart` is the README's Quickstart as a whole app.

The repository has only `lib/`, `test/` and `pubspec.yaml`; create the platform folders once with Flutter, then run it:

```sh
cd example
flutter create --platforms=android,ios --project-name replyze_flutter_example .
flutter run                        # the full example
flutter run -t lib/quickstart.dart # the Quickstart
```

Put your widget token (Replyze: Settings → Integrations → Install widget) in `lib/main.dart` first, and a `baseUrl` on one of the widget's allowed domains if it has a list. For camera and photo attachments on iOS add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` to `ios/Runner/Info.plist`.

CI builds this app for Android (`flutter build apk --debug`) and iOS (`flutter build ios --debug --no-codesign`) on every push.
