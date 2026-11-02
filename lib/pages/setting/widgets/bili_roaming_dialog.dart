import 'package:PiliPlus/services/bili_roaming/config.dart';
import 'package:material_ui/material_ui.dart';

class BiliRoamingDialog extends StatefulWidget {
  const BiliRoamingDialog({super.key, required this.config});

  final BiliRoamingConfig config;

  @override
  State<BiliRoamingDialog> createState() => _BiliRoamingDialogState();
}

class _BiliRoamingDialogState extends State<BiliRoamingDialog> {
  final _form = GlobalKey<FormState>();
  late bool _enabled = widget.config.enabled;
  late bool _force = widget.config.force;
  late bool _headers = widget.config.sendHeaders;
  late String _server = widget.config.server;
  late String _area = BiliRoamingConfig.areas.containsKey(widget.config.area)
      ? widget.config.area
      : 'hk';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('哔哩漫游'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '通过你配置的 BiliRoaming 服务端获取受地区限制的番剧播放数据。默认先请求 B站，地区限制时再尝试漫游。搜索页另有对应地区的番剧／影视标签。',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用哔哩漫游'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              TextFormField(
                initialValue: _server,
                decoration: const InputDecoration(
                  labelText: '服务端地址',
                  hintText: 'https://你的漫游服务端',
                  helperText: '需提供支持播放及 Android 地区搜索的服务端',
                ),
                autocorrect: false,
                onChanged: (value) => _server = value.trim(),
                validator: (value) {
                  if (_enabled && (value ?? '').trim().isEmpty) {
                    return '启用前请填写服务端地址';
                  }
                  return BiliRoamingConfig.validateServer(value ?? '');
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _area,
                decoration: const InputDecoration(labelText: '地区'),
                items: [
                  for (final entry in BiliRoamingConfig.areas.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) => _area = value ?? 'hk',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('始终使用漫游'),
                subtitle: const Text('番剧信息与播放均请求漫游服务端；用于自动检测未生效的情况'),
                value: _force,
                onChanged: (value) => setState(() => _force = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('发送漫游请求头'),
                subtitle: const Text(
                  '仅控制 Web 接口，旧 PHP 返回 -15 时可关闭；Android 搜索始终发送',
                ),
                value: _headers,
                onChanged: (value) => setState(() => _headers = value),
              ),
              const SizedBox(height: 12),
              const Text(
                '默认向配置的服务端发送当前视频取流账号的 Access Key，无需手动填写；未登录或账号无密钥时不发送。不会发送 Cookie、CSRF 或刷新令牌。地区与会员内容支持取决于服务端及账号权限。',
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              BiliRoamingConfig(
                enabled: _enabled,
                server: _server,
                area: _area,
                force: _force,
                sendHeaders: _headers,
                accessKeyProvider: widget.config.accessKeyProvider,
              ),
            );
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}
