// ReplyzeChat and ReplyzeHost on a fake WebView platform: the page they
// load, the JavaScript channel the widget posts to, the commands they run
// in the page, and where links go. Widgets only (WidgetsApp), as the package
// itself uses no Material.

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:replyze_flutter/replyze_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class FakeWebViewPlatform extends WebViewPlatform {
  final List<FakeController> controllers = [];

  @override
  PlatformWebViewController createPlatformWebViewController(
      PlatformWebViewControllerCreationParams params) {
    final controller = FakeController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      FakeWebViewWidget(params);
}

class FakeController extends PlatformWebViewController {
  FakeController(super.params) : super.implementation();

  String? html;
  String? baseUrl;
  JavaScriptMode? javaScriptMode;
  final Map<String, JavaScriptChannelParams> channels = {};
  FakeNavigationDelegate? navigation;
  final List<String> scripts = [];

  /// The widget posts one event to the app, as widget.js does in the page.
  void post(String type, [Map<String, Object?> data = const {}]) {
    channels['ReplyzeFlutter']!.onMessageReceived(
      JavaScriptMessage(
          message: jsonEncode({'replyze': 1, 'type': type, 'data': data})),
    );
  }

  /// The commands the scripts hand to window.ReplyzeApp.receive(...).
  List<Map<String, dynamic>> get commands => scripts.map((script) {
        const start = 'window.ReplyzeApp.receive(';
        final from = script.indexOf(start) + start.length;
        final to = script.lastIndexOf(');}catch');
        return jsonDecode(script.substring(from, to)) as Map<String, dynamic>;
      }).toList();

  List<String> get commandNames =>
      commands.map((c) => c['cmd'] as String).toList();

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    this.html = html;
    this.baseUrl = baseUrl;
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    this.javaScriptMode = javaScriptMode;
  }

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> addJavaScriptChannel(
      JavaScriptChannelParams javaScriptChannelParams) async {
    channels[javaScriptChannelParams.name] = javaScriptChannelParams;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate handler) async {
    navigation = handler as FakeNavigationDelegate;
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    scripts.add(javaScript);
  }
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onNavigationRequest;

  Future<NavigationDecision> request(String url,
          {bool isMainFrame = true}) async =>
      onNavigationRequest!(
          NavigationRequest(url: url, isMainFrame: isMainFrame));

  @override
  Future<void> setOnNavigationRequest(
      NavigationRequestCallback onNavigationRequest) async {
    this.onNavigationRequest = onNavigationRequest;
  }
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class HomeStub extends StatelessWidget {
  const HomeStub({super.key});

  @override
  Widget build(BuildContext context) => const Text('home');
}

/// An app with a navigator (and Android's back button), without Material.
Widget app({required Widget home, TransitionBuilder? builder}) {
  return WidgetsApp(
    color: const Color(0xFF000000),
    builder: builder,
    home: home,
    pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder page) =>
        PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page(context),
    ),
  );
}

