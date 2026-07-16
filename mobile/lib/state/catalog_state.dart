import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/content.dart';
import '../services/catalog_db.dart';
import '../services/netwix_api.dart';

/// An Explore/Home category chip. Backed by a media [type] (series|movie|
/// vertical), a [genre] slug, the [anime] bucket, or 'all'. The five base chips
/// are fixed; genre chips are appended from the server taxonomy (`/genres`) so
/// the app's categories always match the web.
class CatalogCategory {
  const CatalogCategory({
    required this.id,
    required this.th,
    required this.en,
    this.type,
    this.genre,
    this.scope,
    this.anime = false,
  });

  /// 'all' | 'series' | 'movie' | 'vertical' | 'anime' | 'g:{slug}'
  final String id;
  final String th;
  final String en;
  final String? type; // media type
  final String? genre; // genre slug
  final String? scope; // main category: 'notanime' keeps anime out of movies/series (matches the web)
  final bool anime; // anime/cartoon bucket (server maps to scope=anime)

  bool get isAll => id == 'all';
  String label(bool isTh) => isTh ? th : en;

  static const all = CatalogCategory(id: 'all', th: 'ทั้งหมด', en: 'All');

  /// Fixed chips shown before the server genre list. movie/series exclude anime (scope=notanime) so
  /// they match the web's /movies and /series pages instead of mixing anime in.
  static const base = <CatalogCategory>[
    all,
    CatalogCategory(id: 'series', th: 'ซีรีส์', en: 'Series', type: 'series', scope: 'notanime'),
    CatalogCategory(id: 'movie', th: 'ภาพยนตร์', en: 'Movies', type: 'movie', scope: 'notanime'),
    CatalogCategory(id: 'vertical', th: 'แนวตั้ง', en: 'Vertical', type: 'vertical'),
    CatalogCategory(id: 'anime', th: 'อนิเมะ', en: 'Anime', anime: true),
  ];
}

/// Catalog sourced entirely from NetWix (`/api/app/*`). Cache-first, and
/// **paginated**: each category (and the search view) accumulates pages as the
/// user scrolls, and search hits the server so it finds the whole 2500+ catalog
/// — not just the first page held on-device.
class CatalogState extends ChangeNotifier {
  CatalogState(this._api, this._db);
  final NetwixApi _api;
  final CatalogDb _db;

  static const int _perPage = 30;
  static const String _searchKey = 'search';

  Content? _hero;
  List<NetwixRail> _rails = const [];
  List<CatalogCategory> _genreCats = const [];

  // Paginated feeds keyed by view id ('all' | 'series' | 'g:slug' | 'anime' |
  // 'search'); page cursor + has-more tracked per key.
  final Map<String, List<Content>> _items = {};
  final Map<String, int> _pages = {};
  final Map<String, bool> _more = {};
  int _totalAll = 0;

  bool loading = false; // initial catalog load
  bool filterLoading = false; // switching category / running a fresh search
  bool loadingMore = false; // appending the next page
  String? error;
  String _query = '';
  Timer? _searchDebounce;
  CatalogCategory _current = CatalogCategory.all;

  bool get isEmpty => (_items['all'] ?? const []).isEmpty;
  int get total => _totalAll > 0 ? _totalAll : (_items['all'] ?? const []).length;
  String get query => _query;
  Content? get hero => _hero;

  /// The web's curated home rails (trending + genre rails incl. an anime rail).
  List<NetwixRail> get rails => _rails;

  List<CatalogCategory> get categories => [...CatalogCategory.base, ..._genreCats];
  CatalogCategory get current => _current;

  /// The key of the currently displayed feed: the search bucket while a query
  /// is active, otherwise the selected category.
  String get _key => _query.isNotEmpty ? _searchKey : _current.id;

  /// The items to render right now (search results or the active category).
  List<Content> get visible => _items[_key] ?? const [];

  /// Whether the current feed has more pages to lazy-load.
  bool get hasMore => _more[_key] ?? false;

  List<Content> get featured {
    final all = List<Content>.from(_items['all'] ?? const [])
      ..sort((a, b) => b.views.compareTo(a.views));
    return all.take(10).toList();
  }

  /// "มาใหม่" — newest catalogue additions. Backend ids are monotonically
  /// increasing on import, so id desc ≈ recency without needing a created_at.
  List<Content> get newest {
    final all = List<Content>.from(_items['all'] ?? const [])
      ..sort((a, b) => b.id.compareTo(a.id));
    return all.take(18).toList();
  }

