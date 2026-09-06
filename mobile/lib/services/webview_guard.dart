import 'package:webview_flutter/webview_flutter.dart';

/// Keeps a WebView on the page we opened it for.
///
/// Both of ours host a YouTube embed — a pre-roll creative and a watch-to-earn mission — and both
/// run with JavaScript unrestricted, because the IFrame API needs it. Without a delegate, anything
/// inside that frame can navigate the view somewhere else entirely and the viewer has no address
/// bar to notice with; a creative reaches us through the self-serve ad marketplace, so "the content
/// is ours" is not an assumption worth making. Player traffic is allowed, everything else is
/// refused rather than followed.
///
/// A click-through belongs in the phone's browser (url_launcher), never in here.
NavigationDelegate playerOnlyNavigation() => NavigationDelegate(
      onNavigationRequest: (request) => allowedInPlayerWebView(request.url)
          ? NavigationDecision.navigate
          : NavigationDecision.prevent,
    );

const _hosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'youtube-nocookie.com',
  'www.youtube-nocookie.com',
  'youtu.be',
  'www.google.com', // the embed's consent/redirect hop
  'googlevideo.com',
};

/// Public for the test that pins it: an allowlist matched with `endsWith` is exactly where
/// `youtube.com.attacker.net` gets in if the dot is ever dropped.
bool allowedInPlayerWebView(String url) {
  if (url == 'about:blank' || url.startsWith('data:')) return true;

  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) return false;

  final host = uri.host.toLowerCase();

  return _hosts.contains(host) || _hosts.any((h) => host.endsWith('.$h'));
}
