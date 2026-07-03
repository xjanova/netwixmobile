import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../state/catalog_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/poster_card.dart';

/// Explore · สำรวจ — full searchable catalog grid.
class CatalogGridScreen extends StatefulWidget {
  const CatalogGridScreen({super.key});

  @override
  State<CatalogGridScreen> createState() => _CatalogGridScreenState();
}

class _CatalogGridScreenState extends State<CatalogGridScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CatalogState>().load();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<AppState>().l;
    final catalog = context.watch<CatalogState>();
    final list = catalog.visible;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Text(l.bi('สำรวจ', 'Explore'), style: AppTheme.display(21, weight: FontWeight.w700)),
                  const Spacer(),
                  if (catalog.total > 0)
                    Text('${catalog.total} ${l.pick('เรื่อง', 'titles')}',
                        style: AppTheme.body(12, color: T.textFaint)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0x10FFFFFF),
                  borderRadius: BorderRadius.circular(T.rPill),
                  border: Border.all(color: T.hairline),
                ),
                child: Row(children: [
                  const Icon(Icons.search_rounded, size: 18, color: T.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onChanged: catalog.setQuery,
                      style: AppTheme.body(13.5, color: T.textPrimary),
                      cursorColor: T.accent,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: l.bi('ค้นหาซีรีส์ หนัง อนิเมะ', 'Search series, movies, anime…'),
                        hintStyle: AppTheme.body(13.5, color: T.textMuted),
                      ),
                    ),
                  ),
                  if (catalog.query.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _controller.clear();
                        catalog.setQuery('');
                      },
                      child: const Icon(Icons.close_rounded, size: 18, color: T.textMuted),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final f in CatalogFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _chip(catalog, f, l.isTh ? f.th : f.en),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: (catalog.loading || catalog.filterLoading) && list.isEmpty
              ? const Center(child: CircularProgressIndicator(color: T.accent))
              : catalog.error != null && catalog.isEmpty
                  ? _error(l, catalog)
                  : list.isEmpty
                      ? Center(
                          child: Text(l.pick('ไม่พบผลลัพธ์', 'No results'),
                              style: AppTheme.body(14, color: T.textMuted)))
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.5,
                          ),
                          itemCount: list.length,
                          itemBuilder: (_, i) => PortraitPosterCard(content: list[i], width: double.infinity),
                        ),
        ),
      ],
    );
  }

  Widget _chip(CatalogState catalog, CatalogFilter f, String label) {
    final active = catalog.filter == f;
    return GestureDetector(
      onTap: () => catalog.setFilter(f),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: active ? T.accentGradient : null,
          color: active ? null : const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(T.rPill),
          border: Border.all(color: active ? Colors.transparent : T.hairline),
        ),
        child: Text(label,
            style: AppTheme.body(12.5,
                weight: FontWeight.w600, color: active ? T.onAccent : T.textSecondary)),
      ),
    );
  }

  Widget _error(L10n l, CatalogState catalog) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 40, color: T.textFaint),
              const SizedBox(height: 12),
              Text(catalog.error ?? '', textAlign: TextAlign.center, style: AppTheme.body(13, color: T.textMuted)),
              const SizedBox(height: 16),
              SizedBox(
                width: 160,
                child: AccentButton(label: l.pick('ลองใหม่', 'Retry'), height: 46, onPressed: () => catalog.load(force: true)),
              ),
            ],
          ),
        ),
      );
}
