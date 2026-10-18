import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/services/thread_ripper/range_proxy.dart';
import 'package:PiliPlus/utils/dash_mpd_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'adaptive DASH preserves representations and indexes through the proxy',
    () async {
      final bytes = Uint8List.fromList(List.generate(200000, (i) => i % 251));
      final cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      cdn.listen((request) async {
        final (start, end) = RipperRangeProxy.parseRange(
          request.headers.value('range'),
          bytes.length,
        );
        request.response
          ..statusCode = 206
          ..headers.set('Content-Range', 'bytes $start-$end/${bytes.length}')
          ..add(bytes.sublist(start, end + 1));
        await request.response.close();
      });
      final proxy = RipperRangeProxy(
        userAgent: 'test',
        supersedeTrackRequests: false,
      );
      final client = HttpClient();
      addTearDown(() async {
        proxy.close();
        client.close(force: true);
        await cdn.close(force: true);
      });
      await proxy.start();
      final tracks = [
        for (final quality in [64, 80])
          VideoItem.fromJson({
            'id': quality,
            'base_url': 'http://127.0.0.1:${cdn.port}/v$quality.m4s?sign=a%2Bb',
            'bandwidth': quality * 100000,
            'codecs': 'avc1.640032',
            'segment_base': {
              'initialization': '0-999',
              'index_range': '1000-1999',
            },
          }),
      ];
      final audio = AudioItem.fromJson({
        'id': 30280,
        'base_url': 'http://127.0.0.1:${cdn.port}/a.m4s?sign=a%2Bb',
        'codecs': 'mp4a.40.2',
        'segment_base': {'initialization': '0-999', 'index_range': '1000-1999'},
      });
      final mapped = <String>[];
      final uri = DashMpdUtils.buildDataUri(
        duration: const Duration(seconds: 120),
        minBufferTime: 1.5,
        videoItems: tracks,
        audioItem: audio,
        resolveUrl: (item) {
          final url = proxy.registerCandidates(
            item.playUrls.map(Uri.parse).toList(),
            isAudio: item is AudioItem,
          );
          mapped.add(url);
          return url;
        },
      );
      final xml = Uri.parse(uri).data!.contentAsString();
      expect(mapped, hasLength(3));
      expect(xml, contains('id="v0-64"'));
      expect(xml, contains('id="v1-80"'));
      expect(xml, contains('id="a-30280"'));
      expect(xml, contains('mediaPresentationDuration="PT120S"'));
      expect(xml, contains('codecs="avc1.640032"'));
      expect(RegExp('indexRange="1000-1999"').allMatches(xml), hasLength(3));
      expect(xml, isNot(contains('sign=')));
      for (final url in mapped) {
        expect(xml, contains('<BaseURL>$url</BaseURL>'));
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('range', 'bytes=1000-1999');
        final response = await request.close();
        expect(response.statusCode, 206);
        final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
        expect(body, bytes.sublist(1000, 2000));
      }
    },
  );
}
