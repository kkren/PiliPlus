import 'dart:convert';

import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/utils/video_utils.dart';

abstract final class DashMpdUtils {
  static String buildDataUri({
    required Duration? duration,
    required double? minBufferTime,
    required Iterable<VideoItem> videoItems,
    required AudioItem? audioItem,
  }) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..write('<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" ')
      ..write('type="static" ')
      ..write('profiles="urn:mpeg:dash:profile:isoff-on-demand:2011" ')
      ..write('minBufferTime="${_duration(minBufferTime ?? 1.5)}"');

    final presentationDuration = duration;
    if (presentationDuration != null && presentationDuration > Duration.zero) {
      buffer.write(
        ' mediaPresentationDuration="${_durationFromDuration(presentationDuration)}"',
      );
    }
    buffer.writeln('>');
    buffer.write('  <Period');
    if (presentationDuration != null && presentationDuration > Duration.zero) {
      buffer.write(
        ' duration="${_durationFromDuration(presentationDuration)}"',
      );
    }
    buffer.writeln('>');

    _writeVideoAdaptationSet(buffer, videoItems);
    if (audioItem != null && audioItem.playUrls.isNotEmpty) {
      _writeAudioAdaptationSet(buffer, audioItem);
    }

    buffer
      ..writeln('  </Period>')
      ..writeln('</MPD>');

    return Uri.dataFromString(
      buffer.toString(),
      mimeType: 'application/dash+xml',
      encoding: utf8,
      base64: true,
    ).toString();
  }

  static void _writeVideoAdaptationSet(
    StringBuffer buffer,
    Iterable<VideoItem> items,
  ) {
    final representations = items.where((item) => item.playUrls.isNotEmpty);
    buffer.writeln(
      '    <AdaptationSet id="0" contentType="video" '
      'segmentAlignment="true" subsegmentAlignment="true">',
    );
    var index = 0;
    for (final item in representations) {
      final codecs = item.codecs;
      final mimeType = item.mimeType ?? 'video/mp4';
      buffer.write(
        '      <Representation id="${_attr('v${index++}-${item.id ?? 0}')}" '
        'mimeType="${_attr(mimeType)}" '
        'bandwidth="${item.bandWidth ?? 1}"',
      );
      if (codecs?.isNotEmpty == true) {
        buffer.write(' codecs="${_attr(codecs!)}"');
      }
      if (item.width != null) buffer.write(' width="${item.width}"');
      if (item.height != null) buffer.write(' height="${item.height}"');
      if (item.frameRate?.isNotEmpty == true) {
        buffer.write(' frameRate="${_attr(item.frameRate!)}"');
      }
      if (item.sar?.isNotEmpty == true) {
        buffer.write(' sar="${_attr(item.sar!)}"');
      }
      buffer.writeln('>');
      _writeBaseUrlAndSegmentBase(
        buffer,
        url: VideoUtils.getCdnUrl(item.playUrls),
        item: item,
      );
      buffer.writeln('      </Representation>');
    }
    buffer.writeln('    </AdaptationSet>');
  }

  static void _writeAudioAdaptationSet(StringBuffer buffer, AudioItem item) {
    buffer.writeln(
      '    <AdaptationSet id="1" contentType="audio" '
      'segmentAlignment="true" subsegmentAlignment="true">',
    );
    final codecs = item.codecs;
    final mimeType = item.mimeType ?? 'audio/mp4';
    buffer.write(
      '      <Representation id="${_attr('a-${item.id ?? 0}')}" '
      'mimeType="${_attr(mimeType)}" '
      'bandwidth="${item.bandWidth ?? 1}"',
    );
    if (codecs?.isNotEmpty == true) {
      buffer.write(' codecs="${_attr(codecs!)}"');
    }
    buffer.writeln('>');
    buffer.writeln(
      '        <AudioChannelConfiguration '
      'schemeIdUri="urn:mpeg:dash:23003:3:audio_channel_configuration:2011" '
      'value="2"/>',
    );
    _writeBaseUrlAndSegmentBase(
      buffer,
      url: VideoUtils.getCdnUrl(item.playUrls, isAudio: true),
      item: item,
    );
    buffer.writeln('      </Representation>');
    buffer.writeln('    </AdaptationSet>');
  }

  static void _writeBaseUrlAndSegmentBase(
    StringBuffer buffer, {
    required String url,
    required BaseItem item,
  }) {
    buffer.writeln('        <BaseURL>${_text(url)}</BaseURL>');
    final segmentBase = item.segmentBase;
    if (segmentBase == null) return;
    final initialization = segmentBase['initialization']?.toString();
    final indexRange = (segmentBase['index_range'] ?? segmentBase['indexRange'])
        ?.toString();
    if (initialization == null && indexRange == null) return;
    buffer.write('        <SegmentBase');
    if (indexRange != null) {
      buffer.write(' indexRange="${_attr(indexRange)}"');
    }
    if (initialization == null) {
      buffer.writeln('/>');
      return;
    }
    buffer
      ..writeln('>')
      ..writeln('          <Initialization range="${_attr(initialization)}"/>')
      ..writeln('        </SegmentBase>');
  }

  static String _duration(num seconds) {
    var value = seconds.toStringAsFixed(seconds % 1 == 0 ? 0 : 3);
    value = value.replaceFirst(RegExp(r'\.?0+$'), '');
    return 'PT${value}S';
  }

  static String _durationFromDuration(Duration duration) {
    final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
    return _duration(seconds);
  }

  static String _text(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _attr(String value) =>
      _text(value).replaceAll('"', '&quot;').replaceAll("'", '&apos;');
}
