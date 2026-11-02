import 'package:PiliPlus/http/bili_roaming.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/search/search_type.dart';
import 'package:PiliPlus/models/search/pgc.dart';
import 'package:PiliPlus/pages/search_panel/controller.dart';
import 'package:PiliPlus/services/bili_roaming/config.dart';

class RoamingSearchPgcController
    extends SearchPanelController<SearchPgcData, SearchPgcItemModel> {
  RoamingSearchPgcController({
    required super.keyword,
    required super.searchType,
    required super.tag,
    required super.tabIndex,
    required this.config,
  });

  final BiliRoamingConfig config;

  @override
  Future<LoadingState<SearchPgcData>> customGetData() =>
      BiliRoamingHttp(config).search(
        keyword: keyword,
        page: page,
        movie: searchType == SearchType.media_ft,
      );

  @override
  bool customHandleResponse(bool isRefresh, Success<SearchPgcData> response) {
    super.customHandleResponse(isRefresh, response);
    final data = response.response;
    if (data.totalPages case final pages?) isEnd = page >= pages;
    if (isRefresh) {
      // App search can omit totals. Do not display an invented zero count.
      searchResultController?.count[tabIndex] = data.numResults ?? -1;
    }
    return false;
  }
}