  /// "ดาวเยอะ" — highest-rated titles (rated ones only, then popularity).
  List<Content> get topRated {
    final all = (_items['all'] ?? const <Content>[]).where((c) => c.rating > 0).toList()
      ..sort((a, b) {
        final r = b.rating.compareTo(a.rating);
        return r != 0 ? r : b.views.compareTo(a.views);
      });
    return all.take(18).toList();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> load({bool force = false}) async {
    if (loading) return;
    if (_items.containsKey('all') && !force) return;
    loading = true;
    error = null;
    if (force) {
      _items.clear();
      _pages.clear();
      _more.clear();
    }
    notifyListeners();

    if (!_items.containsKey('all')) {
      try {
        final cached = await _db.getAllContent();
        if (cached.isNotEmpty) {
          _items['all'] = cached;
          notifyListeners();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('catalog cache read: $e');
      }
    }

    try {
      final home = await _api.fetchHome();
      final genres = await _api.fetchGenres();
      final first = await _api.fetchTitlesPage(per: _perPage, page: 1);
      _hero = home?.hero;
      if (home != null && home.rails.isNotEmpty) _rails = home.rails;
      if (genres.isNotEmpty) {
        _genreCats = genres
            .where((g) => !g.isAnime)
            .map((g) => CatalogCategory(
                  id: 'g:${g.slug}',
                  th: g.name,
                  en: g.nameEn ?? g.name,
                  genre: g.slug,
                ))
            .toList();
      }
      if (first.items.isNotEmpty) {
        _items['all'] = first.items;
        _pages['all'] = 1;
        _more['all'] = first.hasMore;
        _totalAll = first.total;
        unawaited(_db.upsertContent(first.items));
        error = null;
      } else if ((_items['all'] ?? const []).isEmpty) {
        error = 'โหลดคลังหนังไม่สำเร็จ ตรวจสอบการเชื่อมต่อ';
      }
    } catch (e) {
      if ((_items['all'] ?? const []).isEmpty) {
        error = 'โหลดคลังหนังไม่สำเร็จ ตรวจสอบการเชื่อมต่อ';
      }
      if (kDebugMode) debugPrint('catalog load: $e');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Debounced server search. Empty query returns to the category view.
  void setQuery(String q) {
    q = q.trim();
    if (q == _query) return;
    _query = q;
    _searchDebounce?.cancel();
    // Fresh query → drop the previous search page cache.
    _items.remove(_searchKey);
    _pages.remove(_searchKey);
    _more.remove(_searchKey);
    if (q.isEmpty) {
      filterLoading = false;
      notifyListeners();
      return;
    }
    filterLoading = true;
    notifyListeners();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_loadSearch(reset: true));
    });
  }

  /// Switch category (exits search). Loads the first page if not cached.
  Future<void> setCategory(CatalogCategory cat) async {
    if (_current.id == cat.id && _query.isEmpty) return;
    _current = cat;
    if (_query.isNotEmpty) {
      _query = '';
      _searchDebounce?.cancel();
      _items.remove(_searchKey);
      _pages.remove(_searchKey);
      _more.remove(_searchKey);
    }
    notifyListeners();
    if (_items.containsKey(cat.id)) return; // already loaded
    filterLoading = true;
    notifyListeners();
    await _loadCategory(cat, reset: true);
    filterLoading = false;
    notifyListeners();
  }

  /// Lazy-load the next page of the current feed (category or search).
  Future<void> loadMore() async {
    if (loadingMore || !hasMore) return;
    loadingMore = true;
    notifyListeners();
    if (_query.isNotEmpty) {
      await _loadSearch();
    } else {
      await _loadCategory(_current);
    }
    loadingMore = false;
    notifyListeners();
  }

  Future<void> _loadCategory(CatalogCategory cat, {bool reset = false}) async {
    final key = cat.id;
    final next = reset ? 1 : (_pages[key] ?? 0) + 1;
    try {
      final res = await _api.fetchTitlesPage(
          type: cat.type, genre: cat.genre, scope: cat.scope, anime: cat.anime, per: _perPage, page: next);
      final base = reset ? const <Content>[] : (_items[key] ?? const <Content>[]);
      _items[key] = [...base, ...res.items];
      _pages[key] = next;
      _more[key] = res.hasMore;
    } catch (e) {
      if (kDebugMode) debugPrint('catalog _loadCategory($key): $e');
    }
  }

  Future<void> _loadSearch({bool reset = false}) async {
    final q = _query;
    if (q.isEmpty) return;
    final next = reset ? 1 : (_pages[_searchKey] ?? 0) + 1;
    try {
      final res = await _api.searchPage(q, page: next);
      if (q != _query) return; // query changed mid-flight — drop stale results
      final base = reset ? const <Content>[] : (_items[_searchKey] ?? const <Content>[]);
      _items[_searchKey] = [...base, ...res.items];
      _pages[_searchKey] = next;
      _more[_searchKey] = res.hasMore;
    } catch (e) {
      if (kDebugMode) debugPrint('catalog _loadSearch: $e');
    } finally {
      if (reset) filterLoading = false;
      notifyListeners();
    }
  }
}
