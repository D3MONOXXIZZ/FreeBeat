package com.freebeat.freebeat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Shader
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import java.io.File
import java.net.URL

class FreeBeatPlaybackService : Service() {

    companion object {
        const val CHANNEL_ID = "freebeat_playback_channel_v4"
        const val NOTIFICATION_ID = 1001

        const val ACTION_PLAY_PAUSE = "com.freebeat.ACTION_PLAY_PAUSE"
        const val ACTION_NEXT = "com.freebeat.ACTION_NEXT"
        const val ACTION_PREV = "com.freebeat.ACTION_PREV"
        const val ACTION_SHUFFLE = "com.freebeat.ACTION_SHUFFLE"
        const val ACTION_REPEAT = "com.freebeat.ACTION_REPEAT"
        const val ACTION_STOP = "com.freebeat.ACTION_STOP"
        const val ACTION_UPDATE = "com.freebeat.ACTION_UPDATE"

        var isServiceRunning = false
        var playerActionListener: ((action: String, extras: Map<String, Any>) -> Unit)? = null

        var currentTitle: String = "FreeBeat"
        var currentArtist: String = "Unknown Artist"
        var currentAlbum: String = "Library"
        var currentArtworkPath: String? = null
        var currentDurationMs: Long = 0L
        var currentPositionMs: Long = 0L
        var isPlaying: Boolean = false
        var isShuffle: Boolean = false
        var repeatMode: Int = 0 // 0: Off, 1: All, 2: One
        var currentVolume: Float = 1.0f
        var currentDominantColor: Int = 0xFF1E293B.toInt()
        var currentOutputDevice: String = "Phone Speaker"
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var mediaSession: MediaSessionCompat? = null

    override fun onCreate() {
        super.onCreate()
        isServiceRunning = true
        createNotificationChannel()
        initMediaSession()
        acquireWakeLock()
        updateNotification()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action

        when (action) {
            ACTION_PLAY_PAUSE -> {
                isPlaying = !isPlaying
                playerActionListener?.invoke("onPlayPause", mapOf("isPlaying" to isPlaying))
                updateNotification()
            }
            ACTION_NEXT -> {
                playerActionListener?.invoke("onNext", emptyMap())
            }
            ACTION_PREV -> {
                playerActionListener?.invoke("onPrevious", emptyMap())
            }
            ACTION_SHUFFLE -> {
                isShuffle = !isShuffle
                playerActionListener?.invoke("onShuffle", mapOf("isShuffle" to isShuffle))
                updateNotification()
            }
            ACTION_REPEAT -> {
                repeatMode = (repeatMode + 1) % 3
                playerActionListener?.invoke("onRepeat", mapOf("repeatMode" to repeatMode))
                updateNotification()
            }
            ACTION_STOP -> {
                stopPlaybackService()
                return START_NOT_STICKY
            }
            ACTION_UPDATE -> {
                intent.getStringExtra("title")?.let { if (it.isNotEmpty()) currentTitle = it }
                intent.getStringExtra("artist")?.let { if (it.isNotEmpty()) currentArtist = it }
                intent.getStringExtra("album")?.let { if (it.isNotEmpty()) currentAlbum = it }

                // CRITICAL: Only update artworkPath if non-null and not empty so position updates don't wipe out artwork
                val artArg = intent.getStringExtra("artworkPath")
                if (!artArg.isNullOrEmpty()) {
                    currentArtworkPath = artArg
                }

                currentDurationMs = intent.getLongExtra("durationMs", currentDurationMs)
                currentPositionMs = intent.getLongExtra("positionMs", currentPositionMs)
                isPlaying = intent.getBooleanExtra("isPlaying", isPlaying)
                currentVolume = intent.getFloatExtra("volume", currentVolume)
                currentDominantColor = intent.getIntExtra("dominantColor", currentDominantColor)
                intent.getStringExtra("outputDevice")?.let { if (it.isNotEmpty()) currentOutputDevice = it }
                if (intent.hasExtra("isShuffle")) isShuffle = intent.getBooleanExtra("isShuffle", isShuffle)
                if (intent.hasExtra("repeatMode")) repeatMode = intent.getIntExtra("repeatMode", repeatMode)

                if (isPlaying) {
                    acquireWakeLock()
                } else {
                    releaseWakeLock()
                }
                updateNotification()
            }
        }

        return START_STICKY
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "FreeBeat:PlaybackWakeLock")
            wakeLock?.setReferenceCounted(false)
        }
        if (wakeLock?.isHeld != true) {
            wakeLock?.acquire(24 * 60 * 60 * 1000L) // Safe hold while playing
        }
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "FreeBeat Music Playback",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Controls background audio playback and notifications"
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                enableVibration(false)
                setSound(null, null)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun initMediaSession() {
        mediaSession = MediaSessionCompat(this, "FreeBeatMediaSession").apply {
            isActive = true
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    isPlaying = true
                    playerActionListener?.invoke("onPlayPause", mapOf("isPlaying" to true))
                    updateNotification()
                }

                override fun onPause() {
                    isPlaying = false
                    playerActionListener?.invoke("onPlayPause", mapOf("isPlaying" to false))
                    updateNotification()
                }

                override fun onSkipToNext() {
                    playerActionListener?.invoke("onNext", emptyMap())
                }

                override fun onSkipToPrevious() {
                    playerActionListener?.invoke("onPrevious", emptyMap())
                }

                override fun onSeekTo(pos: Long) {
                    currentPositionMs = pos
                    playerActionListener?.invoke("onSeek", mapOf("positionMs" to pos))
                    updateNotification()
                }

                override fun onStop() {
                    stopPlaybackService()
                }
            })
        }
    }

    private fun updateNotification() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val detectedOutput = detectOutputDevice(audioManager)
            val outputDeviceName = if (detectedOutput.isNotEmpty()) detectedOutput else currentOutputDevice

            // 1. Resolve & prepare rounded album artwork bitmap (16dp rounded corners)
            val rawArtBitmap = loadArtworkBitmap(currentArtworkPath, currentTitle, currentDominantColor)
            val artBitmap = getRoundedCornerBitmap(rawArtBitmap, 16f)

            // 2. Update MediaSession state & metadata (powers Bluetooth, lockscreen, car audio)
            try {
                val playbackState = PlaybackStateCompat.Builder()
                    .setActions(
                        PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackStateCompat.ACTION_SEEK_TO or
                        PlaybackStateCompat.ACTION_STOP
                    )
                    .setState(
                        if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                        currentPositionMs,
                        1.0f
                    )
                    .build()
                mediaSession?.setPlaybackState(playbackState)

                val mediaMetadata = MediaMetadataCompat.Builder()
                    .putString(MediaMetadataCompat.METADATA_KEY_TITLE, currentTitle)
                    .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, currentArtist)
                    .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, currentAlbum)
                    .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, currentDurationMs)
                    .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, artBitmap)
                    .putBitmap(MediaMetadataCompat.METADATA_KEY_ART, artBitmap)
                    .build()
                mediaSession?.setMetadata(mediaMetadata)
            } catch (_: Throwable) {}

            // 3. Build RemoteViews matching user reference layout
            val compactViews = RemoteViews(packageName, R.layout.notification_media_player)
            val expandedViews = RemoteViews(packageName, R.layout.notification_media_player_expanded)

            // Compact View
            compactViews.setTextViewText(R.id.tv_title, currentTitle)
            compactViews.setTextViewText(R.id.tv_artist, currentArtist)
            compactViews.setImageViewBitmap(R.id.iv_artwork, artBitmap)
            val playPauseDarkIcon = if (isPlaying) R.drawable.ic_pause_dark else R.drawable.ic_play_arrow_dark
            compactViews.setImageViewResource(R.id.btn_play_pause, playPauseDarkIcon)

            // Expanded View (Full Reference Mockup)
            expandedViews.setTextViewText(R.id.tv_title_expanded, currentTitle)
            expandedViews.setTextViewText(R.id.tv_artist_expanded, currentArtist)
            expandedViews.setImageViewBitmap(R.id.iv_artwork_expanded, artBitmap)

            // Output Device Icon (Earbuds/Bluetooth/Speaker)
            val deviceIconRes = when {
                outputDeviceName.contains("Bluetooth", true) -> R.drawable.ic_bluetooth
                outputDeviceName.contains("Speaker", true) -> R.drawable.ic_speaker
                else -> R.drawable.ic_earbuds
            }
            expandedViews.setImageViewResource(R.id.iv_output_device, deviceIconRes)
            expandedViews.setImageViewResource(R.id.btn_more, R.drawable.ic_more_horiz_dark)

            // Progress & Time
            val progressPercent = if (currentDurationMs > 0) {
                ((currentPositionMs.toFloat() / currentDurationMs.toFloat()) * 1000).toInt().coerceIn(0, 1000)
            } else 0
            expandedViews.setProgressBar(R.id.pb_seek_bar, 1000, progressPercent, false)
            expandedViews.setTextViewText(R.id.tv_time_current, formatDuration(currentPositionMs))
            expandedViews.setTextViewText(R.id.tv_time_total, formatDuration(currentDurationMs))

            // Play/Pause Dark Icon on Solid White Circle
            expandedViews.setImageViewResource(R.id.btn_play_pause_expanded, playPauseDarkIcon)

            // Card backgrounds are natively defined in XML drawables (@drawable/notification_card_bg and @drawable/notification_compact_bg)
            // keeping the Binder IPC transaction size under 120KB to completely prevent TransactionTooLargeException.

            val launchIntent = PendingIntent.getActivity(
                this, 6,
                Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Pending intents for notification actions
            val playPauseIntent = PendingIntent.getService(
                this, 1,
                Intent(this, FreeBeatPlaybackService::class.java).apply { action = ACTION_PLAY_PAUSE },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val nextIntent = PendingIntent.getService(
                this, 2,
                Intent(this, FreeBeatPlaybackService::class.java).apply { action = ACTION_NEXT },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val prevIntent = PendingIntent.getService(
                this, 3,
                Intent(this, FreeBeatPlaybackService::class.java).apply { action = ACTION_PREV },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val shuffleIntent = PendingIntent.getService(
                this, 4,
                Intent(this, FreeBeatPlaybackService::class.java).apply { action = ACTION_SHUFFLE },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val repeatIntent = PendingIntent.getService(
                this, 5,
                Intent(this, FreeBeatPlaybackService::class.java).apply { action = ACTION_REPEAT },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Button Click Pending Intents
            bindActionIntents(
                compactViews,
                expandedViews,
                playPauseIntent,
                nextIntent,
                prevIntent,
                shuffleIntent,
                repeatIntent,
                launchIntent
            )

            val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_play_arrow)
                .setContentTitle(currentTitle)
                .setContentText(currentArtist)
                .setContentIntent(launchIntent)
                .setCustomContentView(compactViews)
                .setCustomBigContentView(expandedViews)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setOngoing(isPlaying)
                .setColor(currentDominantColor)
                .setColorized(true)
                .setOnlyAlertOnce(true)
                .setSound(null)

            val notification = notificationBuilder.build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceCompat.startForeground(
                    this,
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, notification)
        } catch (e: Throwable) {
            android.util.Log.e("FreeBeatPlayback", "Error in updateNotification: ${e.message}", e)
            try {
                val fallbackNotification = NotificationCompat.Builder(this, CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_play_arrow)
                    .setContentTitle(currentTitle)
                    .setContentText(currentArtist)
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setOngoing(isPlaying)
                    .build()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    ServiceCompat.startForeground(
                        this,
                        NOTIFICATION_ID,
                        fallbackNotification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                    )
                } else {
                    startForeground(NOTIFICATION_ID, fallbackNotification)
                }
            } catch (_: Throwable) {}
        }
    }

    private fun bindActionIntents(
        compactViews: RemoteViews,
        expandedViews: RemoteViews,
        playPauseIntent: PendingIntent,
        nextIntent: PendingIntent,
        prevIntent: PendingIntent,
        shuffleIntent: PendingIntent,
        repeatIntent: PendingIntent,
        launchIntent: PendingIntent
    ) {
        compactViews.setOnClickPendingIntent(R.id.btn_play_pause, playPauseIntent)
        compactViews.setOnClickPendingIntent(R.id.btn_next, nextIntent)
        compactViews.setOnClickPendingIntent(R.id.btn_prev, prevIntent)
        compactViews.setOnClickPendingIntent(R.id.iv_artwork, launchIntent)
        compactViews.setOnClickPendingIntent(R.id.tv_title, launchIntent)
        compactViews.setOnClickPendingIntent(R.id.notification_root, launchIntent)

        expandedViews.setOnClickPendingIntent(R.id.btn_play_pause_expanded, playPauseIntent)
        expandedViews.setOnClickPendingIntent(R.id.btn_next_expanded, nextIntent)
        expandedViews.setOnClickPendingIntent(R.id.btn_prev_expanded, prevIntent)
        expandedViews.setOnClickPendingIntent(R.id.btn_shuffle, shuffleIntent)
        expandedViews.setOnClickPendingIntent(R.id.btn_repeat, repeatIntent)
        expandedViews.setOnClickPendingIntent(R.id.btn_more, launchIntent)
        expandedViews.setOnClickPendingIntent(R.id.pill_now_playing, launchIntent)
        expandedViews.setOnClickPendingIntent(R.id.iv_artwork_expanded, launchIntent)
        expandedViews.setOnClickPendingIntent(R.id.tv_title_expanded, launchIntent)
        expandedViews.setOnClickPendingIntent(R.id.tv_artist_expanded, launchIntent)
        expandedViews.setOnClickPendingIntent(R.id.notification_root_expanded, launchIntent)
    }

    private fun detectOutputDevice(audioManager: AudioManager): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                for (dev in devices) {
                    when (dev.type) {
                        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_HEARING_AID -> {
                            return "Bluetooth (${dev.productName.takeIf { it.isNotEmpty() } ?: "Headphones"})"
                        }
                        AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> {
                            return "USB DAC (${dev.productName.takeIf { it.isNotEmpty() } ?: "Hi-Res"})"
                        }
                        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> {
                            return "Wired Headphones"
                        }
                    }
                }
            } catch (_: Throwable) {}
        }
        return "Phone Speaker"
    }

    private fun getRoundedCornerBitmap(bitmap: Bitmap, cornerRadiusDp: Float): Bitmap {
        val targetSize = 160
        val scaled = Bitmap.createScaledBitmap(bitmap, targetSize, targetSize, true)
        val output = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val rect = RectF(0f, 0f, targetSize.toFloat(), targetSize.toFloat())
        val radiusPx = (cornerRadiusDp / 62f) * targetSize.toFloat()
        canvas.drawRoundRect(rect, radiusPx, radiusPx, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(scaled, 0f, 0f, paint)
        return output
    }

    private fun loadArtworkBitmap(path: String?, title: String, dominantColor: Int): Bitmap {
        if (!path.isNullOrEmpty()) {
            // 1. Android SAF content:// URI
            if (path.startsWith("content://")) {
                try {
                    contentResolver.openInputStream(Uri.parse(path))?.use { stream ->
                        val bmp = BitmapFactory.decodeStream(stream)
                        if (bmp != null) return bmp
                    }
                } catch (_: Throwable) {}
            }

            // 2. Direct local file on disk
            try {
                val file = File(path)
                if (file.exists() && file.length() > 200) {
                    val bmp = BitmapFactory.decodeFile(file.absolutePath)
                    if (bmp != null) return bmp
                }
            } catch (_: Throwable) {}

            // 3. HTTP / HTTPS URL
            if (path.startsWith("http://") || path.startsWith("https://")) {
                try {
                    val hash = path.hashCode().toString()
                    val cacheFile = File(cacheDir, "art_$hash.jpg")
                    if (cacheFile.exists() && cacheFile.length() > 200) {
                        val bmp = BitmapFactory.decodeFile(cacheFile.absolutePath)
                        if (bmp != null) return bmp
                    } else {
                        // Download asynchronously and refresh notification
                        Thread {
                            try {
                                val url = URL(path)
                                val conn = url.openConnection()
                                conn.connectTimeout = 4000
                                conn.readTimeout = 4000
                                conn.getInputStream().use { input ->
                                    cacheFile.outputStream().use { output ->
                                        input.copyTo(output)
                                    }
                                }
                                updateNotification()
                            } catch (_: Throwable) {}
                        }.start()
                    }
                } catch (_: Throwable) {}
            }
        }

        // 4. Procedural High-Res Monet Cover with Vinyl Grooves & Initials
        return createProceduralCover(title, dominantColor)
    }

    private fun createProceduralCover(title: String, dominantColor: Int): Bitmap {
        val size = 360
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        // Draw rich Monet dynamic gradient background
        val shader = android.graphics.LinearGradient(
            0f, 0f, size.toFloat(), size.toFloat(),
            dominantColor,
            blendColorWithBlack(dominantColor, 0.65f),
            Shader.TileMode.CLAMP
        )
        paint.shader = shader
        canvas.drawRect(0f, 0f, size.toFloat(), size.toFloat(), paint)
        paint.shader = null

        // Concentric vinyl soundwave grooves
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2.5f
        for (r in listOf(size * 0.44f, size * 0.34f, size * 0.24f, size * 0.14f)) {
            paint.color = Color.argb(40, 255, 255, 255)
            canvas.drawCircle(size / 2f, size / 2f, r, paint)
        }

        // High-contrast clean initials
        paint.style = Paint.Style.FILL
        paint.color = Color.WHITE
        paint.textSize = 88f
        paint.isFakeBoldText = true
        paint.textAlign = Paint.Align.CENTER
        val initials = title.trim().split(" ")
            .filter { it.isNotEmpty() }
            .take(2)
            .mapNotNull { it.firstOrNull()?.uppercaseChar() }
            .joinToString("")
            .ifEmpty { title.take(2).uppercase().ifEmpty { "FB" } }
        val yPos = (size / 2f - (paint.descent() + paint.ascent()) / 2f)
        canvas.drawText(initials, size / 2f, yPos, paint)

        return bmp
    }

    private fun blendColorWithBlack(color: Int, ratio: Float): Int {
        val a = Color.alpha(color)
        val r = (Color.red(color) * (1 - ratio)).toInt().coerceIn(0, 255)
        val g = (Color.green(color) * (1 - ratio)).toInt().coerceIn(0, 255)
        val b = (Color.blue(color) * (1 - ratio)).toInt().coerceIn(0, 255)
        return Color.argb(a, r, g, b)
    }

    private fun formatDuration(millis: Long): String {
        val totalSecs = (millis / 1000).coerceAtLeast(0)
        val mins = totalSecs / 60
        val secs = totalSecs % 60
        return "%02d:%02d".format(mins, secs)
    }

    private fun stopPlaybackService() {
        releaseWakeLock()
        mediaSession?.isActive = false
        mediaSession?.release()
        mediaSession = null
        isServiceRunning = false
        stopForeground(true)
        stopSelf()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopPlaybackService()
    }
}
