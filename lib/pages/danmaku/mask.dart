import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueListenable, compute;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';

const int _webMaskHeaderLength = 16;
const int _webMaskSegmentMetaLength = 16;
const int _maxWebMaskSegments = 24 * 60 * 60 ~/ 10;

final class WebMaskSegment {
  const WebMaskSegment({required this.time, required this.offset});

  final int time;
  final int offset;
}

final class WebMaskFrame {
  const WebMaskFrame({required this.time, required this.svg});

  final int time;
  final String svg;
}

/// Parsed index at the beginning of a Bilibili `.webmask` file.
final class WebMaskIndex {
  const WebMaskIndex(this.segments);

  final List<WebMaskSegment> segments;

  static int segmentCount(Uint8List header) {
    if (header.length < _webMaskHeaderLength ||
        ascii.decode(header.sublist(0, 4), allowInvalid: true) != 'MASK') {
      throw const FormatException('Invalid webmask header');
    }
    final data = ByteData.sublistView(header);
    final version = data.getUint32(4, Endian.big);
    final count = data.getUint32(12, Endian.big);
    if (version != 1 || count == 0 || count > _maxWebMaskSegments) {
      throw const FormatException('Unsupported webmask index');
    }
    return count;
  }

  factory WebMaskIndex.parse(Uint8List bytes) {
    final count = segmentCount(bytes);
    final indexLength =
        _webMaskHeaderLength + count * _webMaskSegmentMetaLength;
    if (bytes.length < indexLength) {
      throw const FormatException('Incomplete webmask index');
    }

    final data = ByteData.sublistView(bytes);
    final segments = <WebMaskSegment>[];
    for (var i = 0; i < count; i++) {
      final start = _webMaskHeaderLength + i * _webMaskSegmentMetaLength;
      // The unused words are zero in the current version of the format.
      if (data.getUint32(start, Endian.big) != 0 ||
          data.getUint32(start + 8, Endian.big) != 0) {
        continue;
      }
      final segment = WebMaskSegment(
        time: data.getUint32(start + 4, Endian.big),
        offset: data.getUint32(start + 12, Endian.big),
      );
      if (segment.offset < indexLength ||
          (segments.isNotEmpty &&
              (segment.time <= segments.last.time ||
                  segment.offset <= segments.last.offset))) {
        throw const FormatException('Invalid webmask segment table');
      }
      segments.add(segment);
    }
    if (segments.isEmpty) {
      throw const FormatException('Empty webmask segment table');
    }
    return WebMaskIndex(List.unmodifiable(segments));
  }
}

/// Decompresses one webmask segment and extracts its timestamped SVG frames.
List<WebMaskFrame> parseWebMaskFrames(Uint8List compressed) {
  final decoded = Uint8List.fromList(
    const GZipDecoder().decodeBytes(compressed),
  );
  final data = ByteData.sublistView(decoded);
  final frames = <WebMaskFrame>[];
  var offset = 0;
  while (offset < decoded.length) {
    if (decoded.length - offset < 12) {
      throw const FormatException('Incomplete webmask frame header');
    }
    final payloadLength = data.getUint32(offset, Endian.big);
    final time = data.getUint32(offset + 8, Endian.big);
    final payloadStart = offset + 12;
    final payloadEnd = payloadStart + payloadLength;
    if (payloadLength == 0 || payloadEnd > decoded.length) {
      throw const FormatException('Invalid webmask frame length');
    }

    final payload = utf8.decode(decoded.sublist(payloadStart, payloadEnd));
    final separator = payload.indexOf(';base64,');
    if (separator < 0) {
      throw const FormatException('Invalid webmask SVG payload');
    }
    frames.add(
      WebMaskFrame(
        time: time,
        svg: utf8.decode(
          base64Decode(
            payload.substring(separator + 8).replaceAll(RegExp(r'\s'), ''),
          ),
        ),
      ),
    );
    offset = payloadEnd;
  }
  return frames;
}

final class _WebMaskSource {
  _WebMaskSource(this.url);

  final String url;
  Uint8List? _wholeFile;
  late final WebMaskIndex index;

