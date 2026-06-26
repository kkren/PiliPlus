package com.example.piliplus

import android.app.Activity
import android.content.Context
import android.content.pm.ActivityInfo
import android.graphics.Color
import android.hardware.display.DisplayManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.ContextThemeWrapper
import android.view.Display
import android.view.SurfaceView
import android.view.View
import androidx.media3.common.C
import androidx.media3.common.ColorInfo
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DecoderCounters
import androidx.media3.exoplayer.DecoderReuseEvaluation
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.util.concurrent.ConcurrentHashMap

private const val MEDIA3_SURFACE_HDR_HEADROOM = 4.0f
private const val MEDIA3_SDR_WINDOW_HEADROOM = 1.0f

@androidx.annotation.OptIn(UnstableApi::class)
class Media3PlayerViewFactory(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    private val sessions = ConcurrentHashMap<Int, Media3PlayerSession>()

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val playerId = (params?.get("id") as? Number)?.toInt() ?: viewId
        val backgroundColor = (params?.get("backgroundColor") as? Number)?.toInt() ?: Color.BLACK
        val session = sessions[playerId] ?: Media3PlayerSession(
            activity = activity,
            messenger = messenger,
            playerId = playerId,
            backgroundColor = backgroundColor,
            onDispose = { sessions.remove(it) },
        ).also { sessions[playerId] = it }
        return Media3PlayerPlatformView(activity, session, viewId, backgroundColor)
    }
}

@androidx.annotation.OptIn(UnstableApi::class)
private class Media3PlayerPlatformView(
    activity: Activity,
    private val session: Media3PlayerSession,
    private val viewId: Int,
    private val backgroundColor: Int,
) : PlatformView {
    private val playerView = PlayerView(
        ContextThemeWrapper(activity, R.style.PiliPlusMedia3PlayerView),
    )

    init {
        session.attachView(playerView, viewId, backgroundColor)
    }

    override fun getView(): View = playerView

    override fun dispose() {
        session.detachView(playerView, viewId)
    }
}

