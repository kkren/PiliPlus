import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliPlus/models/common/search/search_type.dart';
import 'package:PiliPlus/models/search/pgc.dart';
import 'package:PiliPlus/models/search/search_tab.dart';
import 'package:PiliPlus/services/bili_roaming/search.dart';
import 'package:crypto/crypto.dart';

import 'package:PiliPlus/http/bili_roaming.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/services/bili_roaming/config.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply, {this.status = 200});
  final Object? reply;
  final int status;
  RequestOptions? request;
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(reply),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) => closed = true;
}

String _accountKey() => 'test+key&private';

const config = BiliRoamingConfig(
  enabled: true,
  server: 'https://roaming.example/proxy/',
  area: 'tw',
  accessKeyProvider: _accountKey,
);

Map<String, dynamic> stream() => {
  'quality': 80,
  'timelength': 60000,
  'is_preview': 1,
  'is_drm': true,
  'dash': {
    'duration': 60,
    'minBufferTime': 1.5,
    'video': [
      {'id': 80, 'base_url': 'https://media.example/v.m4s'},
    ],
    'audio': [
      {'id': 30280, 'baseUrl': 'https://media.example/a.m4s'},
    ],
  },
};

BiliRoamingHttp _client(_Adapter adapter, [BiliRoamingConfig cfg = config]) =>
    BiliRoamingHttp(cfg, client: Dio()..httpClientAdapter = adapter);