  Future<void> initialize() async {
    final header = await _range(0, _webMaskHeaderLength - 1);
    final count = WebMaskIndex.segmentCount(header);
    final indexEnd =
        _webMaskHeaderLength + count * _webMaskSegmentMetaLength - 1;
    index = WebMaskIndex.parse(await _range(0, indexEnd));
  }

  Future<List<WebMaskFrame>> loadSegment(int segmentIndex) async {
    final segments = index.segments;
    final start = segments[segmentIndex].offset;
    final end = segmentIndex + 1 < segments.length
        ? segments[segmentIndex + 1].offset - 1
        : null;
    final compressed = await _range(start, end);
    return compute(parseWebMaskFrames, compressed);
  }

  Future<Uint8List> _range(int start, int? end) async {
    if (_wholeFile case final file?) {
      return Uint8List.sublistView(
        file,
        start,
        end == null ? file.length : end + 1,
      );
    }

    final response = await Request.dio.get<Uint8List>(
      url.http2https,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'accept-encoding': 'identity',
          'referer': 'https://www.bilibili.com/',
          'range': 'bytes=$start-${end ?? ''}',
        },
      ),
    );
    final bytes = response.data;
    if (bytes == null) {
      throw StateError('Empty webmask response');
    }

    // Some CDNs ignore Range. Keep that response and serve later ranges locally.
    if (response.statusCode == 200) {
      _wholeFile = bytes;
      if (start >= bytes.length || (end != null && end >= bytes.length)) {
        throw const FormatException('Incomplete webmask response');
      }
      return Uint8List.sublistView(
        bytes,
        start,
        end == null ? bytes.length : end + 1,
      );
    }
    return bytes;
  }
}

/// Clips only the danmaku layer with Bilibili's time-varying SVG mask.
class DanmakuMask extends StatefulWidget {
  const DanmakuMask({
    super.key,
    required this.url,
    required this.enabled,
    required this.position,
    required this.child,
  });

  final String? url;
  final bool enabled;
  final ValueListenable<Duration> position;
  final Widget child;

  @override
  State<DanmakuMask> createState() => _DanmakuMaskState();
}

class _DanmakuMaskState extends State<DanmakuMask> {
  _WebMaskSource? _source;
  final Map<int, List<WebMaskFrame>> _segments = {};
  final Map<int, Future<List<WebMaskFrame>>> _loading = {};
  ui.Image? _image;
  int _generation = 0;
  int? _renderedTime;
  bool _rendering = false;
  Duration? _pendingPosition;

  @override
  void initState() {
    super.initState();
    widget.position.addListener(_onPosition);
    _configure();
  }

