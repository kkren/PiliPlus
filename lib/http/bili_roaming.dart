import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/search/pgc.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/services/bili_roaming/config.dart';
import 'package:PiliPlus/services/bili_roaming/search.dart';
import 'package:dio/dio.dart';

/// Uses a separate client: Bilibili cookies, CSRF tokens and account interceptors
/// must never be sent to a user-configured roaming server.
class BiliRoamingHttp {
  // A supplied client is owned and closed after the request.
  BiliRoamingHttp(this.config, {this.client});

  final Dio? client;

  final BiliRoamingConfig config;

  Future<LoadingState<Map<String, dynamic>>> _get(
    String path,
    Map<String, dynamic> params, {
    bool android = false,
  }) async {
    if (!config.enabled) return const Error('哔哩漫游未启用');
    if (!config.isConfigured) return const Error('请先在视频设置中配置有效的哔哩漫游服务端');
    // Android search already resolved and signed the key; do not resolve again.
    final accessKey = android ? '' : config.accessKey;
    final dio = (client ?? Dio())
      ..options = BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        followRedirects: false,
        headers: {
          if (android || config.sendHeaders) ...{
            'User-Agent': 'Bilibili Freedoooooom/MarkII',
            'x-from-biliroaming': 'biliroaming-x-player',
            'platform-from-biliroaming': android ? 'android' : 'web',
          },
        },
      );
    try {
      final base = config.server.trim().replaceFirst(RegExp(r'/+$'), '');
      final response = await dio.get<dynamic>(
        '$base$path',
        queryParameters: {
          ...params,
          if (!android)
            'area': BiliRoamingConfig.areas.containsKey(config.area)
                ? config.area
                : 'hk',
          if (!android && accessKey.isNotEmpty) 'access_key': accessKey,
        },
      );
      final json = response.data;
      if (json is! Map<String, dynamic>) return const Error('哔哩漫游服务端返回了无效数据');
      if (json['code'] != 0) {
        // Avoid reflecting server text or request URLs containing access_key.
        final code = json['code'];
        return Error(
          '哔哩漫游请求失败（${code is int ? code : '未知错误'}），请检查服务端、地区及 Access Key',
        );
      }
      if (json['result'] case final Map<String, dynamic> result) {
        return Success(result);
      }
      if (json['data'] case final Map<String, dynamic> data) {
        return Success(data);
      }
      // Older proxies can return the playurl fields directly at the root.
      return Success(json);
    } on DioException catch (e) {
      return Error('哔哩漫游连接失败（${e.response?.statusCode ?? e.type.name}）');
    } catch (_) {
      return const Error('哔哩漫游服务端返回了无效数据');
    } finally {
      dio.close(force: true);
    }
  }

  Future<LoadingState<SearchPgcData>> search({
    required String keyword,
    required int page,
    bool movie = false,
  }) async {
    if (!config.enabled) return const Error('哔哩漫游未启用');
    try {
      final request = BiliRoamingSearch.request(
        config: config,
        keyword: keyword,
        page: page,
        movie: movie,
      );
      final result = await _get(request.path, request.params, android: true);
      if (result case Success(:final response)) {
        try {
          return Success(BiliRoamingSearch.parse(response));
        } catch (_) {
          return const Error('哔哩漫游搜索数据格式不受支持');
        }
      }
      return result as Error;
    } on ArgumentError {
      return const Error('哔哩漫游搜索参数无效');
    }
  }

  Future<LoadingState<PlayUrlModel>> videoUrl({
    int? avid,
    String? bvid,
    required int cid,
    required int qn,
    Object? epId,
    Object? seasonId,
    String? language,
    bool voiceBalance = false,
  }) async {
    final result = await _get('/pgc/player/web/playurl', {
      'avid': ?avid,
      'bvid': ?bvid,
      'cid': cid,
      'ep_id': ?epId,
      'season_id': ?seasonId,
      'qn': qn,
      'fnver': 0,
      'fnval': 4048,
      'fourk': 1,
      'cur_language': ?language,
      'voice_balance': voiceBalance ? 1 : 0,
    });
    if (result case Success(:final response)) {
      try {
        final data = PlayUrlModel.fromJson(response['video_info'] ?? response);
        if (!(data.dash?.video?.any((e) => e.playUrls.isNotEmpty) ?? false) &&
            !(data.durl?.any((e) => e.playUrls.isNotEmpty) ?? false)) {
          return const Error('哔哩漫游未返回可播放的视频，请检查地区及账号权限');
        }
        if (response['play_view_business_info']?['user_status']?['watch_progress']?['current_watch_progress']
            case final int progress) {
          data.lastPlayTime = progress;
        }
        return Success(data);
      } catch (_) {
        return const Error('哔哩漫游播放数据格式不受支持');
      }
    }
    return result as Error;
  }

  Future<LoadingState<PgcInfoModel>> season({
    Object? seasonId,
    Object? epId,
  }) async {
    final result = await _get('/pgc/view/web/season', {
      'season_id': ?seasonId,
      'ep_id': ?epId,
    });
    if (result case Success(:final response)) {
      try {
        final data = PgcInfoModel.fromJson(response);
        if (!data.hasEpisodes) return const Error('哔哩漫游未返回剧集列表');
        for (final episode in data.episodes!) {
          episode.epId ??= episode.id;
        }
        for (final section in data.sections ?? const []) {
          for (final episode in section.episodes ?? const []) {
            episode.epId ??= episode.id;
          }
        }
        if (data.episodes!.any(
          (episode) =>
              episode.epId == null ||
              episode.cid == null ||
              episode.cid! <= 0 ||
              episode.bvid == null ||
              episode.bvid!.isEmpty,
        )) {
          return const Error('哔哩漫游剧集信息不完整，请使用支持 Web 番剧详情的服务端');
        }
        return Success(data);
      } catch (_) {
        return const Error('哔哩漫游剧集数据格式不受支持');
      }
    }
    return result as Error;
  }
}
