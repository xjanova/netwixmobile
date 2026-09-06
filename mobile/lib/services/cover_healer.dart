import 'netwix_api.dart';

/// Repairs broken title covers from what viewers actually see.
///
/// The website has pinged `heal-cover` since a card's poster first failed to load (2026-07-16); the
/// app never did. So an app viewer staring at a broken cover got the branded fallback and the server
/// learned nothing — the title never reached the admin's missing-covers queue, and a dead hotlink
/// stayed indistinguishable from a live one in the database. This is the app's half of that signal.
///
/// Bounded on purpose. One scroll can fail twenty cards at once, so:
///  - one attempt per title per app run — [_result] remembers the null answers too, which are the
///    common case (nothing recoverable) and must never be retried on every rebuild;
///  - at most [_maxConcurrent] reports in flight;
///  - a hard [_maxPerRun] ceiling, so scrolling a catalogue of dead hotlinks cannot turn into a
///    flood that the server's per-IP throttle has to absorb.
///
/// A dropped report is not a loss: the next launch reports it again.
class CoverHealer {
  CoverHealer._();

  static final CoverHealer instance = CoverHealer._();

  static const int _maxConcurrent = 2;
  static const int _maxPerRun = 40;

  NetwixApi? _api;
  final Map<int, Future<String?>> _inFlight = {};
  final Map<int, String?> _result = {};
  int _started = 0;
  int _active = 0;

  void configure(NetwixApi api) => _api = api;

  /// Report a cover that failed to load. Resolves to the repaired URL, or null when there is nothing
  /// to swap in — which stays silent in the UI, because the fallback is already what's on screen.
  Future<String?> heal(int contentId) {
    if (_result.containsKey(contentId)) return Future.value(_result[contentId]);

    final running = _inFlight[contentId];
    if (running != null) return running;

    final api = _api;
    if (api == null || contentId <= 0) return Future.value(null);
    if (_started >= _maxPerRun || _active >= _maxConcurrent) return Future.value(null);

    _started++;
    _active++;
    final f = api.healCover(contentId).then((url) {
      _result[contentId] = url;
      return url;
    }).whenComplete(() {
      _active--;
      _inFlight.remove(contentId);
    });
    _inFlight[contentId] = f;

    return f;
  }
}
