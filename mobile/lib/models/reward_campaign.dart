/// Server-authoritative bonuses shared across the web and every signed-in device.
class RewardCampaign {
  const RewardCampaign({
    required this.key,
    required this.title,
    required this.description,
    required this.kind,
    required this.target,
    required this.progress,
    required this.coins,
    required this.repeat,
    required this.earned,
  });
  final String key, title, description, kind, repeat;
  final int target, progress, coins;
  final bool earned;

  factory RewardCampaign.fromJson(Map<String, dynamic> j) => RewardCampaign(
    key: '${j['key']}',
    title: '${j['title']}',
    description: '${j['description']}',
    kind: '${j['kind']}',
    target: (j['target'] as num).toInt(),
    progress: (j['progress'] as num).toInt(),
    coins: (j['coins'] as num).toInt(),
    repeat: '${j['repeat']}',
    earned: j['status'] == 'earned',
  );
}
