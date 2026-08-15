/// A legal document (terms / privacy) as blocks, exactly as the website renders it.
///
/// The text is served from the server's single copy (App\Support\LegalDocs) rather than duplicated
/// here — legal wording that exists in two places drifts, and then the app and the website promise
/// people different things.
class LegalDoc {
  const LegalDoc({required this.title, required this.updated, required this.blocks});

  final String title;
  final String updated;
  final List<LegalBlock> blocks;

  factory LegalDoc.fromJson(Map<String, dynamic> j) => LegalDoc(
        title: (j['title'] ?? '').toString(),
        updated: (j['updated'] ?? '').toString(),
        blocks: (j['blocks'] is List)
            ? (j['blocks'] as List)
                .whereType<Map>()
                .map((m) => LegalBlock.fromJson(m.cast<String, dynamic>()))
                .toList()
            : const [],
      );
}

enum LegalBlockType { heading, paragraph, bullet }

class LegalBlock {
  const LegalBlock({required this.type, required this.text});

  final LegalBlockType type;
  final String text;

  factory LegalBlock.fromJson(Map<String, dynamic> j) => LegalBlock(
        type: switch ((j['type'] ?? '').toString()) {
          'heading' => LegalBlockType.heading,
          'bullet' => LegalBlockType.bullet,
          _ => LegalBlockType.paragraph,
        },
        text: (j['text'] ?? '').toString(),
      );
}
