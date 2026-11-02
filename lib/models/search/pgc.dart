import 'package:PiliPlus/models/search/search_num_data.dart';
import 'package:PiliPlus/utils/em.dart';

class SearchPgcData extends SearchNumData<SearchPgcItemModel> {
  SearchPgcData({
    super.numResults,
    super.list,
    this.totalPages,
  });

  int? totalPages;

  SearchPgcData.fromJson(Map<String, dynamic> json) {
    numResults = (json['numResults'] as num?)?.toInt();
    list = (json['result'] as List?)
        ?.map<SearchPgcItemModel>((e) => SearchPgcItemModel.fromJson(e))
        .toList();
  }
}

class SearchPgcItemModel {
  SearchPgcItemModel({
    this.type,
    this.mediaId,
    required this.title,
    this.orgTitle,
    this.mediaType,
    this.cv,
    this.staff,
    this.seasonId,
    this.isAvid,
    this.hitEpids,
    this.seasonType,
    this.seasonTypeName,
    this.url,
    this.buttonText,
    this.isFollow,
    this.isSelection,
    this.cover,
    this.areas,
    this.styles,
    this.gotoUrl,
    this.desc,
    this.pubtime,
    this.mediaMode,
    this.mediaScore,
    this.indexShow,
  });

  String? type;
  int? mediaId;
  late List<({bool isEm, String text})> title;
  String? orgTitle;
  int? mediaType;
  String? cv;
  String? staff;
  int? seasonId;
  bool? isAvid;
  String? hitEpids;
  int? seasonType;
  String? seasonTypeName;
  String? url;
  String? buttonText;
  int? isFollow;
  int? isSelection;
  String? cover;
  String? areas;
  String? styles;
  String? gotoUrl;
  String? desc;
  int? pubtime;
  int? mediaMode;
  Map? mediaScore;
  String? indexShow;

  SearchPgcItemModel.fromJson(Map<String, dynamic> json) {
    type = json['type'];
    mediaId = json['media_id'];
    title = Em.regTitle(json['title']);
    orgTitle = json['org_title'];
    mediaType = json['media_type'];
    cv = json['cv'];
    staff = json['staff'];
    seasonId = json['season_id'];
    isAvid = json['is_avid'];
    hitEpids = json['hit_epids'];
    seasonType = json['season_type'];
    seasonTypeName = json['season_type_name'];
    url = json['url'];
    buttonText = json['button_text'];
    isFollow = json['is_follow'];
    isSelection = json['is_selection'];
    cover = json['cover'];
    areas = json['areas'];
    styles = json['styles'];
    gotoUrl = json['goto_url'];
    desc = json['desc'];
    pubtime = json['pubtime'];
    mediaMode = json['media_mode'];
    mediaScore = json['media_score'];
    indexShow = json['index_show'];
  }
}
