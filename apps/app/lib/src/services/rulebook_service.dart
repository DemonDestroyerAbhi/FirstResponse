import 'dart:convert';

import 'package:core_rules/core_rules.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// A downloaded rulebook, kept between launches.
class CachedBundle {
  final String json;
  final String etag;

  /// Version of the rulebook bundled with the app build that downloaded
  /// this. A new app build ships newer rules, so older downloads are dropped.
  final String assetVersion;

  const CachedBundle({
    required this.json,
    required this.etag,
    required this.assetVersion,
  });
}

abstract interface class BundleCache {
  Future<CachedBundle?> read();
  Future<void> write(CachedBundle bundle);
  Future<void> clear();
}

/// Works on Android, iOS and web. Fine while bundles are tens of kilobytes;
/// move to a file once they reach megabytes.
class PrefsBundleCache implements BundleCache {
  static const _key = 'rulebook.cache';

  @override
  Future<CachedBundle?> read() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return CachedBundle(
      json: m['json'] as String,
      etag: m['etag'] as String,
      assetVersion: m['assetVersion'] as String,
    );
  }

  @override
  Future<void> write(CachedBundle b) async =>
      (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode({
          'json': b.json,
          'etag': b.etag,
          'assetVersion': b.assetVersion,
        }),
      );

  @override
  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}

class MemoryBundleCache implements BundleCache {
  CachedBundle? value;

  @override
  Future<CachedBundle?> read() async => value;

  @override
  Future<void> write(CachedBundle bundle) async => value = bundle;

  @override
  Future<void> clear() async => value = null;
}

/// Holds the engine in use and swaps in newer rules from the API.
///
/// Diagnosis never waits on the network: the app starts with the rules it
/// has and picks up new ones in the background.
class RulebookService extends ChangeNotifier {
  final BundleCache _cache;
  final ApiClient? api;
  final String _assetVersion;

  Engine _engine;
  String? _etag;

  RulebookService._(
    this._engine,
    this._assetVersion,
    this._cache,
    this.api,
    this._etag,
  );

  Engine get engine => _engine;

  /// Version of the rules in use.
  String get version => _engine.rulebook.version;

  /// Starts from a cached download if it belongs to this app build and is
  /// valid, otherwise from [assetJson], the bundle shipped in the app.
  static Future<RulebookService> load({
    required String assetJson,
    required BundleCache cache,
    ApiClient? api,
  }) async {
    final asset = _parse(assetJson)!;
    final cached = await cache.read();
    if (cached != null && cached.assetVersion == asset.version) {
      if (_parse(cached.json) case final book?) {
        return RulebookService._(
          Engine(book),
          asset.version,
          cache,
          api,
          cached.etag,
        );
      }
    }
    if (cached != null) await cache.clear();
    return RulebookService._(Engine(asset), asset.version, cache, api, null);
  }

  /// Downloads newer rules if the server has them. Returns whether the
  /// rules changed. Never throws: offline simply means no update.
  Future<bool> refresh() async {
    final api = this.api;
    if (api == null) return false;
    try {
      final download = await api.fetchRulebook(etag: _etag ?? '"$version"');
      if (download == null) return false;
      final book = _parse(download.json);
      // A bundle that fails validation is never used.
      if (book == null) return false;
      await _cache.write(
        CachedBundle(
          json: download.json,
          etag: download.etag,
          assetVersion: _assetVersion,
        ),
      );
      _etag = download.etag;
      if (book.version == version) return false;
      _engine = Engine(book);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Rulebook refresh failed: ${e.runtimeType}');
      return false;
    }
  }

  static Rulebook? _parse(String json) {
    try {
      return Rulebook.fromBundle(jsonDecode(json) as Map<String, dynamic>);
    } on Object catch (e) {
      debugPrint('Ignoring invalid rulebook: ${e.runtimeType}');
      return null;
    }
  }
}
