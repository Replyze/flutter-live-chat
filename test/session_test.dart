import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:replyze_flutter/src/protocol.dart';
import 'package:replyze_flutter/src/session.dart';

/// A fake WebView: records the commands its scripts carry.
class FakeWebView {
  final List<Map<String, dynamic>> commands = [];

  void inject(String script) {
    const start = 'window.ReplyzeApp.receive(';
    final from = script.indexOf(start) + start.length;
    final to = script.lastIndexOf(');}catch');
    commands
        .add(jsonDecode(script.substring(from, to)) as Map<String, dynamic>);
  }

  List<String> get names => commands.map((c) => c['cmd'] as String).toList();
}

String event(String type, [Map<String, Object?>? data]) =>
    jsonEncode({'replyze': 1, 'type': type, 'data': data});

void main() {
  late List<String> logs;
  late ReplyzeSession session;

  setUp(() {
    logs = [];
    session = ReplyzeSession(
        readyTimeout: const Duration(milliseconds: 50),
        log: (_, message) => logs.add(message));
  });

  test('holds commands until ready, then sends them in the right order', () {
    final web = FakeWebView();
    final connection = session.connect(web.inject);
    connection.setInsets(const ReplyzeInsets(top: 47, bottom: 34));
    connection.setVisible(true);
    session.pushEvent('Opened app', {'build': 12});
    session.identify(
        const ReplyzeUser(email: 'ana@shop.example', userId: 7, userHash: 'h'));
    session.setLanguage('de');
    session.setData({'plan': 'pro'});
    session.setData({'seats': 3, 'plan': 'team'});
    session.openArticle(12);
    expect(web.commands, isEmpty);

    connection.receive(event('ready', {'version': 1}));

    expect(connection.isReady, isTrue);
    expect(web.commands, [
      {
        'cmd': 'setInsets',
        'args': {'top': 47, 'bottom': 34},
      },
      {
        'cmd': 'setLanguage',
        'args': {'language': 'de'},
      },
      {
        'cmd': 'identify',
        'args': {'email': 'ana@shop.example', 'user_id': 7, 'user_hash': 'h'},
      },
      {
        'cmd': 'setData',
        'args': {
          'data': {'plan': 'team', 'seats': 3},
        },
      },
      {'cmd': 'open'},
      {
        'cmd': 'pushEvent',
        'args': {
          'name': 'Opened app',
          'data': {'build': 12},
        },
      },
      {
        'cmd': 'openArticle',
        'args': {'id': 12},
      },
    ]);
  });

  test('makes a reloaded WebView the same user again', () {
    final web = FakeWebView();
    final connection = session.connect(web.inject);
    connection.receive(event('ready'));
    session.identify(const ReplyzeUser(userId: 'u1', userHash: 'h1'));
    session.setLanguage('sr');
    web.commands.clear();

    connection.reloaded();
    session.pushEvent('Later');
    connection.receive(event('ready'));

    expect(web.names, ['setLanguage', 'identify', 'close', 'pushEvent']);
  });

  test('a reset asked for before ready goes first, and forgets the old user',
      () {
    final web = FakeWebView();
    final connection = session.connect(web.inject);
    session.identify(const ReplyzeUser(email: 'old@shop.example'));
    session.setData({'plan': 'pro'});
    session.pushEvent('Old user event');
    session.reset();
    session.identify(const ReplyzeUser(email: 'new@shop.example'));
    connection.receive(event('ready'));
    expect(web.commands, [
      {'cmd': 'reset'},
      {
        'cmd': 'identify',
        'args': {'email': 'new@shop.example'},
      },
      {'cmd': 'close'},
    ]);
  });

  test('keeps the unread count and reports only changes', () async {
    final counts = <int>[];
    final subscription = session.unreadCountChanges.listen(counts.add);
    final connection = session.connect(FakeWebView().inject);
    connection.receive(event('ready'));
    connection.receive(event('unread', {'count': 1}));
    connection.receive(event('unread', {'count': 1}));
    connection.receive(event('unread', {'count': 2}));
    expect(session.unreadCount, 2);
    session.reset();
    expect(session.unreadCount, 0);
    await subscription.cancel();
    expect(counts, [1, 2, 0]);
  });

  test('passes messages, close, links and errors to the app', () {
    final closes = <String>[];
    final urls = <String>[];
    final handlerErrors = <ReplyzeError>[];
    final messages = <ReplyzeMessage>[];
    final errors = <ReplyzeError>[];
    session.messages.listen(messages.add);
    session.errors.listen(errors.add);
    final connection = session.connect(
      FakeWebView().inject,
      ReplyzeConnectionHandlers(
          onClose: () => closes.add('close'),
          onOpenUrl: urls.add,
          onError: handlerErrors.add),
    );
    connection.receive(event('ready'));
    connection.receive(
        event('message', {'id': '5', 'text': 'Hello', 'sender': 'agent'}));
    connection.receive(event('close'));
    connection
        .receive(event('openUrl', {'url': 'https://shop.example/returns'}));
    connection.receive(event('openUrl', {'url': 'javascript:alert(1)'}));
    connection.receive(
        event('error', {'code': 'help_unavailable', 'message': 'no help'}));
    connection.receive(
        event('log', {'level': 'warn', 'message': '[Replyze] Widget blocked'}));

    expect(messages,
        [const ReplyzeMessage(id: '5', text: 'Hello', sender: 'agent')]);
    expect(closes, ['close']);
    expect(urls, ['https://shop.example/returns']);
    expect(handlerErrors, [const ReplyzeError('help_unavailable', 'no help')]);
    expect(errors, [const ReplyzeError('help_unavailable', 'no help')]);
    expect(logs, ['[Replyze] Widget blocked']);
  });

  test('reports a chat that never loads, but not one that did', () async {
    final slow = <ReplyzeError>[];
    final fast = <ReplyzeError>[];
    session.connect(
        FakeWebView().inject, ReplyzeConnectionHandlers(onError: slow.add));
    final ok = session.connect(
        FakeWebView().inject, ReplyzeConnectionHandlers(onError: fast.add));
    ok.receive(event('ready'));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(slow.single.code, 'load_timeout');
    expect(fast, isEmpty);
  });

  test('sends to every chat view, and not to one that is gone', () {
    final a = FakeWebView();
    final b = FakeWebView();
    final ca = session.connect(a.inject);
    final cb = session.connect(b.inject);
    ca.receive(event('ready'));
    cb.receive(event('ready'));
    cb.disconnect();
    expect(session.connectionCount, 1);
    session.pushEvent('Both?');
    expect(a.names, contains('pushEvent'));
    expect(b.names, isNot(contains('pushEvent')));
  });

  test('checks what the app passes', () {
    final web = FakeWebView();
    session.connect(web.inject).receive(event('ready'));
    web.commands.clear();
    session.identify(const ReplyzeUser());
    session.pushEvent('   ');
    session.openArticle(0);
    session.sendMessage('  ');
    session.setData({
      'nested': {'no': true},
      'ok': 'yes',
    });
    expect(web.commands, [
      {
        'cmd': 'setData',
        'args': {
          'data': {'ok': 'yes'},
        },
      },
    ]);
    expect(logs.length, greaterThanOrEqualTo(3));
  });
}
