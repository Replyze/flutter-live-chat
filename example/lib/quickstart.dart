// The Quickstart from the README, as a whole app:
// flutter run -t lib/quickstart.dart
import 'package:flutter/material.dart';
import 'package:replyze_flutter/replyze_flutter.dart';

void main() {
  Replyze.configure(const ReplyzeOptions(widgetToken: 'wgt_YOUR_TOKEN'));
  runApp(MaterialApp(
    builder: (context, child) => ReplyzeHost(child: child!),
    home: const HomePage(),
  ));
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
