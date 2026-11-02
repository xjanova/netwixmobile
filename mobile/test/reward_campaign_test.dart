import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:netwix/models/member.dart';
import 'package:netwix/models/reward_campaign.dart';
import 'package:netwix/services/account_store.dart';
import 'package:netwix/services/auth_service.dart';
import 'package:netwix/services/netwix_api.dart';
import 'package:netwix/services/watch_reward_tracker.dart';
import 'package:netwix/state/member_state.dart';

class _Store implements AccountStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Auth implements AuthService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Api extends NetwixApi {
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>?> startWatchReward(int contentId, int episodeId, double position) async {
    calls.add('start:$contentId:$episodeId');
    return {'token': 'server-token'};
  }
  @override
  Future<Map<String, dynamic>?> beatWatchReward(String token, double position) async {
    calls.add('beat:$token');
    return {'membership': {'coins': 15}, 'awards': [{'coins': 15}]};
  }
}
class _Member extends MemberState {
  _Member(NetwixApi api) : super(_Store(), api, _Auth());
  bool signedIn = true;
  int applied = 0, refreshed = 0;
  @override
  bool get isLoggedIn => signedIn;
  @override
  Member? get member => signedIn ? Member.fromNetwixUser({'id': 1, 'name': 'Viewer'}, token: 'account-token') : null;
  @override
  void applyMembershipState(Map<String, dynamic> state) { applied = (state['coins'] as num).toInt(); }
  @override
  Future<void> refreshMissions() async { refreshed++; }
}

void main() {
  test('real API methods use authenticated campaign and heartbeat endpoints', () async {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: NetwixApi.baseUrl));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      final data = options.path == '/rewards/campaigns'
          ? {'items': [{'key':'daily','title':'เช็กอิน','description':'รับโบนัส','kind':'daily','target':1,'progress':0,'coins':3,'repeat':'daily','status':'available'}]}
          : options.path.endsWith('/start') ? {'token':'verified-token'} : {'membership':{'coins':5},'awards':[]};
      handler.resolve(Response(requestOptions: options, statusCode:200, data:{'success':true,'data':data}));
    }));
    final api = NetwixApi(dio: dio, token: 'account-token');
    expect((await api.fetchRewardCampaigns())!.single.coins, 3);
    expect((await api.startWatchReward(7, 20, 0))!['token'], 'verified-token');
    expect((await api.beatWatchReward('verified-token', 15))!['membership'], {'coins':5});
    expect(requests.map((r)=>r.path), ['/rewards/campaigns','/rewards/watch/start','/rewards/watch/beat']);
    expect(requests.every((r)=>r.headers['Authorization']=='Bearer account-token'), true);
    expect(requests[1].data, {'content_id':7,'episode_id':20,'position':0.0});
  });
  test('campaign cards use server progress, bonus and period instead of local constants', () {
    final c = RewardCampaign.fromJson({'key': 'explorer', 'title': 'พาสปอร์ต', 'description': 'ดู 3 หมวด',
      'kind': 'categories', 'target': 3, 'progress': 2, 'coins': 25, 'repeat': 'weekly', 'status': 'available'});
    expect(c.progress, 2); expect(c.target, 3); expect(c.coins, 25); expect(c.earned, false); expect(c.repeat, 'weekly');
  });

  test('only active current playback sends beats, applies server coins, and restarts on episode changes', () async {
    final api = _Api(); final member = _Member(api);
    var now = DateTime(2026, 11, 2, 12);
    final tracker = WatchRewardTracker(api: api, member: member, contentId: 9, clock: () => now);
    await tracker.tick(episodeId: 4, position: 0, active: false);
    expect(api.calls, isEmpty);
    await tracker.tick(episodeId: 4, position: 0, active: true);
    expect(api.calls, ['start:9:4']);
    await tracker.tick(episodeId: 4, position: 10, active: true);
    expect(api.calls.length, 1);
    now = now.add(const Duration(seconds: 15));
    await tracker.tick(episodeId: 4, position: 15, active: true);
    expect(api.calls.last, 'beat:server-token'); expect(member.applied, 15); expect(member.refreshed, 1);
    now = now.add(const Duration(seconds: 15));
    await tracker.tick(episodeId: 5, position: 0, active: true);
    expect(api.calls.last, 'start:9:5');
    tracker.dispose(); now = now.add(const Duration(seconds: 15));
    await tracker.tick(episodeId: 5, position: 15, active: true);
    expect(api.calls.length, 3);
  });

  test('guests never earn signed-in campaign coins', () async {
    final api = _Api(); final member = _Member(api)..signedIn = false;
    final tracker = WatchRewardTracker(api: api, member: member, contentId: 9);
    await tracker.tick(episodeId: 1, position: 300, active: true);
    expect(api.calls, isEmpty); expect(member.applied, 0);
  });
}
