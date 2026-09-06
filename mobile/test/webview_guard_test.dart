import 'package:flutter_test/flutter_test.dart';
import 'package:netwix/services/webview_guard.dart';

void main() {
  group('player WebView navigation allowlist', () {
    test('lets the embed and its own traffic through', () {
      expect(allowedInPlayerWebView('https://www.youtube.com/embed/abc'), isTrue);
      expect(allowedInPlayerWebView('https://youtube-nocookie.com/embed/abc'), isTrue);
      expect(allowedInPlayerWebView('https://r5---sn-x.googlevideo.com/videoplayback'), isTrue);
      expect(allowedInPlayerWebView('about:blank'), isTrue);
    });

    test('refuses everything else, including a host that merely ends in ours', () {
      expect(allowedInPlayerWebView('https://youtube.com.attacker.net/pay'), isFalse);
      expect(allowedInPlayerWebView('https://notyoutube.com/'), isFalse);
      expect(allowedInPlayerWebView('https://evil.example/phish'), isFalse);
    });

    test('refuses non-web schemes an ad could use to leave the app', () {
      expect(allowedInPlayerWebView('intent://scan/#Intent;end'), isFalse);
      expect(allowedInPlayerWebView('market://details?id=com.evil'), isFalse);
      expect(allowedInPlayerWebView('javascript:alert(1)'), isFalse);
    });
  });
}