  @override
  void didUpdateWidget(DanmakuMask oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      oldWidget.position.removeListener(_onPosition);
      widget.position.addListener(_onPosition);
    }
    if (oldWidget.url != widget.url || oldWidget.enabled != widget.enabled) {
      _configure();
    }
  }

  Future<void> _configure() async {
    final generation = ++_generation;
    _source = null;
    _segments.clear();
    _loading.clear();
    _renderedTime = null;
    _replaceImage(null);
    final url = widget.url;
    if (!widget.enabled || url == null || url.isEmpty) return;

    try {
      final source = _WebMaskSource(url);
      await source.initialize();
      if (!mounted || generation != _generation) return;
      _source = source;
      _onPosition();
    } catch (_) {
      // A missing or malformed mask must never prevent danmaku from rendering.
    }
  }

  void _onPosition() {
    final source = _source;
    if (source == null) return;
    final position = widget.position.value.inMilliseconds;
    final segments = source.index.segments;
    var segmentIndex = segments.length - 1;
    for (var i = 1; i < segments.length; i++) {
      if (position < segments[i].time) {
        segmentIndex = i - 1;
        break;
      }
    }
    _showSegmentFrame(segmentIndex, position);

    if (segmentIndex + 1 < segments.length &&
        position >= segments[segmentIndex + 1].time - 2000) {
      unawaited(_prefetchSegment(segmentIndex + 1));
    }
  }

  Future<void> _prefetchSegment(int index) async {
    try {
      await _loadSegment(index);
    } catch (_) {
      // The active frame loader can retry this segment when it is needed.
    }
  }

  Future<List<WebMaskFrame>> _loadSegment(int index) {
    if (_segments[index] case final frames?) return Future.value(frames);
    final source = _source;
    if (source == null) {
      return Future.error(StateError('Webmask source is not configured'));
    }
    final generation = _generation;
    return _loading[index] ??= source
        .loadSegment(index)
        .then(
          (frames) {
            _loading.remove(index);
            if (generation != _generation || !identical(source, _source)) {
              return frames;
            }
            _segments[index] = frames;
            while (_segments.length > 2) {
              _segments.remove(
                _segments.keys.firstWhere((key) => key != index),
              );
            }
            return frames;
          },
          onError: (Object error, StackTrace stackTrace) {
            _loading.remove(index);
            throw error;
          },
        );
  }

  Future<void> _showSegmentFrame(int segmentIndex, int position) async {
    final generation = _generation;
    final source = _source;
    try {
      final frames = await _loadSegment(segmentIndex);
      if (!mounted ||
          frames.isEmpty ||
          generation != _generation ||
          !identical(source, _source)) {
        return;
      }
      var low = 0;
      var high = frames.length - 1;
      while (low < high) {
        final mid = (low + high + 1) >> 1;
        if (frames[mid].time <= position) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      final frame = frames[low];
      if (frame.time == _renderedTime) return;
      _pendingPosition = Duration(milliseconds: position);
      if (_rendering) return;
      await _render(frame, generation);
    } catch (_) {
      // Fail open: leave the unmasked danmaku visible.
    }
  }

  Future<void> _render(WebMaskFrame frame, int generation) async {
    _rendering = true;
    _pendingPosition = null;
    try {
      final picture = await vg.loadPicture(SvgStringLoader(frame.svg), null);
      final size = picture.size;
      late final ui.Image image;
      try {
        image = await picture.picture.toImage(
          size.width.ceil().clamp(1, 4096),
          size.height.ceil().clamp(1, 4096),
        );
      } finally {
        picture.picture.dispose();
      }
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      _renderedTime = frame.time;
      _replaceImage(image);
    } catch (_) {
      // Ignore individual malformed SVG frames.
    } finally {
      _rendering = false;
      if (_pendingPosition != null && mounted) _onPosition();
    }
  }

  void _replaceImage(ui.Image? image) {
    final previous = _image;
    _image = image;
    if (mounted) setState(() {});
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    ++_generation;
    widget.position.removeListener(_onPosition);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DanmakuMaskLayer(
      image: widget.enabled ? _image : null,
      child: widget.child,
    );
  }
}

class _DanmakuMaskLayer extends SingleChildRenderObjectWidget {
  const _DanmakuMaskLayer({required this.image, required super.child});

  final ui.Image? image;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDanmakuMask(image);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderDanmakuMask renderObject,
  ) {
    renderObject.image = image;
  }
}

class _RenderDanmakuMask extends RenderProxyBox {
  _RenderDanmakuMask(this._image);

  @override
  ShaderMaskLayer? get layer => super.layer as ShaderMaskLayer?;

  ui.Image? _image;

  set image(ui.Image? value) {
    if (identical(value, _image)) return;
    final compositingChanged = (_image == null) != (value == null);
    _image = value;
    if (compositingChanged) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _image != null;

  @override
  void paint(PaintingContext context, ui.Offset offset) {
    final image = _image;
    if (image == null) {
      layer = null;
      super.paint(context, offset);
      return;
    }

    assert(needsCompositing);
    final scaleX = size.width / image.width;
    final scaleY = size.height / image.height;
    layer ??= ShaderMaskLayer();
    layer!
      ..shader = ui.ImageShader(
        image,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        Float64List.fromList([
          scaleX,
          0,
          0,
          0,
          0,
          scaleY,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          1,
        ]),
        filterQuality: ui.FilterQuality.low,
      )
      ..maskRect = offset & size
      ..blendMode = ui.BlendMode.dstIn;
    context.pushLayer(layer!, super.paint, offset);
    assert(() {
      layer!.debugCreator = debugCreator;
      return true;
    }());
  }
}
