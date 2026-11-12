# Replyze Flutter example

A Support button with the unread count, a help article, sign-in and sign-out, and the chat as one of the app's screens.

The repository has only `lib/` and `pubspec.yaml`; create the platform folders once with Flutter, then run it:

```sh
cd example
flutter create --platforms=android,ios .
flutter run
```

Put your widget token (Replyze: Settings → Integrations → Install widget) in `lib/main.dart` first, and a `baseUrl` on one of the widget's allowed domains if it has a list. For camera and photo attachments on iOS add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` to `ios/Runner/Info.plist`.
