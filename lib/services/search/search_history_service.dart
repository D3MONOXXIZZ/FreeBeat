import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service managing persistent recent search queries for FreeBeat.
/// Keeps up to [maxHistoryItems] distinct queries in LRU order.
class SearchHistoryService extends ChangeNotifier {
  SearchHistoryService({this.maxHistoryItems = 15}) {
    _loadHistory();
  }

  final int maxHistoryItems;
  static const String _prefKey = 'freebeat_search_history';

  List<String> _history = [];
  List<String> get history => List.unmodifiable(_history);

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _history = prefs.getStringList(_prefKey) ?? [];
      notifyListeners();
    } catch (_) {}
  }

  /// Adds [query] to recent searches, moving it to the top.
  Future<void> addQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    _history.removeWhere((q) => q.toLowerCase() == trimmed.toLowerCase());
    _history.insert(0, trimmed);

    if (_history.length > maxHistoryItems) {
      _history = _history.sublist(0, maxHistoryItems);
    }

    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKey, _history);
    } catch (_) {}
  }

  /// Removes a single query from history.
  Future<void> removeQuery(String query) async {
    _history.removeWhere((q) => q.toLowerCase() == query.toLowerCase());
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKey, _history);
    } catch (_) {}
  }

  /// Clears the entire search history.
  Future<void> clearHistory() async {
    _history.clear();
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (_) {}
  }
}

final searchHistoryServiceProvider =
    ChangeNotifierProvider<SearchHistoryService>((ref) {
  return SearchHistoryService();
});
