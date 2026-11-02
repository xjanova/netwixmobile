import '../state/member_state.dart';
import 'netwix_api.dart';

/// Reports only the current, advancing, foreground player. Server checks time/seek/concurrency.
class WatchRewardTracker {
  WatchRewardTracker({
    required this.api,
    required this.member,
    required this.contentId,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;
  final DateTime Function() _now;
  final NetwixApi api;
  final MemberState member;
  final int contentId;
  String? _token, _identity;
  int? _episode;
  bool _busy = false, _disposed = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void dispose() {
    _disposed = true;
  }

  Future<void> tick({
    required int episodeId,
    required double position,
    required bool active,
  }) async {
    if (_disposed ||
        _busy ||
        !active ||
        !member.isLoggedIn ||
        !position.isFinite ||
        _now().difference(_last).inSeconds < 15) {
      return;
    }
    _last = _now();
    _busy = true;
    final identity = member.member?.token;
    if (_episode != episodeId || _identity != identity) {
      _token = null;
      _episode = episodeId;
      _identity = identity;
    }
    try {
      final result = _token == null
          ? await api.startWatchReward(contentId, episodeId, position)
          : await api.beatWatchReward(_token!, position);
      if (_disposed || member.member?.token != identity) return;
      if (result == null) {
        _token = null;
        return;
      }
      if (result['token'] is String) _token = result['token'] as String;
      if (result['membership'] is Map) {
        member.applyMembershipState(
          (result['membership'] as Map).cast<String, dynamic>(),
        );
      }
      if (result['awards'] is List && (result['awards'] as List).isNotEmpty) {
        await member.refreshMissions();
      }
    } finally {
      _busy = false;
    }
  }
}
