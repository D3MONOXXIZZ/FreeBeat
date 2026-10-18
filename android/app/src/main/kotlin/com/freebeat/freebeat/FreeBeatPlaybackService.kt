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
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.media.app.NotificationCompat.MediaStyle
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
                val oldTitle = currentTitle
                val oldArtist = currentArtist
                val oldAlbum = currentAlbum
                val oldArt = currentArtworkPath
                val oldPlaying = isPlaying
                val oldShuffle = isShuffle
                val oldRepeat = repeatMode
                val oldColor = currentDominantColor

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

                val metadataChanged = (currentTitle != oldTitle ||
                        currentArtist != oldArtist ||
                        currentAlbum != oldAlbum ||
                        currentArtworkPath != oldArt ||
                        isPlaying != oldPlaying ||
                        isShuffle != oldShuffle ||
                        repeatMode != oldRepeat ||
                        currentDominantColor != oldColor)

                // If only position or volume changed, ONLY update MediaSession state.
                // NEVER call notificationManager.notify() periodically: it wakes SystemUI and locks 120Hz!
                if (metadataChanged) {
                    updateNotification()
                } else {
                    updatePlaybackStateOnly()
                }
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
            wakeLock?.acquire(60 * 60 * 1000L) // 1 hour safety hold
        }
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
    }

    private fun updatePlaybackStateOnly() {
        try {
            val playbackState = PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY or
                    PlaybackStateCompat.ACTION_PAUSE or
                    PlaybackStateCompat.ACTION_PLAY_PAUSE or
                    PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                    PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackStateCompat.ACTION_SEEK_TO or
                    PlaybackStateCompat.ACTION_SET_SHUFFLE_MODE or
                    PlaybackStateCompat.ACTION_SET_REPEAT_MODE or
                    PlaybackStateCompat.ACTION_STOP
                )
                .setState(
                    if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                    currentPositionMs,
                    if (isPlaying) 1.0f else 0.0f
                )
                .build()

            mediaSession?.setPlaybackState(playbackState)
        } catch (_: Throwable) {}
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "FreeBeat Music Playback",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Controls background audio playback and notifications"
                setShowBadge(false)
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
            setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)
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

                override fun onSetShuffleMode(shuffleMode: Int) {
                    isShuffle = (shuffleMode != PlaybackStateCompat.SHUFFLE_MODE_NONE)
                    playerActionListener?.invoke("onShuffle", mapOf("isShuffle" to isShuffle))
                    updateNotification()
                }

                override fun onSetRepeatMode(newRepeatMode: Int) {
                    repeatMode = when (newRepeatMode) {
                        PlaybackStateCompat.REPEAT_MODE_ONE -> 2
                        PlaybackStateCompat.REPEAT_MODE_ALL -> 1
                        else -> 0
                    }
                    playerActionListener?.invoke("onRepeat", mapOf("repeatMode" to repeatMode))
                    updateNotification()
                }

                override fun onCustomAction(action: String?, extras: android.os.Bundle?) {
                    when (action) {
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
                    }
                }

                override fun onStop() {
                    stopPlaybackService()
                }
            })
        }
    }

    private fun updateNotification() {
        try {
            // 1. Resolve safe artwork bitmap (max 384x384 for Binder safety)
            val rawArtBitmap = loadArtworkBitmap(currentArtworkPath, currentTitle, currentDominantColor)

            // 2. Update MediaSession state & rich metadata for Quick Settings Media Carousel
            try {
                val playbackState = PlaybackStateCompat.Builder()
                    .setActions(
                        PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackStateCompat.ACTION_SEEK_TO or
                        PlaybackStateCompat.ACTION_SET_SHUFFLE_MODE or
                        PlaybackStateCompat.ACTION_SET_REPEAT_MODE or
                        PlaybackStateCompat.ACTION_STOP
                    )
                    .addCustomAction(
                        PlaybackStateCompat.CustomAction.Builder(
                            ACTION_SHUFFLE,
                            "Shuffle",
                            R.drawable.ic_shuffle
                        ).build()
                    )
                    .addCustomAction(
                        PlaybackStateCompat.CustomAction.Builder(
                            ACTION_REPEAT,
                            "Repeat",
                            R.drawable.ic_repeat
                        ).build()
                    )
                    .setState(
                        if (isPlaying) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                        currentPositionMs,
                        if (isPlaying) 1.0f else 0.0f
                    )
                    .build()

                mediaSession?.apply {
                    setPlaybackState(playbackState)
                    setShuffleMode(if (isShuffle) PlaybackStateCompat.SHUFFLE_MODE_ALL else PlaybackStateCompat.SHUFFLE_MODE_NONE)
                    setRepeatMode(
                        when (repeatMode) {
                            2 -> PlaybackStateCompat.REPEAT_MODE_ONE
                            1 -> PlaybackStateCompat.REPEAT_MODE_ALL
                            else -> PlaybackStateCompat.REPEAT_MODE_NONE
                        }
                    )

                    val mediaMetadata = MediaMetadataCompat.Builder()
                        .putString(MediaMetadataCompat.METADATA_KEY_TITLE, currentTitle)
                        .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, currentArtist)
                        .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, currentAlbum)
                        .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, currentTitle)
                        .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE, currentArtist)
                        .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_DESCRIPTION, currentAlbum)
                        .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, currentDurationMs)
                        .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, rawArtBitmap)
                        .putBitmap(MediaMetadataCompat.METADATA_KEY_ART, rawArtBitmap)
                        .putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, rawArtBitmap)
                        .build()
                    setMetadata(mediaMetadata)
                }
            } catch (e: Throwable) {
                android.util.Log.w("FreeBeatPlayback", "Error updating MediaSession: ${e.message}")
            }

            // 3. Pending intents for standard media transport controls
            val launchIntent = PendingIntent.getActivity(
                this, 0,
                Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

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
            val stopIntent = PendingIntent.getService(
                this, 6,
                Intent(this, FreeBeatPlaybackService::class.java).apply { action = ACTION_STOP },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // 4. Standard MediaStyle Notification for Android SystemUI Media Carousel
            // In Android 11, 12, 13, 14, 15, SystemUI intercepts this standard MediaStyle notification
            // and renders it directly inside the Quick Settings Media Carousel (next to Spotify/YouTube)
            // with live wave seekbar, full-bleed artwork, audio output switcher, and squircle buttons!
            val mediaStyle = MediaStyle()
                .setMediaSession(mediaSession?.sessionToken)
                .setShowActionsInCompactView(0, 1, 2)
                .setShowCancelButton(true)
                .setCancelButtonIntent(stopIntent)

            val prevAction = NotificationCompat.Action(
                R.drawable.ic_skip_previous,
                "Previous",
                prevIntent
            )
            val playPauseAction = NotificationCompat.Action(
                if (isPlaying) R.drawable.ic_pause else R.drawable.ic_play_arrow,
                if (isPlaying) "Pause" else "Play",
                playPauseIntent
            )
            val nextAction = NotificationCompat.Action(
                R.drawable.ic_skip_next,
                "Next",
                nextIntent
            )
            val shuffleAction = NotificationCompat.Action(
                R.drawable.ic_shuffle,
                "Shuffle",
                shuffleIntent
            )
            val repeatAction = NotificationCompat.Action(
                R.drawable.ic_repeat,
                "Repeat",
                repeatIntent
            )

            val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_play_arrow)
                .setContentTitle(currentTitle)
                .setContentText(currentArtist)
                .setSubText(currentAlbum)
                .setLargeIcon(rawArtBitmap)
                .setContentIntent(launchIntent)
                .setDeleteIntent(stopIntent)
                .setStyle(mediaStyle)
                .addAction(prevAction)       // Slot 0
                .addAction(playPauseAction)   // Slot 1
                .addAction(nextAction)        // Slot 2
                .addAction(shuffleAction)     // Slot 3
                .addAction(repeatAction)      // Slot 4
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setPriority(NotificationCompat.PRIORITY_LOW)
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
                    .setPriority(NotificationCompat.PRIORITY_LOW)
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

    private fun scaleToSafeDimensions(bitmap: Bitmap, maxDim: Int = 384): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        if (width <= maxDim && height <= maxDim) return bitmap
        val ratio = width.toFloat() / height.toFloat()
        val targetWidth: Int
        val targetHeight: Int
        if (ratio > 1.0f) {
            targetWidth = maxDim
            targetHeight = (maxDim / ratio).toInt().coerceAtLeast(1)
        } else {
            targetHeight = maxDim
            targetWidth = (maxDim * ratio).toInt().coerceAtLeast(1)
        }
        return Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
    }

    private fun loadArtworkBitmap(path: String?, title: String, dominantColor: Int): Bitmap {
        if (!path.isNullOrEmpty()) {
            // 1. Android SAF content:// URI
            if (path.startsWith("content://")) {
                try {
                    contentResolver.openInputStream(Uri.parse(path))?.use { stream ->
                        val bmp = BitmapFactory.decodeStream(stream)
                        if (bmp != null) return scaleToSafeDimensions(bmp)
                    }
                } catch (_: Throwable) {}
            }

            // 2. Direct local file on disk
            try {
                val file = File(path)
                if (file.exists() && file.length() > 200) {
                    val bmp = BitmapFactory.decodeFile(file.absolutePath)
                    if (bmp != null) return scaleToSafeDimensions(bmp)
                }
            } catch (_: Throwable) {}

            // 3. HTTP / HTTPS URL
            if (path.startsWith("http://") || path.startsWith("https://")) {
                try {
                    val hash = path.hashCode().toString()
                    val cacheFile = File(cacheDir, "art_$hash.jpg")
                    if (cacheFile.exists() && cacheFile.length() > 200) {
                        val bmp = BitmapFactory.decodeFile(cacheFile.absolutePath)
                        if (bmp != null) return scaleToSafeDimensions(bmp)
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
        return scaleToSafeDimensions(createProceduralCover(title, dominantColor))
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
