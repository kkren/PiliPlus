import 'package:PiliPlus/models/search/pgc.dart';
import 'package:PiliPlus/services/bili_roaming/config.dart';
import 'package:PiliPlus/utils/app_sign.dart';

/// Ports BiliRoamingApi.getAreaSearchBangumi/getThailandSearchBangumi from
/// sakarie9/BiliRoaming, revision 7c792dc8 (GPL-3.0).
abstract final class BiliRoamingSearch {
  static ({String path, Map<String, dynamic> params}) request({
    required BiliRoamingConfig config,
    required String keyword,
    required int page,
    bool movie = false,
    int pageSize = 20,
  }) {
    if (!BiliRoamingConfig.areas.containsKey(config.area) ||
        page < 1 ||
        pageSize < 1 ||
        pageSize > 50) {
      throw ArgumentError('Invalid roaming search parameters');
    }
    final international = config.area == 'th';
    // Android exposes one Southeast Asia bangumi tab, without a movie tab.
    if (international && movie) {
      throw ArgumentError('No Southeast Asia movie search');
    }
    final accessKey = config.accessKey;
    final params = <String, dynamic>{
      'keyword': keyword,
      'pn': page,
      'ps': pageSize,
      'type': movie ? '8' : '7',
      'fnval': 4048,
      'fnver': 0,
      'qn': 80,
      'device': 'android',
      'platform': 'android',
      'mobi_app': international ? 'bstar_a' : 'android',
      'build': international ? '1001310' : '6400000',
      if (!international) 'area': config.area,
      if (accessKey.isNotEmpty) 'access_key': accessKey,
      if (international) ...{
        's_locale': 'zh_SG',
        'c_locale': 'zh_SG',
        'sim_code': '52004',
        'lang': 'hans',
      },
    };
    // Public client signing identifiers, not user/account credentials.
    AppSign.appSign(
      params,
      appkey: international ? '7d089525d3611b1c' : '1d8b6e7d45233436',
      appsec: international
          ? 'acd495b248ec528c2eed1e862d393126'
          : '560c52ccd288fed045859ed18bffd973',
    );
    return (
      path: international
          ? '/intl/gateway/v2/app/search/type'
          : '/x/v2/search/type',
      params: params,
    );
  }

  static int? _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static String? _text(Object? value) => value is String ? value : null;

  static int? _seasonId(Map item) {
    final id = _int(item['season_id']);
    if (id != null && id > 0) return id;
    for (final key in ['uri', 'url', 'goto_url']) {
      final uri = Uri.tryParse(_text(item[key]) ?? '');
      if (uri == null) continue;
      // Parse IDs locally; never launch arbitrary server-provided links.
      final match = RegExp(r'/(?:season/|anime/|play/ss)(\d+)')
          .firstMatch(uri.path);
      if (match != null) return _int(match[1]);
    }
    if (['bangumi', 'pgc', 'media'].contains(item['goto'])) {
      return _int(item['param']);
    }
    return null;
  }

  static SearchPgcData parse(Map<String, dynamic> data) {
    final items = data['items'];
    if (items is! List) {
      throw const FormatException('Missing Android search items');
    }
    final list = <SearchPgcItemModel>[];
    for (final item in items) {
      if (item is! Map || item['goto'] == 'av' || item['goto'] == 'ad') {
        continue;
      }
      final seasonId = _seasonId(item);
      final title = _text(item['title']);
      if (seasonId == null || seasonId <= 0 || title == null || title.isEmpty) {
        continue;
      }
      final rating = num.tryParse(item['rating']?.toString() ?? '');
      final cover = _text(item['cover']);
      list.add(
        SearchPgcItemModel.fromJson({
          'title': title,
          'season_id': seasonId,
          'media_id': _int(item['media_id']),
          'media_type': _int(item['media_type']),
          'season_type': _int(item['season_type']),
          'season_type_name': _text(item['season_type_name']),
          'cover': cover != null && cover.startsWith('//')
              ? 'https:$cover'
              : cover,
          'areas': _text(item['area']) ?? _text(item['areas']),
          'styles': _text(item['styles']) ?? _text(item['style']),
          'pubtime': _int(item['ptime']) ?? _int(item['pubtime']),
          'index_show':
              _text(item['index_show']) ??
              _text(item['label']) ??
              _text(item['prompt']),
          'desc': _text(item['desc']),
          'cv': _text(item['cv']),
          'staff': _text(item['staff']),
          'is_selection': _int(item['is_selection']),
          'media_score': item['media_score'] is Map
              ? item['media_score']
              : rating != null && rating > 0
              ? {'score': rating, 'user_count': _int(item['vote'])}
              : null,
        }),
      );
    }
    return SearchPgcData(
      list: list,
      numResults: _int(data['total']) ?? _int(data['numResults']),
      totalPages: _int(data['pages']),
    );
  }
}
