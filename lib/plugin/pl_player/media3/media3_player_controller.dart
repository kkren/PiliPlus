import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

class Media3PlayerState {
  const Media3PlayerState({
    this.playing = false,
    this.completed = false,
    this.buffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.rate = 1.0,
    this.width = 0,
    this.height = 0,
    this.debugInfo = const <String, Object?>{},
  });

  final bool playing;
  final bool completed;
  final bool buffering;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final double rate;
  final int width;
  final int height;
  final Map<String, Object?> debugInfo;

  Media3PlayerState copyWith({
    bool? playing,
    bool? completed,
    bool? buffering,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    double? rate,
    int? width,
    int? height,
    Map<String, Object?>? debugInfo,
  }) => Media3PlayerState(
    playing: playing ?? this.playing,
    completed: completed ?? this.completed,
    buffering: buffering ?? this.buffering,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    buffered: buffered ?? this.buffered,
    rate: rate ?? this.rate,
    width: width ?? this.width,
    height: height ?? this.height,
    debugInfo: debugInfo ?? this.debugInfo,
  );
}

class Media3PlayerController {
  Media3PlayerController._(this.id)
    : _channel = MethodChannel('piliplus/media3_player/$id') {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static int _nextId = 1;

  static Media3PlayerController create() {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Media3 player is only available on Android');
    }
    return Media3PlayerController._(_nextId++);
  }

  final int id;
  final MethodChannel _channel;
  Media3PlayerState state = const Media3PlayerState();
  bool _disposed = false;
  bool _nativeReady = false;
  final List<({String method, Object? arguments})> _pendingCalls = [];

  String? _videoSource;
  bool _isLive = false;
  String? _subtitleUri;
  String? _subtitleData;
  String? _subtitleLabel;
  String? _subtitleLanguage;

  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _buffered = StreamController<Duration>.broadcast();
  final _debugInfo = StreamController<Map<String, Object?>>.broadcast();
  final _error = StreamController<String>.broadcast();

  Stream<bool> get playingStream => _playing.stream;
  Stream<bool> get completedStream => _completed.stream;
  Stream<bool> get bufferingStream => _buffering.stream;
  Stream<Duration> get positionStream => _position.stream;
  Stream<Duration> get durationStream => _duration.stream;
  Stream<Duration> get bufferedStream => _buffered.stream;
  Stream<Map<String, Object?>> get debugInfoStream => _debugInfo.stream;
  Stream<String> get errorStream => _error.stream;

  Future<void> open({
    required String videoSource,
    required String? audioSource,
    required String sourceType,
    required Duration? start,
    required bool play,
    required bool isLive,
    required String userAgent,
    required String referer,
  }) {
    _videoSource = videoSource;
    _isLive = isLive;
    return _invoke('open', {
      'videoSource': videoSource,
      'audioSource': audioSource,
      'sourceType': sourceType,
      'startMs': start?.inMilliseconds ?? 0,
      'play': play,
      'isLive': isLive,
      'userAgent': userAgent,
      'referer': referer,
      'subtitleUri': _subtitleUri,
      'subtitleData': _subtitleData,
      'subtitleLabel': _subtitleLabel,
      'subtitleLanguage': _subtitleLanguage,
    });
  }

  Future<void>? refresh(Duration start, {required bool play}) {
    final video = _videoSource;
    if (video == null) {
      return null;
    }
    return _invoke('refresh', {
      'startMs': start.inMilliseconds,
      'play': play,
      'isLive': _isLive,
    });
  }

  Future<void> play() => _invoke('play');

  Future<void> pause() => _invoke('pause');

  Future<void> playOrPause() => state.playing ? pause() : play();

  Future<void> seek(Duration position) =>
      _invoke('seek', {'positionMs': position.inMilliseconds});

  Future<void> setRate(double rate) => _invoke('setRate', {'rate': rate});

  Future<void> setVolume(double volume) =>
      _invoke('setVolume', {'volume': volume});

  Future<void> setAudioOnly(bool audioOnly) =>
      _invoke('setAudioOnly', {'audioOnly': audioOnly});

  Future<void> hideView() => _invoke('hideView');

