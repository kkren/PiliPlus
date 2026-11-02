# 哔哩漫游

在「设置 → 视频设置 → 哔哩漫游」填写支持 BiliRoaming 播放与 Android 地区搜索接口的 HTTPS 服务端地址，选择地区后开启。支持香港、台湾、东南亚、中国大陆；实际可用地区由服务端决定。没有预填公共节点，需要自行提供可用服务端。

默认先请求 B站。在番剧播放接口返回地区限制，或成功响应缺少 `video_info`／包含 `area_limit` 对话框时，改用漫游播放接口。番剧详情返回地区限制或 `-404` 时也会尝试服务端的番剧详情接口。启用「始终使用漫游」后，番剧详情与播放直接请求服务端；普通用户视频、课程和直播保持原有流程。

## 地区搜索

开启漫游并配置有效服务端后，搜索结果页增加所选地区的独立标签，例如「台湾番剧」「台湾影视」。普通「综合」「番剧」「影视」仍然请求 B站；受限条目不会自动合并到普通搜索结果。请横向滑动标签栏，选择对应地区的标签。东南亚按 Android 参考实现只增加「东南亚番剧」，不提供独立影视标签。

地区标签始终直接请求漫游服务端，使用你配置的地区及当前视频取流账号的 Access Key，不依赖普通搜索先返回地区限制错误。后续修改关键词会保留所选地区标签；关闭漫游后，回到相应普通分类。卡片中的季 ID 接入现有番剧详情／播放流程。搜索页使用打开时的服务端配置，修改设置后重新打开搜索页生效。

搜索协议以 [Android BiliRoamingApi](https://github.com/sakarie9/BiliRoaming/blob/7c792dc8fea321ff6a308ce3424668f81019df58/app/src/main/java/me/iacn/biliroaming/network/BiliRoamingApi.kt) 与 `BangumiSeasonHook` 为准：

- 香港／台湾／大陆：`GET <服务端>/x/v2/search/type`。使用 Android 签名、`pn`／`ps` 分页、`type=7`（番剧）或 `8`（影视）、`area` 与 `build=6400000`。
- 东南亚：`GET <服务端>/intl/gateway/v2/app/search/type`。使用 `bstar_a` 签名、`build=1001310`、`zh_SG` 本地化参数；不向签名后的请求追加 Web 通道的 `area` 参数。
- 服务端 `data.items` 转换为现有番剧卡片，保留标题高亮、封面、评分和季 ID。使用 `data.pages` 判断是否继续加载；总数缺失时不显示虚构数量。
- 每次请求自动使用当前视频取流账号的 Access Key；请求时读取最新值，账号切换、刷新或退出登录后不会继续使用旧密钥。搜索的 Android 请求头与签名始终发送；旧 PHP 请求头兼容开关仅控制已有 Web 接口。

当前沿用单个服务端与单个所选地区的设置；需要切换地区时，在漫游设置中修改地区。服务端需支持相应的 Android 搜索接口；仅支持 Web 播放的节点不一定支持地区搜索。

## 播放与番剧详情接口

服务端接口：

- 播放：`GET <服务端>/pgc/player/web/playurl`，携带剧集／视频标识、`qn`、`fnver=0`、`fnval=4048`、`fourk=1`、`area`。
- 番剧详情：`GET <服务端>/pgc/view/web/season`，携带 `season_id`／`ep_id` 和 `area`。服务端需要支持此接口，才能恢复被 B站隐藏的番剧详情；只有播放接口的服务端可以在番剧详情能正常获取时使用默认模式。
- 支持 `result`／`data` 包装、根级播放结果及嵌套 `video_info`。DASH 和 `durl` 接入现有播放器，保留试看片段与 DRM 标记。

「发送漫游请求头」对应 BiliRoaming-webX 的 Web 通道头策略；部分旧 PHP 服务端返回 `-15` 时可以关闭。协议参考：[BiliRoaming-webX fetch-web.js](https://github.com/Lerrenp/BiliRoaming-webX/blob/master/src/background/fetch-web.js)（GPL-3.0）。同时参考 Android 客户端 [sakarie9/BiliRoaming](https://github.com/sakarie9/BiliRoaming/tree/7c792dc8fea321ff6a308ce3424668f81019df58)（GPL-3.0）的 `BangumiPlayUrlHook.needProxy` 与 `BangumiSeasonHook`：检测缺失的视频信息、`area_limit` 对话框和番剧 `-404`。这里使用 PiliPlus 原有播放器，无需安装浏览器扩展或 Xposed 模块。

Access Key 默认自动发送，无需手动填写或覆盖。使用「视频取流」分配的账号；该账号未登录或没有 Access Key 时省略此参数。不发送 Cookie、CSRF 或刷新令牌，也不会将账号密钥复制到漫游设置或设置导出中。请求禁止重定向，错误信息不会回显 URL 或服务端原始错误文本中的密钥。会员内容仍需要相应权限。

弹幕、字幕、评论沿用现有 B站接口。地区搜索使用 Android 签名和国际版搜索接口；番剧详情与播放仍使用已有 Web 通道，没有增加国际版专用播放／字幕协议。东南亚搜索结果能否打开与播放，取决于服务端对详情和 Web 播放接口的支持。

验证命令：

```sh
bash tool/test_bili_roaming.sh /path/to/flutter
```

使用与 PiliPlus 依赖相容的 Flutter SDK（本次使用带手势补丁的 3.47.5）。此脚本使用现有依赖缓存创建临时测试工程，运行生产代码的协议与设置界面测试，避免无关桌面插件对 GTK/X11 的依赖。不替代真实服务端、账号和设备上的播放验证。