@androidx.annotation.OptIn(UnstableApi::class)
private class Media3PlayerSession(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val playerId: Int,
    private var backgroundColor: Int,
    private val onDispose: (Int) -> Unit,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "piliplus/media3_player/$playerId")
    private val mainHandler = Handler(Looper.getMainLooper())
    private var disposed = false

    private var videoSource: String? = null
    private var audioSource: String? = null
    private var isLive = false
    private var subtitleUri: String? = null
    private var subtitleData: String? = null
    private var subtitleLabel: String? = null
    private var subtitleLanguage: String? = null
    private var subtitleFile: File? = null
    private var currentVideoFormat: Format? = null
    private var currentAudioFormat: Format? = null
    private var videoDecoderName: String? = null
    private var audioDecoderName: String? = null
    private var videoDecoderCounters: DecoderCounters? = null
    private var audioDecoderCounters: DecoderCounters? = null
    private var totalDroppedVideoFrames = 0
    private var lastDroppedVideoFrames = 0
    private var lastDroppedVideoFrameElapsedMs = 0L
    private var bandwidthEstimateBitsPerSecond = 0L
    private var lastBandwidthLoadTimeMs = 0
    private var lastBandwidthBytesLoaded = 0L
    private var hdrModeEnabled = false
    private var desiredSurfaceHdrHeadroom = 0f
    private var desiredWindowHdrHeadroom = 0f
    private var attachedViewId: Int? = null

    private val httpFactory = DefaultHttpDataSource.Factory()
    private val dataSourceFactory = DefaultDataSource.Factory(activity, httpFactory)
    private val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
    private val player = ExoPlayer.Builder(activity).build()
    private var activePlayerView: PlayerView? = null

    private val stateTicker = object : Runnable {
        override fun run() {
            if (disposed) return
            sendState()
            mainHandler.postDelayed(this, 500)
        }
    }

    init {
        channel.setMethodCallHandler(this)
        player.addListener(
            object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    sendState()
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    sendState()
                }

                override fun onPlayerError(error: PlaybackException) {
                    channel.invokeMethod("error", error.message ?: error.errorCodeName)
                }

                override fun onVideoSizeChanged(videoSize: VideoSize) {
                    sendState()
                }
            },
        )
        player.addAnalyticsListener(
            object : AnalyticsListener {
                override fun onVideoEnabled(
                    eventTime: AnalyticsListener.EventTime,
                    counters: DecoderCounters,
                ) {
                    videoDecoderCounters = counters
                    sendState()
                }

                override fun onAudioEnabled(
                    eventTime: AnalyticsListener.EventTime,
                    counters: DecoderCounters,
                ) {
                    audioDecoderCounters = counters
                    sendState()
                }

                override fun onVideoDecoderInitialized(
                    eventTime: AnalyticsListener.EventTime,
                    decoderName: String,
                    initializedTimestampMs: Long,
                    initializationDurationMs: Long,
                ) {
                    videoDecoderName = decoderName
                    sendState()
                }

                override fun onAudioDecoderInitialized(
                    eventTime: AnalyticsListener.EventTime,
                    decoderName: String,
                    initializedTimestampMs: Long,
                    initializationDurationMs: Long,
                ) {
                    audioDecoderName = decoderName
                    sendState()
                }

                override fun onVideoInputFormatChanged(
                    eventTime: AnalyticsListener.EventTime,
                    format: Format,
                    decoderReuseEvaluation: DecoderReuseEvaluation?,
                ) {
                    currentVideoFormat = format
                    updateHdrModeForFormat(format)
                    sendState()
                }

                override fun onAudioInputFormatChanged(
                    eventTime: AnalyticsListener.EventTime,
                    format: Format,
                    decoderReuseEvaluation: DecoderReuseEvaluation?,
                ) {
                    currentAudioFormat = format
                    sendState()
                }

                override fun onDroppedVideoFrames(
                    eventTime: AnalyticsListener.EventTime,
                    droppedFrames: Int,
                    elapsedMs: Long,
                ) {
                    lastDroppedVideoFrames = droppedFrames
                    lastDroppedVideoFrameElapsedMs = elapsedMs
                    totalDroppedVideoFrames += droppedFrames
                    sendState()
                }

                override fun onBandwidthEstimate(
                    eventTime: AnalyticsListener.EventTime,
                    totalLoadTimeMs: Int,
                    totalBytesLoaded: Long,
                    bitrateEstimate: Long,
                ) {
                    lastBandwidthLoadTimeMs = totalLoadTimeMs
                    lastBandwidthBytesLoaded = totalBytesLoaded
                    bandwidthEstimateBitsPerSecond = bitrateEstimate
                    sendState()
                }
            },
        )
        mainHandler.post(stateTicker)
    }

    fun attachView(playerView: PlayerView, viewId: Int, backgroundColor: Int) {
        this.backgroundColor = backgroundColor
        if (activePlayerView !== playerView) {
            activePlayerView?.player = null
        }
        attachedViewId = viewId
        activePlayerView = playerView
        playerView.visibility = View.VISIBLE
        playerView.useController = false
        playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
        playerView.setBackgroundColor(backgroundColor)
        playerView.player = player
        applyHdrHeadroom(hdrModeEnabled)
        sendState()
    }

    fun detachView(playerView: PlayerView, viewId: Int) {
        if (attachedViewId != viewId) return
        if (activePlayerView !== playerView) return
        playerView.player = null
        activePlayerView = null
        attachedViewId = null
    }

    private fun hideView() {
        activePlayerView?.let { playerView ->
            playerView.visibility = View.INVISIBLE
            playerView.player = null
        }
    }

    fun dispose() {
        if (disposed) return
        setHdrMode(false, force = true)
        disposed = true
        activePlayerView?.player = null
        activePlayerView = null
        attachedViewId = null
        channel.setMethodCallHandler(null)
        mainHandler.removeCallbacksAndMessages(null)
        player.release()
        subtitleFile?.delete()
        onDispose(playerId)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "open" -> {
                    open(call)
                    result.success(null)
                }
                "refresh" -> {
                    reopen(
                        startMs = call.argument<Number>("startMs")?.toLong() ?: player.currentPosition,
                        play = call.argument<Boolean>("play") ?: player.playWhenReady,
                    )
                    result.success(null)
                }
                "play" -> {
                    player.play()
                    sendState()
                    result.success(null)
                }
                "pause" -> {
                    player.pause()
                    sendState()
                    result.success(null)
                }
                "seek" -> {
                    player.seekTo(call.argument<Number>("positionMs")?.toLong() ?: 0L)
                    sendState()
                    result.success(null)
                }
                "setRate" -> {
                    val rate = call.argument<Number>("rate")?.toFloat() ?: 1.0f
                    player.setPlaybackSpeed(rate)
                    sendState()
                    result.success(null)
                }
                "setVolume" -> {
                    val volume = call.argument<Number>("volume")?.toFloat() ?: 1.0f
                    player.volume = if (volume > 1.0f) volume / 100.0f else volume
                    result.success(null)
                }
                "setAudioOnly" -> {
                    val audioOnly = call.argument<Boolean>("audioOnly") ?: false
                    player.trackSelectionParameters = player.trackSelectionParameters
                        .buildUpon()
                        .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, audioOnly)
                        .build()
                    result.success(null)
                }
                "setSubtitle" -> {
                    subtitleUri = call.argument<String>("uri")
                    subtitleData = call.argument<String>("data")
                    subtitleLabel = call.argument<String>("label")
                    subtitleLanguage = call.argument<String>("language")
                    reopen(player.currentPosition, player.playWhenReady)
                    result.success(null)
                }
                "hideView" -> {
                    hideView()
                    result.success(null)
                }
                "dispose" -> {
                    dispose()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("media3_error", error.message, null)
        }
    }

    private fun open(call: MethodCall) {
        videoSource = call.argument<String>("videoSource")
        audioSource = call.argument<String>("audioSource")
        isLive = call.argument<Boolean>("isLive") ?: false
        subtitleUri = call.argument<String>("subtitleUri")
        subtitleData = call.argument<String>("subtitleData")
        subtitleLabel = call.argument<String>("subtitleLabel")
        subtitleLanguage = call.argument<String>("subtitleLanguage")

        val userAgent = call.argument<String>("userAgent")
        val referer = call.argument<String>("referer")
        if (!userAgent.isNullOrBlank()) {
            httpFactory.setUserAgent(userAgent)
        }
        if (!referer.isNullOrBlank()) {
            httpFactory.setDefaultRequestProperties(mapOf("Referer" to referer))
        }

        reopen(
            startMs = call.argument<Number>("startMs")?.toLong() ?: 0L,
            play = call.argument<Boolean>("play") ?: false,
        )
    }

    private fun reopen(startMs: Long, play: Boolean) {
        val video = videoSource ?: return
        resetDebugInfo()
        player.setMediaSource(buildMediaSource(video, audioSource))
        player.seekTo(startMs.coerceAtLeast(0L))
        player.playWhenReady = play
        player.prepare()
        if (play) {
            player.play()
        }
        sendState()
    }

    private fun buildMediaSource(video: String, audio: String?): MediaSource {
        val videoItem = mediaItem(video, subtitleConfigurations())
        val videoSource = mediaSourceFactory.createMediaSource(videoItem)
        if (audio.isNullOrBlank()) {
            return videoSource
        }
        val audioSource = mediaSourceFactory.createMediaSource(mediaItem(audio, emptyList()))
        return MergingMediaSource(true, true, videoSource, audioSource)
    }

    private fun mediaItem(
        source: String,
        subtitles: List<MediaItem.SubtitleConfiguration>,
    ): MediaItem {
        val builder = MediaItem.Builder().setUri(uriFor(source))
        if (isLive) {
            builder.setLiveConfiguration(MediaItem.LiveConfiguration.Builder().build())
        }
        if (subtitles.isNotEmpty()) {
            builder.setSubtitleConfigurations(subtitles)
        }
        return builder.build()
    }

    private fun subtitleConfigurations(): List<MediaItem.SubtitleConfiguration> {
        val uri = subtitleUriForCurrent() ?: return emptyList()
        return listOf(
            MediaItem.SubtitleConfiguration.Builder(uri)
                .setMimeType(MimeTypes.TEXT_VTT)
                .setLabel(subtitleLabel)
                .setLanguage(subtitleLanguage)
                .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                .build(),
        )
    }

    private fun subtitleUriForCurrent(): Uri? {
        subtitleFile?.delete()
        subtitleFile = null
        subtitleData?.takeIf { it.isNotBlank() }?.let { data ->
            val file = File(activity.cacheDir, "media3_subtitle_$playerId.vtt")
            file.writeText(data)
            subtitleFile = file
            return Uri.fromFile(file)
        }
        return subtitleUri?.takeIf { it.isNotBlank() }?.let(::uriFor)
    }

    private fun uriFor(source: String): Uri {
        return if (
            source.startsWith("http://") ||
            source.startsWith("https://") ||
            source.startsWith("file://") ||
            source.startsWith("content://")
        ) {
            Uri.parse(source)
        } else {
            Uri.fromFile(File(source))
        }
    }

    private fun sendState() {
        if (disposed) return
        val videoSize = player.videoSize
        channel.invokeMethod(
            "state",
            mapOf(
                "playing" to (
                    player.playWhenReady &&
                        player.playbackState != Player.STATE_ENDED
                    ),
                "completed" to (player.playbackState == Player.STATE_ENDED),
                "buffering" to (player.playbackState == Player.STATE_BUFFERING),
                "positionMs" to player.currentPosition.safeMs(),
                "durationMs" to player.duration.safeMs(),
                "bufferedMs" to player.bufferedPosition.safeMs(),
                "rate" to player.playbackParameters.speed,
                "width" to videoSize.width,
                "height" to videoSize.height,
                "hdrModeEnabled" to hdrModeEnabled,
                "displayHdrTypes" to displayHdrTypes(),
                "debug" to debugInfo(),
            ),
        )
    }

    private fun updateHdrModeForFormat(format: Format?) {
        val hdr = format?.colorInfo?.let(ColorInfo::isTransferHdr) == true
        setHdrMode(hdr && displaySupportsHdr())
    }

    private fun setHdrMode(enabled: Boolean, force: Boolean = false) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (!force && hdrModeEnabled == enabled) return
        hdrModeEnabled = enabled
        val applyMode = {
            val params = activity.window.attributes
            params.colorMode = if (enabled) {
                ActivityInfo.COLOR_MODE_HDR
            } else {
                ActivityInfo.COLOR_MODE_DEFAULT
            }
            activity.window.attributes = params
            applyHdrHeadroom(enabled)
            if (!disposed) {
                sendState()
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            applyMode()
        } else {
            mainHandler.post(applyMode)
        }
    }

    private fun applyHdrHeadroom(enabled: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            desiredSurfaceHdrHeadroom = 0f
            desiredWindowHdrHeadroom = 0f
            return
        }

        desiredSurfaceHdrHeadroom = if (enabled) MEDIA3_SURFACE_HDR_HEADROOM else 0f
        desiredWindowHdrHeadroom = if (enabled) MEDIA3_SDR_WINDOW_HEADROOM else 0f

        try {
            activity.window.setDesiredHdrHeadroom(desiredWindowHdrHeadroom)
        } catch (_: Throwable) {
            desiredWindowHdrHeadroom = 0f
        }

        val surfaceView = activePlayerView?.videoSurfaceView as? SurfaceView
        if (surfaceView == null) {
            desiredSurfaceHdrHeadroom = 0f
            return
        }
        try {
            surfaceView.setDesiredHdrHeadroom(desiredSurfaceHdrHeadroom)
        } catch (_: Throwable) {
            desiredSurfaceHdrHeadroom = 0f
        }
    }

    private fun displaySupportsHdr(): Boolean {
        return displayHdrTypes().isNotEmpty()
    }

    private fun currentDisplay(): Display? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                activity.display
            } else {
                @Suppress("DEPRECATION")
                (activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager)
                    .getDisplay(Display.DEFAULT_DISPLAY)
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun displayHdrTypes(): List<String> {
        return try {
            val display = currentDisplay()
            val types = display?.hdrCapabilities?.supportedHdrTypes ?: intArrayOf()
            types.map(::hdrTypeName)
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun displayHdrSdrRatio(): Float? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return null
        }
        return try {
            val display = currentDisplay() ?: return null
            if (display.isHdrSdrRatioAvailable) display.hdrSdrRatio else null
        } catch (_: Throwable) {
            null
        }
    }

    private fun hdrTypeName(type: Int): String {
        return when (type) {
            Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> "DOLBY_VISION"
            Display.HdrCapabilities.HDR_TYPE_HDR10 -> "HDR10"
            Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS -> "HDR10_PLUS"
            Display.HdrCapabilities.HDR_TYPE_HLG -> "HLG"
            else -> "UNKNOWN_$type"
        }
    }

    private fun resetDebugInfo() {
        setHdrMode(false)
        currentVideoFormat = null
        currentAudioFormat = null
        videoDecoderName = null
        audioDecoderName = null
        videoDecoderCounters = null
        audioDecoderCounters = null
        totalDroppedVideoFrames = 0
        lastDroppedVideoFrames = 0
        lastDroppedVideoFrameElapsedMs = 0L
        bandwidthEstimateBitsPerSecond = 0L
        lastBandwidthLoadTimeMs = 0
        lastBandwidthBytesLoaded = 0L
    }

    private fun debugInfo(): Map<String, Any?> {
        videoDecoderCounters?.ensureUpdated()
        audioDecoderCounters?.ensureUpdated()
        return mapOf(
            "videoFormat" to formatInfo(currentVideoFormat),
            "audioFormat" to formatInfo(currentAudioFormat),
            "videoDecoder" to videoDecoderName,
            "audioDecoder" to audioDecoderName,
            "droppedVideoFrames" to totalDroppedVideoFrames,
            "lastDroppedVideoFrames" to lastDroppedVideoFrames,
            "lastDroppedVideoFrameElapsedMs" to lastDroppedVideoFrameElapsedMs,
            "rate" to player.playbackParameters.speed,
            "volume" to (player.volume * 100f),
            "media" to mediaInfo(),
            "bandwidthEstimateBitsPerSecond" to bandwidthEstimateBitsPerSecond,
            "lastBandwidthLoadTimeMs" to lastBandwidthLoadTimeMs,
            "lastBandwidthBytesLoaded" to lastBandwidthBytesLoaded,
            "hdrModeEnabled" to hdrModeEnabled,
            "displayHdrTypes" to displayHdrTypes(),
            "displayHdrSdrRatio" to displayHdrSdrRatio(),
            "desiredSurfaceHdrHeadroom" to desiredSurfaceHdrHeadroom.takeIf { it > 0f },
            "desiredWindowHdrHeadroom" to desiredWindowHdrHeadroom.takeIf { it > 0f },
            "videoSurface" to videoSurfaceInfo(),
            "videoDecoderCounters" to decoderCountersInfo(videoDecoderCounters),
            "audioDecoderCounters" to decoderCountersInfo(audioDecoderCounters),
        )
    }

    private fun mediaInfo(): Map<String, Any?> {
        return mapOf(
            "videoSource" to videoSource,
            "audioSource" to audioSource,
            "subtitleUri" to subtitleUri,
            "subtitleLabel" to subtitleLabel,
            "subtitleLanguage" to subtitleLanguage,
            "isLive" to isLive,
        )
    }

    private fun videoSurfaceInfo(): Map<String, Any?> {
        val surface = activePlayerView?.videoSurfaceView
        return mapOf(
            "class" to surface?.javaClass?.name,
            "isSurfaceView" to (surface is SurfaceView),
            "width" to surface?.width,
            "height" to surface?.height,
        )
    }

    private fun formatInfo(format: Format?): Map<String, Any?>? {
        if (format == null) return null
        return mapOf(
            "id" to format.id,
            "label" to format.label,
            "language" to format.language,
            "containerMimeType" to format.containerMimeType,
            "sampleMimeType" to format.sampleMimeType,
            "codecs" to format.codecs,
            "bitrate" to format.bitrate.cleanNoValue(),
            "averageBitrate" to format.averageBitrate.cleanNoValue(),
            "peakBitrate" to format.peakBitrate.cleanNoValue(),
            "width" to format.width.cleanNoValue(),
            "height" to format.height.cleanNoValue(),
            "frameRate" to format.frameRate.cleanNoValue(),
            "channelCount" to format.channelCount.cleanNoValue(),
            "sampleRate" to format.sampleRate.cleanNoValue(),
            "colorInfo" to colorInfo(format.colorInfo),
        )
    }

    private fun colorInfo(colorInfo: ColorInfo?): Map<String, Any?>? {
        if (colorInfo == null) return null
        return mapOf(
            "colorSpace" to colorInfo.colorSpace,
            "colorSpaceName" to colorSpaceName(colorInfo.colorSpace),
            "colorRange" to colorInfo.colorRange,
            "colorRangeName" to colorRangeName(colorInfo.colorRange),
            "colorTransfer" to colorInfo.colorTransfer,
            "colorTransferName" to colorTransferName(colorInfo.colorTransfer),
            "hdr" to ColorInfo.isTransferHdr(colorInfo),
            "lumaBitdepth" to colorInfo.lumaBitdepth.cleanNoValue(),
            "chromaBitdepth" to colorInfo.chromaBitdepth.cleanNoValue(),
            "hasHdrStaticInfo" to (colorInfo.hdrStaticInfo != null),
        )
    }

    private fun decoderCountersInfo(counters: DecoderCounters?): Map<String, Any?>? {
        if (counters == null) return null
        counters.ensureUpdated()
        return mapOf(
            "decoderInitCount" to counters.decoderInitCount,
            "decoderReleaseCount" to counters.decoderReleaseCount,
            "queuedInputBufferCount" to counters.queuedInputBufferCount,
            "skippedInputBufferCount" to counters.skippedInputBufferCount,
            "renderedOutputBufferCount" to counters.renderedOutputBufferCount,
            "skippedOutputBufferCount" to counters.skippedOutputBufferCount,
            "droppedBufferCount" to counters.droppedBufferCount,
            "droppedInputBufferCount" to counters.droppedInputBufferCount,
            "maxConsecutiveDroppedBufferCount" to counters.maxConsecutiveDroppedBufferCount,
            "droppedToKeyframeCount" to counters.droppedToKeyframeCount,
            "videoFrameProcessingOffsetCount" to counters.videoFrameProcessingOffsetCount,
            "totalVideoFrameProcessingOffsetUs" to counters.totalVideoFrameProcessingOffsetUs,
        )
    }

    private fun Int.cleanNoValue(): Int? {
        return if (this == Format.NO_VALUE || this == C.LENGTH_UNSET) null else this
    }

    private fun Float.cleanNoValue(): Float? {
        return if (this == Format.NO_VALUE.toFloat() || this <= 0f) null else this
    }

    private fun colorSpaceName(value: Int): String {
        return when (value) {
            C.COLOR_SPACE_BT601 -> "BT.601"
            C.COLOR_SPACE_BT709 -> "BT.709"
            C.COLOR_SPACE_BT2020 -> "BT.2020"
            Format.NO_VALUE -> "unknown"
            else -> value.toString()
        }
    }

    private fun colorRangeName(value: Int): String {
        return when (value) {
            C.COLOR_RANGE_LIMITED -> "limited"
            C.COLOR_RANGE_FULL -> "full"
            Format.NO_VALUE -> "unknown"
            else -> value.toString()
        }
    }

    private fun colorTransferName(value: Int): String {
        return when (value) {
            C.COLOR_TRANSFER_LINEAR -> "linear"
            C.COLOR_TRANSFER_SDR -> "SDR"
            C.COLOR_TRANSFER_SRGB -> "sRGB"
            C.COLOR_TRANSFER_GAMMA_2_2 -> "gamma 2.2"
            C.COLOR_TRANSFER_ST2084 -> "ST2084/PQ"
            C.COLOR_TRANSFER_HLG -> "HLG"
            Format.NO_VALUE -> "unknown"
            else -> value.toString()
        }
    }

    private fun Long.safeMs(): Long {
        return if (this == C.TIME_UNSET || this < 0L) 0L else this
    }
}
