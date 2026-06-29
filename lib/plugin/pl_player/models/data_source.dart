import 'package:PiliPlus/utils/path_utils.dart';
import 'package:path/path.dart' as path;

enum PlPlayerSourceType {
  media,
  dash,
}

sealed class DataSource {
  final String videoSource;
  final String? audioSource;
  final PlPlayerSourceType sourceType;

  DataSource({
    required this.videoSource,
    required this.audioSource,
    this.sourceType = PlPlayerSourceType.media,
  });
}

class NetworkSource extends DataSource {
  NetworkSource({
    required super.videoSource,
    required super.audioSource,
    super.sourceType,
  });
}

class FileSource extends DataSource {
  final String dir;
  final bool isMp4;

  FileSource({
    required this.dir,
    required this.isMp4,
    required bool hasDashAudio,
    required String typeTag,
  }) : super(
         videoSource: path.join(
           dir,
           typeTag,
           isMp4 ? PathUtils.videoNameType1 : PathUtils.videoNameType2,
         ),
         audioSource: isMp4 || !hasDashAudio
             ? null
             : path.join(dir, typeTag, PathUtils.audioNameType2),
       );
}
