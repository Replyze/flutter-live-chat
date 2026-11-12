import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:replyze_flutter/src/protocol.dart';

/// The command a script hands to window.ReplyzeApp.receive(...).
Map<String, dynamic> commandIn(String script) {
  const start = 'window.ReplyzeApp.receive(';
  final from = script.indexOf(start) + start.length;
  final to = script.lastIndexOf(');}catch');
  return jsonDecode(script.substring(from, to)) as Map<String, dynamic>;
}

String event(String type, [Map<String, Object?>? data]) => jsonEncode({'replyze': 1, 'type': type, 'data': data});

void main() {
  group('resolveOptions', () {
    test('fills in the defaults', () {
      final o = resolveOptions(const ReplyzeOptions(widgetToken: ' wgt_abc123 '));
      expect(o.widgetToken, 'wgt_abc123');
      expect(o.baseUrl, defaultBaseUrl);
      expect(o.apiUrl, defaultApiUrl);
      expect(o.cdnUrl, defaultCdnUrl);
      expect(o.language, isNull);
      expect(o.tracking, isTrue);
      expect(o.showCloseButton, isTrue);
      expect(o.pageTitle, 'In-app chat');
    });

    test('keeps what the app sets and trims trailing slashes', () {
      final o = resolveOptions(const ReplyzeOptions(
        widgetToken: 'wgt_abc123',
        baseUrl: 'https://shop.example/app',
        apiUrl: 'https://api.shop.example/',
        language: 'pt-BR',
        tracking: false,
        showCloseButton: false,
        pageTitle: 'Shop app',
      ));
      expect(o.apiUrl, 'https://api.shop.example');
      expect(o.baseUrl, 'https://shop.example/app');
      expect(o.language, 'pt-BR');
      expect(o.tracking, isFalse);
      expect(o.pageTitle, 'Shop app');
    });

    for (final token in ['', 'x', 'wgt bad', 'wgt_<script>']) {
      test('refuses the token "$token"', () {
        expect(() => resolveOptions(ReplyzeOptions(widgetToken: token)), throwsA(isA<ReplyzeConfigError>()));
      });
    }

    test('refuses no options', () {
      expect(() => resolveOptions(null), throwsA(isA<ReplyzeConfigError>()));
    });

    test('refuses bad URLs and allows http only for a local backend', () {
      for (final url in ['http://shop.example', 'shop.example', 'javascript:alert(1)', 'https://u:p@api.example', 'https://cdn.example/"><script>']) {
        expect(() => resolveOptions(ReplyzeOptions(widgetToken: 'wgt_abc123', baseUrl: url)), throwsA(isA<ReplyzeConfigError>()), reason: url);
      }
      expect(resolveOptions(const ReplyzeOptions(widgetToken: 'wgt_abc123', apiUrl: 'http://10.0.2.2:8000')).apiUrl, 'http://10.0.2.2:8000');
    });

    test('refuses a language that is not a code', () {
      expect(() => resolveOptions(const ReplyzeOptions(widgetToken: 'wgt_abc123', language: 'german!')), throwsA(isA<ReplyzeConfigError>()));
    });
  });

  group('buildChatHtml', () {
    final html = buildChatHtml(resolveOptions(const ReplyzeOptions(
      widgetToken: 'wgt_abc123',
      baseUrl: 'https://shop.example/app',
      language: 'de',
      pageTitle: 'Shop "app" <b>',
    )));

    test('loads widget.js in in-app mode with data attributes', () {
      expect(
        html,
        contains('<script src="https://cdn.replyze.chat/widget.js" data-token="wgt_abc123" data-embedded="app" '
            'data-api-url="https://client.replyze.chat" data-language="de"></script>'),
      );
    });

    test('has one script, from the CDN, and a strict CSP', () {
      expect(RegExp(r'<script\b').allMatches(html).length, 1);
      final csp = RegExp(r'http-equiv="Content-Security-Policy" content="([^"]+)"').firstMatch(html)!.group(1)!;
      expect(csp, contains("default-src 'none'"));
      expect(csp, contains('script-src https://cdn.replyze.chat;'));
      expect(csp, isNot(contains('unsafe-eval')));
      expect(csp, isNot(contains('http:')));
    });

    test('escapes the page title and is safe-area aware', () {
      expect(html, contains('<title>Shop &quot;app&quot; &lt;b&gt;</title>'));
      expect(html, contains('viewport-fit=cover'));
    });

    test('switches tracking and close buttons off by attribute', () {
      final off = buildChatHtml(resolveOptions(const ReplyzeOptions(widgetToken: 'wgt_abc123', tracking: false, showCloseButton: false)));
      expect(off, contains('data-tracking="false"'));
      expect(off, contains('data-close-button="false"'));
    });
  });

  group('commandScript', () {
    test('carries the command as JSON, line separators escaped', () {
      final text = 'He said "hi" </script> ${String.fromCharCode(0x2028)} \\ \'';
      final script = commandScript({
        'cmd': 'sendMessage',
        'args': {'text': text},
      });
      expect(script, isNot(contains(String.fromCharCode(0x2028))));
      expect(commandIn(script), {
        'cmd': 'sendMessage',
        'args': {'text': text},
      });
    });
  });

  group('parseEvent', () {
    test('reads each event', () {
      expect((parseEvent(event('ready', {'version': 1})) as ReadyEvent).version, 1);
      expect(parseEvent(event('close')), isA<CloseEvent>());
      expect((parseEvent(event('unread', {'count': 3})) as UnreadEvent).count, 3);
      expect((parseEvent(event('identified', {'verified': true})) as IdentifiedEvent).verified, isTrue);
      expect((parseEvent(event('openUrl', {'url': 'https://shop.example/terms'})) as OpenUrlEvent).url, 'https://shop.example/terms');
      expect((parseEvent(event('error', {'code': 'help_unavailable', 'message': 'x'})) as ErrorEvent).error, const ReplyzeError('help_unavailable', 'x'));
      final message = parseEvent(event('message', {'id': '9', 'text': 'Hi', 'sender': 'agent', 'senderName': 'Ana', 'createdAt': null, 'type': 'text'})) as MessageEvent;
      expect(message.message, const ReplyzeMessage(id: '9', text: 'Hi', sender: 'agent', senderName: 'Ana'));
    });

    test('cleans up odd values', () {
      expect((parseEvent(event('unread', {'count': -4})) as UnreadEvent).count, 0);
      expect((parseEvent(event('unread', {'count': 'many'})) as UnreadEvent).count, 0);
      final message = parseEvent(event('message', {'id': 9, 'sender': 'visitor'})) as MessageEvent;
      expect(message.message, const ReplyzeMessage(id: '', text: '', sender: 'bot'));
    });

    test('ignores anything that is not a Replyze event, and links the app must not open', () {
      expect(parseEvent('not json'), isNull);
      expect(parseEvent(jsonEncode({'type': 'close'})), isNull);
      expect(parseEvent(jsonEncode({'replyze': 2, 'type': 'close'})), isNull);
      expect(parseEvent(event('somethingElse')), isNull);
      expect(parseEvent(null), isNull);
      expect(parseEvent(event('openUrl', {'url': 'javascript:alert(1)'})), isNull);
      expect(parseEvent(event('openUrl', {'url': 'file:///etc/passwd'})), isNull);
    });
  });

  group('links and navigation', () {
    test('opens web, mail, phone and sms links outside', () {
      for (final url in ['https://a.example', 'mailto:a@b.example', 'tel:+381601234567', 'sms:+38160']) {
        expect(isExternalUrl(url), isTrue, reason: url);
      }
      for (final url in ['javascript:void(0)', 'file:///x', 'myapp://x', '//a.example']) {
        expect(isExternalUrl(url), isFalse, reason: url);
      }
    });

    test('lets the WebView load only the chat page', () {
      const base = 'https://shop.example/app';
      expect(isChatPage('https://shop.example/app/', base), isTrue);
      expect(isChatPage('https://shop.example/app#x', base), isTrue);
      expect(isChatPage('about:blank', base), isTrue);
      expect(isChatPage('https://shop.example/', base), isFalse);
      expect(isChatPage('https://evil.example/app', base), isFalse);
    });
  });

  group('commands from the app', () {
    test('maps the user to the widget identify', () {
      expect(identifyCommand(const ReplyzeUser(email: ' ana@shop.example ', name: 'Ana', userId: 42, userHash: 'abc')), {
        'cmd': 'identify',
        'args': {'email': 'ana@shop.example', 'name': 'Ana', 'user_id': 42, 'user_hash': 'abc'},
      });
      expect(identifyCommand(const ReplyzeUser(userHash: 'abc')), isNull);
    });

    test('rounds insets and keeps them positive', () {
      expect(insetsCommand(const ReplyzeInsets(top: 47.4, bottom: -3)), {
        'cmd': 'setInsets',
        'args': {'top': 47, 'bottom': 0},
      });
    });
  });
}
