import 'package:PiliPlus/common/skeleton/media_bangumi.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/search_panel/controller.dart';
import 'package:PiliPlus/pages/search_panel/pgc/controller.dart';
import 'package:PiliPlus/pages/search_panel/pgc/widgets/item.dart';
import 'package:PiliPlus/pages/search_panel/view.dart';
import 'package:PiliPlus/services/bili_roaming/config.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart'
    hide SliverGridDelegateWithMaxCrossAxisExtent;

class SearchPgcPanel extends CommonSearchPanel {
  const SearchPgcPanel({
    super.key,
    required super.keyword,
    required super.tag,
    required super.searchType,
    this.roaming,
    this.tabIndex,
  });

  final BiliRoamingConfig? roaming;
  final int? tabIndex;

  @override
  State<SearchPgcPanel> createState() => _SearchPgcPanelState();
}

class _SearchPgcPanelState
    extends
        CommonSearchPanelState<
          SearchPgcPanel,
          SearchPgcData,
          SearchPgcItemModel
        > {
  @override
  late final SearchPanelController<SearchPgcData, SearchPgcItemModel>
  controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      widget.roaming != null
          ? RoamingSearchPgcController(
              keyword: widget.keyword,
              searchType: widget.searchType,
              tag: widget.tag,
              tabIndex: widget.tabIndex,
              config: widget.roaming!,
            )
          : SearchPanelController<SearchPgcData, SearchPgcItemModel>(
              keyword: widget.keyword,
              searchType: widget.searchType,
              tag: widget.tag,
            ),
      tag:
          '${widget.searchType.name}${widget.tag}${widget.roaming == null ? "" : ":roaming:${widget.roaming!.area}"}',
    );
  }

  late final gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: Grid.smallCardWidth * 2,
    mainAxisExtent: 158,
  );

  @override
  Widget buildList(List<SearchPgcItemModel> list) {
    return SliverGrid.builder(
      gridDelegate: gridDelegate,
      itemBuilder: (BuildContext context, int index) {
        if (index == list.length - 1) {
          controller.onLoadMore();
        }
        return SearchPgcItem(item: list[index]);
      },
      itemCount: list.length,
    );
  }

  @override
  Widget get buildLoading => SliverGrid(
    gridDelegate: gridDelegate,
    delegate: const SliverSingleChildDelegate(
      count: 10,
      child: MediaPgcSkeleton(),
    ),
  );
}
