/// Web-channel protocol reference: Lerrenp/BiliRoaming-webX (GPL-3.0).
class BiliRoamingConfig {
  const BiliRoamingConfig({
    this.enabled = false,
    this.server = '',
    this.area = 'hk',
    this.force = false,
    this.sendHeaders = true,
    this.accessKeyProvider,
  });

  final bool enabled;
  final String server;
  final String area;
  final bool force;
  final bool sendHeaders;
  // Resolve at request time so open search tabs follow account refresh/logout.
  final String? Function()? accessKeyProvider;
  String get accessKey => accessKeyProvider?.call()?.trim() ?? '';

  static const areas = {'hk': '香港', 'tw': '台湾', 'th': '东南亚', 'cn': '中国大陆'};

  static String? validateServer(String value) {
    if (value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return '请输入 HTTPS 服务端地址，可包含路径，不含账号、参数或片段';
    }
    return null;
  }

  bool get isConfigured =>
      server.trim().isNotEmpty && validateServer(server) == null;

  /// Android BiliRoaming also checks area_limit dialogs in successful replies.
  /// https://github.com/sakarie9/BiliRoaming (GPL-3.0).
  bool shouldProxyPlayback(Map response) {
    if (!enabled) return false;
    if (force || shouldFallback(response['code'], response['message'])) {
      return true;
    }
    if (response['code'] != 0) return false;
    final result = response['data'] ?? response['result'];
    if (result is! Map) return true;
    final reason = result['not_playable_reason'];
    if (reason is Map && shouldFallback(reason['code'], reason['message'])) {
      return true;
    }
    final view = result['view_info'];
    if (view is Map) {
      final dialog = view['dialog'];
      if (dialog is Map && dialog['type'] == 'area_limit') return true;
      final endPage = view['end_page'];
      if (endPage is Map) {
        final dialog = endPage['dialog'];
        if (dialog is Map && dialog['type'] == 'area_limit') return true;
      }
    }
    // DRM 响应交由官方备用接口处理。
    if (result['arc'] case {'is_drm': true}) return false;
    return result['video_info'] == null;
  }

  bool shouldFallback(Object? code, Object? message, {bool season = false}) {
    if (!enabled) return false;
    // Season lookup can hide region-restricted titles behind -404.
    if (code == -10403 || code == 6002003 || (season && code == -404)) {
      return true;
    }
    final text = message?.toString().toLowerCase() ?? '';
    return code != 0 &&
        (text.contains('地区') ||
            text.contains('区域') ||
            text.contains('region') ||
            text.contains('area limit'));
  }
}