void main() {
  test(
    'new PGC playback envelope preserves direct playback and region fallback',
    () {
      const config = BiliRoamingConfig(enabled: true);
      expect(
        config.shouldProxyPlayback({
          'code': 0,
          'data': {
            'video_info': {'quality': 80},
          },
        }),
        isFalse,
      );
      expect(
        config.shouldProxyPlayback({
          'code': 0,
          'data': {
            'not_playable_reason': {'code': -10403, 'message': '区域限制'},
          },
        }),
        isTrue,
      );
    },
  );

  test('DRM playback keeps the official fallback unless region-restricted', () {
    const config = BiliRoamingConfig(enabled: true);
    for (final envelope in ['data', 'result']) {
      expect(
        config.shouldProxyPlayback({
          'code': 0,
          envelope: {
            'arc': {'is_drm': true},
          },
        }),
        isFalse,
      );
      expect(
        config.shouldProxyPlayback({
          'code': 0,
          envelope: {
            'arc': {'is_drm': true},
            'not_playable_reason': {'code': -10403, 'message': '区域限制'},
          },
        }),
        isTrue,
      );
    }
  });

  test('automatic key follows refresh, account changes, and logout', () async {
    String? accountKey = 'first-key';
    final cfg = BiliRoamingConfig(
      enabled: true,
      server: config.server,
      accessKeyProvider: () => accountKey,
    );
    for (final next in ['first-key', 'refreshed-key', null, '  ']) {
      accountKey = next;
      for (final search in [false, true]) {
        final adapter = _Adapter({
          'code': 0,
          'data': search ? {'items': [], 'pages': 0} : stream(),
        });
        final api = _client(adapter, cfg);
        final result = search
            ? await api.search(keyword: 'test', page: 1)
            : await api.videoUrl(cid: 2, qn: 80);
        expect(result.isSuccess, isTrue);
        final query = adapter.request!.uri.queryParameters;
        if ((next?.trim() ?? '').isEmpty) {
          expect(query, isNot(contains('access_key')));
        } else {
          expect(query['access_key'], next);
        }
      }
    }
  });
  test(
    'signed search resolves the account key only once per request',
    () async {
      var reads = 0;
      final cfg = BiliRoamingConfig(
        enabled: true,
        server: config.server,
        accessKeyProvider: () => 'key-${++reads}',
      );
      final adapter = _Adapter({
        'code': 0,
        'data': {'items': [], 'pages': 0},
      });
      await _client(adapter, cfg).search(keyword: 'test', page: 1);
      expect(reads, 1);
      expect(adapter.request!.uri.queryParameters['access_key'], 'key-1');
    },
  );

  group('Android regional search', () {
    test(
      'regional selection survives a new keyword and falls back if disabled',
      () {
        final tabs = SearchResultTab.forConfig(config);
        expect(
          SearchResultTab.initialIndex(
            tabs,
            SearchType.media_bangumi.index,
            roamingArea: 'tw',
          ),
          SearchType.actives.length,
        );
        expect(
          SearchResultTab.initialIndex(
            tabs,
            SearchType.media_ft.index,
            roamingArea: 'tw',
          ),
          SearchType.actives.length + 1,
        );
        final normal = SearchResultTab.forConfig(const BiliRoamingConfig());
        expect(
          SearchResultTab.initialIndex(
            normal,
            SearchType.media_bangumi.index,
            roamingArea: 'tw',
          ),
          SearchType.media_bangumi.index,
        );
        expect(SearchResultTab.initialIndex(normal, 999), 0);
      },
    );

    test(
      'regional tabs are separate from the unchanged normal search tabs',
      () {
        final tabs = SearchResultTab.forConfig(config);
        expect(
          tabs.take(SearchType.actives.length).map((tab) => tab.type),
          SearchType.actives,
        );
        expect(
          tabs
              .take(SearchType.actives.length)
              .every((tab) => tab.roaming == null),
          isTrue,
        );
        expect(tabs.skip(SearchType.actives.length).map((tab) => tab.label), [
          '台湾番剧',
          '台湾影视',
        ]);
        expect(tabs.last.roaming, same(config));
        for (final cfg in [
          const BiliRoamingConfig(),
          const BiliRoamingConfig(enabled: true),
        ]) {
          expect(
            SearchResultTab.forConfig(cfg).length,
            SearchType.actives.length,
          );
        }
        final thTabs = SearchResultTab.forConfig(
          const BiliRoamingConfig(
            enabled: true,
            server: 'https://example.com',
            area: 'th',
          ),
        );
        expect(thTabs.length, SearchType.actives.length + 1);
        expect(thTabs.last.label, '东南亚番剧');
      },
    );

    test('Android cards preserve highlights, ratings, IDs, and pagination', () {
      final data = BiliRoamingSearch.parse({
        'total': '42',
        'pages': '3',
        'items': [
          {
            'goto': 'bangumi',
            'season_id': '44467',
            'title': '<em class="keyword">虚構</em>推理 &amp; S2',
            'cover': '//i.example/cover.jpg',
            'rating': '9.8',
            'vote': 100,
            'ptime': '1673107200',
            'area': '日本',
            'styles': '奇幻',
            'label': '全12话',
          },
          {
            'goto': 'bangumi',
            'uri': 'bstar://bangumi/season/1234',
            'title': 'International',
          },
          {'goto': 'pgc', 'param': '5678', 'title': 'Film'},
          {'goto': 'av', 'param': '9876', 'title': 'Unrelated video'},
          {'goto': 'ad', 'season_id': 1, 'title': 'Ad'},
          {'title': 'Section header'},
        ],
      });
      expect(data.numResults, 42);
      expect(data.totalPages, 3);
      expect(data.list!.map((e) => e.seasonId), [44467, 1234, 5678]);
      final item = data.list!.first;
      expect(item.title.first, (isEm: true, text: '虚構'));
      expect(item.title.map((e) => e.text).join(), '虚構推理 & S2');
      expect(item.mediaScore!['score'], 9.8);
      expect(item.cover, 'https://i.example/cover.jpg');
      expect(item.pubtime, 1673107200);
      expect(item.indexShow, '全12话');
    });

    test('existing Web PGC model still parses normal search results', () {
      final data = SearchPgcData.fromJson({
        'numResults': 1,
        'result': [
          {
            'season_id': 10,
            'title': 'Normal result',
            'media_score': {'score': 9.5},
          },
        ],
      });
      expect(data.list!.single.seasonId, 10);
      expect(data.list!.single.mediaScore!['score'], 9.5);
      expect(data.totalPages, isNull);
    });

    test('HK TW and CN use signed Android search type 7 or 8', () async {
      for (final area in ['hk', 'tw', 'cn']) {
        for (final movie in [false, true]) {
          final cfg = BiliRoamingConfig(
            enabled: true,
            server: config.server,
            area: area,
            accessKeyProvider: _accountKey,
            sendHeaders: false,
          );
          final adapter = _Adapter({
            'code': 0,
            'data': {'items': [], 'pages': 3},
          });
          final result = await _client(
            adapter,
            cfg,
          ).search(keyword: '虚構 推理+&', page: 2, movie: movie);
          expect(result.isSuccess, isTrue);
          final request = adapter.request!;
          expect(request.uri.path, '/proxy/x/v2/search/type');
          final query = request.uri.queryParameters;
          expect(query['type'], movie ? '8' : '7');
          expect(query['pn'], '2');
          expect(query['ps'], '20');
          expect(query['area'], area);
          expect(query['build'], '6400000');
          expect(query['mobi_app'], 'android');
          expect(query['appkey'], '1d8b6e7d45233436');
          expect(query['access_key'], config.accessKey);
          expect(query['keyword'], '虚構 推理+&');
          expect(query, isNot(contains('search_type')));
          expect(query, isNot(contains('w_rid')));
          expect(request.headers['platform-from-biliroaming'], 'android');
          expect(
            request.headers.keys.map((e) => e.toLowerCase()),
            isNot(contains('cookie')),
          );
          final sorted = query.keys.where((e) => e != 'sign').toList()..sort();
          final signedQuery = sorted
              .map(
                (key) =>
                    '${Uri.encodeComponent(key)}=${Uri.encodeComponent(query[key]!)}',
              )
              .join('&');
          expect(
            query['sign'],
            md5
                .convert(
                  utf8.encode(
                    '$signedQuery'
                    '560c52ccd288fed045859ed18bffd973',
                  ),
                )
                .toString(),
          );
          expect(result.data.totalPages, 3);
        }
      }
    });

    test('Southeast Asia uses the Android international endpoint and profile', () async {
      const cfg = BiliRoamingConfig(
        enabled: true,
        server: 'https://example.com',
        area: 'th',
      );
      final adapter = _Adapter({
        'code': 0,
        'data': {
          'items': [
            {
              'uri': 'bstar://bangumi/season/1234',
              'title': 'International title',
            },
          ],
          'pages': 1,
        },
      });
      final result = await _client(
        adapter,
        cfg,
      ).search(keyword: 'test', page: 1);
      expect(result.data.list!.single.seasonId, 1234);
      expect(adapter.request!.uri.path, '/intl/gateway/v2/app/search/type');
      final params = adapter.request!.uri.queryParameters;
      expect(params['appkey'], '7d089525d3611b1c');
      expect(params['mobi_app'], 'bstar_a');
      expect(params['build'], '1001310');
      expect(params['s_locale'], 'zh_SG');
      expect(params['c_locale'], 'zh_SG');
      expect(params['sim_code'], '52004');
      expect(params['lang'], 'hans');
      expect(params, isNot(contains('area')));
      expect(params, isNot(contains('access_key')));
      final sorted = params.keys.where((e) => e != 'sign').toList()..sort();
      final signedQuery = sorted
          .map(
            (key) =>
                '${Uri.encodeComponent(key)}=${Uri.encodeComponent(params[key]!)}',
          )
          .join('&');
      expect(
        params['sign'],
        md5
            .convert(
              utf8.encode(
                '$signedQuery'
                'acd495b248ec528c2eed1e862d393126',
              ),
            )
            .toString(),
      );
    });

    test('disabled and unsupported searches never send a request', () async {
      for (final cfg in [
        const BiliRoamingConfig(),
        const BiliRoamingConfig(
          enabled: true,
          server: 'https://example.com',
          area: 'th',
        ),
      ]) {
        final adapter = _Adapter({});
        final result = await _client(
          adapter,
          cfg,
        ).search(keyword: 'test', page: 1, movie: true);
        expect(result, isA<Error>());
        expect(adapter.request, isNull);
      }
    });

    test(
      'malformed results fail, and server errors do not expose the key',
      () async {
        for (final payload in [
          {
            'code': 0,
            'data': {'items': 'invalid'},
          },
          {'code': -1, 'message': config.accessKey},
        ]) {
          final result = await _client(_Adapter(payload))
              .search(keyword: 'test', page: 1);
          expect(result, isA<Error>());
          expect(result.toString(), isNot(contains(config.accessKey)));
        }
        final empty = await _client(
          _Adapter({
            'code': 0,
            'data': {'items': [], 'pages': 0},
          }),
        ).search(keyword: 'test', page: 1);
        expect(empty.data.list, isEmpty);
        expect(empty.data.totalPages, 0);
      },
    );
  });

  test('Android-style successful region dialogs still request roaming', () {
    final video = stream();
    expect(
      config.shouldProxyPlayback({
        'code': 0,
        'result': {'video_info': video},
      }),
      isFalse,
    );
    for (final view in [
      {
        'dialog': {'type': 'area_limit'},
      },
      {
        'end_page': {
          'dialog': {'type': 'area_limit'},
        },
      },
    ]) {
      final response = {
        'code': 0,
        'result': {'video_info': video, 'view_info': view},
      };
      expect(config.shouldProxyPlayback(response), isTrue);
      expect(const BiliRoamingConfig().shouldProxyPlayback(response), isFalse);
    }
    expect(config.shouldProxyPlayback({'code': 0, 'result': {}}), isTrue);
    expect(config.shouldProxyPlayback({'code': 6002003}), isTrue);
    expect(config.shouldProxyPlayback({'code': -101}), isFalse);
    expect(
      const BiliRoamingConfig(
        enabled: true,
        force: true,
      ).shouldProxyPlayback({'code': 0}),
      isTrue,
    );
  });

  test('root-level legacy playback payload is accepted', () async {
    final adapter = _Adapter({'code': 0, ...stream(), 'result': 'suee'});
    final result = await _client(adapter).videoUrl(cid: 2, qn: 80);
    expect(result.isSuccess, isTrue);
    expect(result.data.quality, 80);
  });

  test('incomplete season metadata fails before opening the player', () async {
    final result = await _client(
      _Adapter({
        'code': 0,
        'result': {
          'season_id': 4,
          'episodes': [
            {'id': 3},
          ],
        },
      }),
    ).season(seasonId: 4);
    expect(result, isA<Error>());
  });

  test(
    'disabled by default; only region failures trigger automatic fallback',
    () {
      expect(const BiliRoamingConfig().shouldFallback(-10403, ''), isFalse);
      expect(config.shouldFallback(-10403, ''), isTrue);
      expect(config.shouldFallback(-1, '您所在的地区无法观看'), isTrue);
      expect(config.shouldFallback(-1, 'region restricted'), isTrue);
      expect(config.shouldFallback(-101, '请先登录'), isFalse);
      expect(config.shouldFallback(-1, '大会员专享'), isFalse);
      expect(config.shouldFallback(0, 'success'), isFalse);
      expect(config.shouldFallback(-404, '不存在'), isFalse);
      expect(config.shouldFallback(-404, '不存在', season: true), isTrue);
    },
  );

  test(
    'server validation allows path prefixes and rejects unsafe URL forms',
    () {
      expect(
        BiliRoamingConfig.validateServer('https://example.com/proxy/'),
        isNull,
      );
      for (final url in [
        'http://example.com',
        'https://u:p@example.com',
        'https://example.com?a=b',
        'https://example.com/#fragment',
        'invalid',
      ]) {
        expect(BiliRoamingConfig.validateServer(url), isNotNull, reason: url);
      }
    },
  );

  test('disabled or unconfigured client never issues a request', () async {
    for (final cfg in [
      const BiliRoamingConfig(),
      const BiliRoamingConfig(enabled: true),
    ]) {
      final adapter = _Adapter({});
      final result = await _client(adapter, cfg).videoUrl(cid: 12, qn: 80);
      expect(result, isA<Error>());
      expect(adapter.request, isNull);
    }
  });

  test(
    'web request preserves parameters and sends no account cookies',
    () async {
      final adapter = _Adapter({'code': 0, 'result': stream()});
      final result = await _client(adapter).videoUrl(
        avid: 1,
        bvid: 'BVtest',
        cid: 2,
        qn: 120,
        epId: 3,
        seasonId: 4,
        language: 'zh-CN',
        voiceBalance: true,
      );
      expect(result.isSuccess, isTrue);
      final request = adapter.request!;
      expect(request.uri.path, '/proxy/pgc/player/web/playurl');
      expect(
        request.uri.queryParameters,
        containsPair('access_key', config.accessKey),
      );
      expect(request.queryParameters, containsPair('area', 'tw'));
      expect(request.queryParameters, containsPair('fnval', 4048));
      expect(request.queryParameters, containsPair('fnver', 0));
      expect(request.queryParameters, containsPair('fourk', 1));
      expect(request.queryParameters, containsPair('qn', 120));
      expect(request.queryParameters, containsPair('ep_id', 3));
      expect(request.queryParameters, containsPair('cid', 2));
      expect(request.queryParameters, containsPair('avid', 1));
      expect(request.queryParameters, containsPair('cur_language', 'zh-CN'));
      expect(request.queryParameters, containsPair('voice_balance', 1));
      expect(request.headers['platform-from-biliroaming'], 'web');
      expect(
        request.headers.keys.map((e) => e.toLowerCase()),
        isNot(anyElement(isIn(['cookie', 'authorization', 'csrf']))),
      );
      expect(request.followRedirects, isFalse);
      expect(adapter.closed, isTrue);
      final data = result.data;
      expect(data.dash!.video!.single.baseUrl, 'https://media.example/v.m4s');
      expect(data.dash!.audio!.single.baseUrl, 'https://media.example/a.m4s');
      expect(data.isDrm, isTrue);
      expect(data.isPreview, isTrue);
    },
  );

  test('PHP compatibility omits roaming headers and blank key', () async {
    final adapter = _Adapter({'code': 0, 'data': stream()});
    final cfg = BiliRoamingConfig(
      enabled: true,
      server: config.server,
      sendHeaders: false,
    );
    expect(
      (await _client(adapter, cfg).videoUrl(cid: 2, qn: 80)).isSuccess,
      isTrue,
    );
    expect(adapter.request!.headers, isNot(contains('x-from-biliroaming')));
    expect(
      adapter.request!.headers,
      isNot(contains('platform-from-biliroaming')),
    );
    expect(adapter.request!.queryParameters, isNot(contains('access_key')));
  });

  test('nested v2 result retains progress and entitlement flags', () async {
    final adapter = _Adapter({
      'code': 0,
      'result': {
        'video_info': stream(),
        'play_view_business_info': {
          'user_status': {
            'watch_progress': {
              'current_watch_progress': 12345,
            },
          },
        },
      },
    });
    final data = (await _client(adapter).videoUrl(cid: 2, qn: 80)).data;
    expect(data.lastPlayTime, 12345);
    expect(data.isPreview, isTrue);
  });

  test('legacy durl responses remain playable', () async {
    final adapter = _Adapter({
      'code': 0,
      'result': {
        'quality': 80,
        'durl': [
          {'url': 'https://media.example/v.mp4'},
        ],
      },
    });
    final data = (await _client(adapter).videoUrl(cid: 2, qn: 80)).data;
    expect(data.durl!.single.url, 'https://media.example/v.mp4');
  });

  test('season metadata uses the configured server and region', () async {
    final adapter = _Adapter({
      'code': 0,
      'result': {
        'season_id': 4,
        'title': 'Test season',
        'episodes': [
          {'id': 3, 'cid': 2, 'aid': 1, 'bvid': 'BVtest'},
        ],
        'section': [
          {
            'title': 'Extras',
            'episodes': [
              {'id': 5, 'cid': 6, 'aid': 7, 'bvid': 'BVextra'},
            ],
          },
        ],
      },
    });
    final result = await _client(adapter).season(seasonId: 4, epId: 3);
    expect(result.isSuccess, isTrue);
    expect(result.data.episodes!.single.cid, 2);
    expect(result.data.episodes!.single.epId, 3);
    expect(result.data.sections!.single.episodes!.single.epId, 5);
    expect(adapter.request!.uri.path, '/proxy/pgc/view/web/season');
    expect(adapter.request!.queryParameters['area'], 'tw');
  });

  test(
    'malformed or empty playback payloads produce actionable errors',
    () async {
      for (final payload in [
        null,
        [],
        {'code': 0},
        {'code': 0, 'result': {}},
        {
          'code': 0,
          'result': {
            'dash': {'video': []},
          },
        },
        {
          'code': 0,
          'result': {'dash': 'invalid'},
        },
      ]) {
        final result = await _client(_Adapter(payload))
            .videoUrl(cid: 2, qn: 80);
        expect(result, isA<Error>(), reason: '$payload');
      }
    },
  );

  test(
    'error messages never echo credentials from server or request URLs',
    () async {
      for (final adapter in [
        _Adapter({'code': -15, 'message': config.accessKey}),
        _Adapter({}, status: 403),
        _Adapter({}, status: 302),
      ]) {
        final result = await _client(adapter).videoUrl(cid: 2, qn: 80);
        expect(result, isA<Error>());
        expect(result.toString(), isNot(contains(config.accessKey)));
        expect(result.toString(), isNot(contains('access_key')));
        expect(adapter.closed, isTrue);
      }
    },
  );
}
