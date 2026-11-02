import 'package:PiliPlus/models/common/search/search_type.dart';
import 'package:PiliPlus/services/bili_roaming/config.dart';

class SearchResultTab {
  const SearchResultTab(this.type, {this.roaming});

  final SearchType type;
  final BiliRoamingConfig? roaming;

  String get label => roaming == null
      ? type.label
      : '${BiliRoamingConfig.areas[roaming!.area]}${type.label}';

  static int initialIndex(
    List<SearchResultTab> tabs,
    int typeIndex, {
    String? roamingArea,
  }) {
    if (roamingArea != null) {
      final index = tabs.indexWhere(
        (tab) =>
            tab.type.index == typeIndex && tab.roaming?.area == roamingArea,
      );
      if (index != -1) return index;
    }
    final index = tabs.indexWhere(
      (tab) => tab.type.index == typeIndex && tab.roaming == null,
    );
    return index == -1 ? 0 : index;
  }

  static List<SearchResultTab> forConfig(BiliRoamingConfig config) => [
    for (final type in SearchType.actives) SearchResultTab(type),
    if (config.enabled &&
        config.isConfigured &&
        BiliRoamingConfig.areas.containsKey(config.area)) ...[
      SearchResultTab(SearchType.media_bangumi, roaming: config),
      if (config.area != 'th')
        SearchResultTab(SearchType.media_ft, roaming: config),
    ],
  ];
}
