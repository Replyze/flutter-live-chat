import 'package:material_ui/material_ui.dart';
import 'package:replyze_flutter/replyze_flutter.dart';

void main() {
  // Your widget's token (Settings → Integrations → Install widget)
  // and, when the widget has an allowed-domains list, a URL on one of those
  // domains.
  Replyze.configure(
    const ReplyzeOptions(
      widgetToken: 'wgt_your_widget_token',
      baseUrl: 'https://yourshop.example/app',
    ),
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Replyze example',
      // The full-screen chat Replyze.show() opens, over every screen
      builder: (context, child) => ReplyzeHost(child: child!),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    Replyze.messages.listen(
      (message) => debugPrint(
        'Reply from ${message.senderName ?? message.sender}: ${message.text}',
      ),
    );
  }

  void _signIn() {
    // userHash comes from YOUR server: HMAC-SHA256 of the user id, keyed with
    // the identity secret. Never put the identity secret in the app.
    Replyze.identify(
      const ReplyzeUser(
        userId: 'user_1234',
        email: 'ana@example.com',
        name: 'Ana',
        userHash: null,
      ),
    );
    Replyze.setData({'plan': 'pro', 'app_version': '3.2.0'});
    Replyze.pushEvent('Signed in');
    setState(() => _signedIn = true);
  }

  void _signOut() {
    Replyze.reset();
    setState(() => _signedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Shop')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: Replyze.unreadCount,
              builder: (context, unread, _) => FilledButton(
                onPressed: () => Replyze.show(context),
                child: Text(unread > 0 ? 'Support ($unread)' : 'Support'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Replyze.openArticle(12, context),
              child: const Text('How do returns work?'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SupportScreen()),
              ),
              child: const Text('Chat as a screen'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _signedIn ? _signOut : _signIn,
              child: Text(_signedIn ? 'Sign out' : 'Sign in as Ana'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chat as one of the app's own screens.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: SafeArea(
        top: false,
        child: ReplyzeChat(
          options: Replyze.options!.copyWith(showCloseButton: false),
        ),
      ),
    );
  }
}
