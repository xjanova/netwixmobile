import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/content.dart';
import '../services/catalog_db.dart';
import '../services/netwix_api.dart';

/// Catalog filter chips → NetWix content types. `anime` is a server-side
/// category (its items keep type movie/series but come from the anime source),
/// so selecting it fetches `/titles?type=anime` rather than filtering locally.
enum CatalogFilter { all, series, movie, vertical, anime }

extension CatalogFilterX on CatalogFilter {
  String get th => switch (this) {
        CatalogFilter.all => 'ทั้งหมด',
        CatalogFilter.series => 'ซีรีส์',
        CatalogFilter.movie => 'ภาพยนตร์',
        CatalogFilter.vertical => 'แนวตั้ง',
        CatalogFilter.anime => 'อนิเมะ',
      };
  String get en => switch (this) {
        CatalogFilter.all => 'All',
        CatalogFilter.series => 'Series',
        CatalogFilter.movie => 'Movies',
        CatalogFilter.vertical => 'Vertical',
        CatalogFilter.anime => 'Anime',
      };
  String? get type => switch (this) {
        CatalogFilter.all => null,
        CatalogFilter.series => 'series',
        CatalogFilter.movie => 'movie',
        CatalogFilter.vertical => 'vertical',
        CatalogFilter.anime => 'anime',
      };
}

/// Catalog sourced entirely from NetWix (`/api/app/*`). Cache-first: paints the
/// SQLite-cached list instantly, then refreshes from NetWix.
class CatalogState extends ChangeNotifier {
  CatalogState(this._api, this._db);
  final NetwixApi _api;
  final CatalogDb _db;

  List<Content> _all = [];
  Content? _hero;
  List<NetwixRail> _rails = const [];
  // Server-fetched results for each non-'all' category (anime/movie/…), cached
  // so re-tapping a chip doesn't refetch.
  final Map<CatalogFilter, List<Content>> _byFilter = {};
  bool loading = false;
  bool filterLoading = false;
  String? error;
  String _query = '';
  CatalogFilter filter = CatalogFilter.all;

  bool get isEmpty => _all.isEmpty;
  int get total => _all.length;
  String get query => _query;
  Content? get hero => _hero;

  /// The web's curated home rails (trending + genre rails incl. anime).
  List<NetwixRail> get rails => _rails;

  Future<void> load({bool force = false}) async {
    if (loading) return;
    if (_all.isNotEmpty && !force) return;
    loading = true;
    error = null;
    if (force) _byFilter.clear(); // drop cached category results on manual refresh
    notifyListeners();

    if (_all.isEmpty) {
      try {
        final cached = await _db.getAllContent();
        if (cached.isNotEmpty) {
          _all = cached;
          notifyListeners();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('catalog cache read: $e');
      }
    }

    try {
      final home = await _api.fetchHome();
      final titles = await _api.fetchTitles(per: 48);
      _hero = home?.hero;
      if (home != null && home.rails.isNotEmpty) _rails = home.rails;
      if (titles.isNotEmpty) {
        _all = titles;
        unawaited(_db.upsertContent(titles));
        error = null;
      } else if (_all.isEmpty) {
        error = 'โหลดคลังหนังไม่สำเร็จ ตรวจสอบการเชื่อมต่อ';
      }
    } catch (e) {
      if (_all.isEmpty) error = 'โหลดคลังหนังไม่สำเร็จ ตรวจสอบการเชื่อมต่อ';
      if (kDebugMode) debugPrint('catalog load: $e');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setQuery(String q) {
    _query = q.trim();
    notifyListeners();
  }

  /// Switch category. 'all' shows the cached full list; any other category is
  /// fetched from the server (`/titles?type=…`) because e.g. anime items don't
  /// carry a distinguishing `type` on each record — the server owns that set.
  Future<void> setFilter(CatalogFilter f) async {
    if (filter == f) return;
    filter = f;
    notifyListeners();
    if (f == CatalogFilter.all || _byFilter.containsKey(f)) return; // cached / no fetch
    filterLoading = true;
    notifyListeners();
    try {
      _byFilter[f] = await _api.fetchTitles(type: f.type, per: 60);
    } catch (e) {
      _byFilter[f] = const [];
      if (kDebugMode) debugPrint('catalog setFilter(${f.name}): $e');
    } finally {
      filterLoading = false;
      notifyListeners();
    }
  }

  /// The items backing the current category (before search is applied).
  List<Content> get _source =>
      filter == CatalogFilter.all ? _all : (_byFilter[filter] ?? const []);

  List<Content> get visible {
    Iterable<Content> list = _source;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((c) =>
          c.title.toLowerCase().contains(q) || c.synopsis.toLowerCase().contains(q));
    }
    return list.toList();
  }

  List<Content> get featured {
    final copy = List<Content>.from(_all)..sort((a, b) => b.views.compareTo(a.views));
    return copy.take(10).toList();
  }
}