  Future<void> setSubtitle({
    String? uri,
    String? data,
    String? label,
    String? language,
  }) {
    _subtitleUri = uri;
    _subtitleData = data;
    _subtitleLabel = label;
    _subtitleLanguage = language;
    return _invoke('setSubtitle', {
      'uri': uri,
      'data': data,
      'label': label,
      'language': language,
    });
  }

  Widget buildView({
    required Color fill,
    required double aspectRatio,
  }) {
    const viewType = 'piliplus/media3_player_view';
    final creationParams = {'id': id, 'backgroundColor': fill.toARGB32()};
    return SizedBox(
      width: aspectRatio * 1000,
      height: 1000,
      child: PlatformViewLink(
        viewType: viewType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        ),
        onCreatePlatformView: (params) {
          return PlatformViewsService.initSurfaceAndroidView(
              id: params.id,
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
              creationParams: creationParams,
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () {
                params.onFocusChanged(true);
              },
            )
            ..addOnPlatformViewCreatedListener((viewId) {
              params.onPlatformViewCreated(viewId);
              _onPlatformViewCreated(viewId);
            })
            ..create();
        },
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    _pendingCalls.clear();
    try {
      await _invoke('dispose');
    } catch (_) {}
    await Future.wait([
      _playing.close(),
      _completed.close(),
      _buffering.close(),
      _position.close(),
      _duration.close(),
      _buffered.close(),
      _debugInfo.close(),
      _error.close(),
    ]);
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (_disposed && method != 'dispose') return null;
    if (!_nativeReady) {
      if (method != 'dispose') {
        _pendingCalls.add((method: method, arguments: arguments));
      }
      return null;
    }
    return _channel.invokeMethod<T>(method, arguments);
  }

  Future<void> _onPlatformViewCreated(int _) async {
    if (_disposed) return;
    _nativeReady = true;
    final calls = List.of(_pendingCalls);
    _pendingCalls.clear();
    for (final call in calls) {
      if (_disposed) return;
      await _channel.invokeMethod(call.method, call.arguments);
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'state':
        _updateState(Map<Object?, Object?>.from(call.arguments as Map));
      case 'error':
        final message = call.arguments?.toString() ?? 'Unknown Media3 error';
        if (!_error.isClosed) _error.add(message);
      default:
        if (kDebugMode) {
          debugPrint('Unknown Media3 callback: ${call.method}');
        }
    }
  }

  void _updateState(Map<Object?, Object?> data) {
    final next = state.copyWith(
      playing: data['playing'] as bool?,
      completed: data['completed'] as bool?,
      buffering: data['buffering'] as bool?,
      position: _durationFromMs(data['positionMs']),
      duration: _durationFromMs(data['durationMs']),
      buffered: _durationFromMs(data['bufferedMs']),
      rate: (data['rate'] as num?)?.toDouble(),
      width: data['width'] as int?,
      height: data['height'] as int?,
      debugInfo: _normalizeMap(data['debug']),
    );
    final previous = state;
    state = next;

    if (previous.debugInfo != next.debugInfo && !_debugInfo.isClosed) {
      _debugInfo.add(next.debugInfo);
    }
    if (previous.playing != next.playing && !_playing.isClosed) {
      _playing.add(next.playing);
    }
    if (previous.completed != next.completed && !_completed.isClosed) {
      _completed.add(next.completed);
    }
    if (previous.buffering != next.buffering && !_buffering.isClosed) {
      _buffering.add(next.buffering);
    }
    if (previous.position != next.position && !_position.isClosed) {
      _position.add(next.position);
    }
    if (previous.duration != next.duration && !_duration.isClosed) {
      _duration.add(next.duration);
    }
    if (previous.buffered != next.buffered && !_buffered.isClosed) {
      _buffered.add(next.buffered);
    }
  }

  Duration? _durationFromMs(Object? value) {
    if (value is num) {
      return Duration(milliseconds: value.round());
    }
    return null;
  }

  Map<String, Object?>? _normalizeMap(Object? value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries)
        entry.key.toString(): _normalizeValue(entry.value),
    };
  }

  Object? _normalizeValue(Object? value) {
    if (value is Map) return _normalizeMap(value);
    if (value is List) return value.map(_normalizeValue).toList();
    return value;
  }
}