void main() {
  late FakeWebViewPlatform platform;

  setUp(() {
    platform = FakeWebViewPlatform();
    WebViewPlatform.instance = platform;
  });

  testWidgets('ReplyzeChat with a bad option reports it and loads nothing',
      (tester) async {
    final errors = <ReplyzeError>[];
    await tester.pumpWidget(app(
      home: ReplyzeChat(
          options: const ReplyzeOptions(widgetToken: ''), onError: errors.add),
    ));
    expect(errors.single.code, 'invalid_options');
    expect(platform.controllers, isEmpty);
  });

  testWidgets(
      'ReplyzeChat loads widget.js in in-app mode and talks over ReplyzeFlutter',
      (tester) async {
    var ready = 0;
    var closed = 0;
    final links = <String>[];
    await tester.pumpWidget(app(
      home: ReplyzeChat(
        options: const ReplyzeOptions(
            widgetToken: 'wgt_test',
            baseUrl: 'https://shop.example/app',
            language: 'de'),
        onReady: () => ready++,
        onClose: () => closed++,
        onOpenUrl: links.add,
      ),
    ));

    final web = platform.controllers.single;
    expect(web.baseUrl, 'https://shop.example/app');
    expect(web.javaScriptMode, JavaScriptMode.unrestricted);
    expect(web.html, contains('src="https://cdn.replyze.chat/widget.js"'));
    expect(web.html, contains('data-token="wgt_test"'));
    expect(web.html, contains('data-embedded="app"'));
    expect(web.html, contains('data-language="de"'));
    // The name the widget looks for (window.ReplyzeFlutter.postMessage).
    expect(web.channels.keys, ['ReplyzeFlutter']);
    expect(web.scripts, isEmpty);

    web.post('ready', {'version': 1});
    expect(ready, 1);
    expect(web.commandNames, ['open']);

    Replyze.openArticle(12);
    expect(web.commands.last, {
      'cmd': 'openArticle',
      'args': {'id': 12},
    });

    web.post('close');
    expect(closed, 1);

    // The chat page stays; links and other pages go to the app.
    expect(await web.navigation!.request('https://shop.example/app'),
        NavigationDecision.navigate);
    expect(await web.navigation!.request('about:blank'),
        NavigationDecision.navigate);
    expect(
        await web.navigation!
            .request('https://www.youtube.com/embed/x', isMainFrame: false),
        NavigationDecision.navigate);
    expect(await web.navigation!.request('https://shop.example/returns'),
        NavigationDecision.prevent);
    expect(await web.navigation!.request('javascript:alert(1)'),
        NavigationDecision.prevent);
    expect(links, ['https://shop.example/returns']);
  });

  testWidgets('ReplyzeChat shows a retry when the chat does not load',
      (tester) async {
    final errors = <String>[];
    await tester.pumpWidget(app(
      home: ReplyzeChat(
        options: const ReplyzeOptions(widgetToken: 'wgt_test'),
        onError: (error) => errors.add(error.code),
      ),
    ));
    expect(find.text("The chat couldn't load."), findsNothing);

    // No ready from the page within 20 seconds
    await tester.pump(const Duration(seconds: 21));
    expect(errors, ['load_timeout']);
    expect(find.text("The chat couldn't load."), findsOneWidget);

    // Try again: a fresh WebView, and the message goes once it is ready
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(platform.controllers, hasLength(2));
    platform.controllers.last.post('ready', {'version': 1});
    await tester.pump();
    expect(find.text("The chat couldn't load."), findsNothing);
  });

  testWidgets('a sign-out before the chat loaded reaches Try again',
      (tester) async {
    Replyze.identify(const ReplyzeUser(email: 'ana@shop.example'));
    Replyze.reset();
    await tester.pumpWidget(app(
      home: ReplyzeChat(
        options: const ReplyzeOptions(widgetToken: 'wgt_test'),
      ),
    ));
    await tester.pump(const Duration(seconds: 21));
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(platform.controllers, hasLength(2));
    platform.controllers.last.post('ready', {'version': 1});
    await tester.pump();
    expect(platform.controllers.first.commandNames, isEmpty);
    expect(platform.controllers.last.commandNames.first, 'reset');
    expect(platform.controllers.last.commandNames, isNot(contains('identify')));
    expect(Replyze.session.isResetPending, isFalse);
  });

  testWidgets(
      'ReplyzeHost preloads the chat hidden; show() opens it and back closes it',
      (tester) async {
    var closes = 0;
    await tester.pumpWidget(app(
      builder: (context, child) =>
          ReplyzeHost(onClose: () => closes++, child: child!),
      home: const HomeStub(),
    ));
    // Not configured yet: only the app.
    expect(platform.controllers, isEmpty);
    expect(find.text('home'), findsOneWidget);

    Replyze.configure(const ReplyzeOptions(widgetToken: 'wgt_test'));
    await tester.pump();
    final web = platform.controllers.single;
    expect(web.baseUrl, 'https://cdn.replyze.chat/in-app');

    web.post('ready', {'version': 1});
    expect(web.commandNames, ['setInsets', 'close']);
    expect(Replyze.isVisible, isFalse);

    web.post('unread', {'count': 2});
    expect(Replyze.unreadCount.value, 2);

    Replyze.show(tester.element(find.byType(HomeStub)));
    await tester.pumpAndSettle();
    expect(Replyze.isVisible, isTrue);
    expect(web.commandNames.last, 'open');

    // Android's back button pops the empty route Replyze.show() pushed.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(Replyze.isVisible, isFalse);
    expect(closes, 1);
    expect(web.commandNames.last, 'close');
    expect(find.text('home'), findsOneWidget);
  });
}
