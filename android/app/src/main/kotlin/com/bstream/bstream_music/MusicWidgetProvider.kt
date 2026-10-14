package com.bstream.bstream_music

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Shader
import android.net.Uri
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

class MusicWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val isPlaying = widgetData.getBoolean("isPlaying", false)
        val progress = widgetData.getInt("progress", 0).coerceIn(0, MAX_PROGRESS)
        val title = widgetData.getString("title", null) ?: DEFAULT_TITLE
        val artist = widgetData.getString("artist", null) ?: DEFAULT_ARTIST

        val views = RemoteViews(context.packageName, R.layout.music_widget)
        views.setTextViewText(R.id.tv_title, title)
        views.setTextViewText(R.id.tv_artist, artist)
        views.setProgressBar(R.id.pb_progress, MAX_PROGRESS, progress, false)
        views.setImageViewResource(
            R.id.btn_play,
            if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
        )

        val cover = loadCircularCover(widgetData.getString("coverPath", null))
        if (cover != null) {
            views.setImageViewBitmap(R.id.iv_cover, cover)
        } else {
            // No artwork on disk yet: keep the placeholder icon.
            views.setImageViewResource(R.id.iv_cover, android.R.drawable.ic_media_play)
        }

        bindQueueRow(
            views,
            R.id.row_queue_1,
            R.id.tv_queue_1_title,
            R.id.tv_queue_1_duration,
            widgetData.getString("queue1Title", null)?.trim() ?: "",
            widgetData.getString("queue1Duration", null) ?: "",
        )
        bindQueueRow(
            views,
            R.id.row_queue_2,
            R.id.tv_queue_2_title,
            R.id.tv_queue_2_duration,
            widgetData.getString("queue2Title", null)?.trim() ?: "",
            widgetData.getString("queue2Duration", null) ?: "",
        )

        views.setOnClickPendingIntent(
            R.id.btn_prev,
            transportPendingIntent(context, WidgetAction.PREVIOUS),
        )
        views.setOnClickPendingIntent(
            R.id.btn_play,
            transportPendingIntent(context, WidgetAction.PLAY_PAUSE),
        )
        views.setOnClickPendingIntent(
            R.id.btn_next,
            transportPendingIntent(context, WidgetAction.NEXT),
        )
        views.setOnClickPendingIntent(
            R.id.row_queue_1,
            transportPendingIntent(context, WidgetAction.QUEUE_1),
        )
        views.setOnClickPendingIntent(
            R.id.row_queue_2,
            transportPendingIntent(context, WidgetAction.QUEUE_2),
        )

        val openApp = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        views.setOnClickPendingIntent(R.id.widget_root, openApp)
        views.setOnClickPendingIntent(R.id.iv_cover, openApp)

        appWidgetManager.updateAppWidget(appWidgetIds, views)
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = WidgetAction.fromAction(intent.action)
        if (action == null) {
            super.onReceive(context, intent)
            return
        }
        // The relay is the authoritative control: home_widget dispatches its
        // Dart callback in an isolated engine with no plugin registrant, so no
        // audio plugin is reachable from there on Android. A queue tap jumps
        // that many tracks forward.
        action.keyCodes.forEach { keyCode -> sendMediaButton(context, keyCode) }
        // Mirror the tap into home_widget's background pipeline so the Dart
        // callback observes the same URI the button was bound to.
        forwardToDart(context, action.uri)
    }

    /**
     * Sends a media button event, the same route the lock screen buttons, the
     * notification and Bluetooth headsets take.
     *
     * androidx resolves the media browser service on its own and delivers the
     * key event through the session, so this works whether or not the Flutter
     * UI is alive, as long as the audio session exists.
     */
    private fun sendMediaButton(context: Context, keyCode: Int) {
        val mediaButtonIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(
                context.packageName,
                "com.ryanheise.audioservice.MediaButtonReceiver",
            )
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        context.sendBroadcast(mediaButtonIntent)
    }

    private fun forwardToDart(context: Context, uri: String) {
        try {
            HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse(uri)).send()
        } catch (error: Exception) {
            Log.w(TAG, "Could not forward the widget tap to Dart", error)
        }
    }

    private fun transportPendingIntent(
        context: Context,
        action: WidgetAction,
    ): PendingIntent {
        // `data` keeps every intent distinct, so FLAG_UPDATE_CURRENT refreshes
        // the matching PendingIntent instead of stacking copies.
        return PendingIntent.getBroadcast(
            context,
            action.requestCode,
            Intent(context, MusicWidgetProvider::class.java).apply {
                this.action = action.action
                data = Uri.parse(action.uri)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun bindQueueRow(
        views: RemoteViews,
        rowId: Int,
        titleId: Int,
        durationId: Int,
        title: String,
        duration: String,
    ) {
        if (title.isEmpty()) {
            views.setViewVisibility(rowId, View.GONE)
            return
        }
        views.setViewVisibility(rowId, View.VISIBLE)
        views.setTextViewText(titleId, title)
        views.setTextViewText(durationId, duration)
    }

    /**
     * Decodes the artwork Dart resolved on disk, downscaled to
     * [COVER_SIZE] and masked into a circle. Returns null when the path is
     * missing, unreadable or not an image.
     */
    private fun loadCircularCover(path: String?): Bitmap? {
        val filePath = path?.takeIf { it.isNotBlank() } ?: return null
        val file = File(filePath)
        if (!file.isFile) {
            return null
        }

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            return null
        }

        var sampleSize = 1
        while (bounds.outWidth / (sampleSize * 2) >= COVER_SIZE &&
            bounds.outHeight / (sampleSize * 2) >= COVER_SIZE
        ) {
            sampleSize *= 2
        }
        val decoded = BitmapFactory.decodeFile(
            file.absolutePath,
            BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            },
        ) ?: return null

        val scaled = Bitmap.createScaledBitmap(decoded, COVER_SIZE, COVER_SIZE, true)
        if (scaled != decoded) {
            decoded.recycle()
        }
        return circularMask(scaled)
    }

    /** Cuts a square bitmap into a circle through a BitmapShader. */
    private fun circularMask(source: Bitmap): Bitmap {
        val output = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        }
        val radius = minOf(source.width, source.height) / 2f
        canvas.drawCircle(source.width / 2f, source.height / 2f, radius, paint)
        if (output != source) {
            source.recycle()
        }
        return output
    }

    companion object {
        private const val TAG = "BStreamWidget"
        private const val DEFAULT_TITLE = "Sin reproducción"
        private const val DEFAULT_ARTIST = "IVG Music"
        private const val MAX_PROGRESS = 100
        private const val COVER_SIZE = 128

        /** Every tap target, the URI it reports and the media buttons it sends. */
        private enum class WidgetAction(
            val action: String,
            val uri: String,
            val requestCode: Int,
            val keyCodes: List<Int>,
        ) {
            PREVIOUS(
                action = "com.bstream.bstream_music.widget.action.PREVIOUS",
                uri = "musicwidget://previous",
                requestCode = 4100,
                keyCodes = listOf(KeyEvent.KEYCODE_MEDIA_PREVIOUS),
            ),
            PLAY_PAUSE(
                action = "com.bstream.bstream_music.widget.action.PLAY_PAUSE",
                uri = "musicwidget://playpause",
                requestCode = 4101,
                keyCodes = listOf(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE),
            ),
            NEXT(
                action = "com.bstream.bstream_music.widget.action.NEXT",
                uri = "musicwidget://next",
                requestCode = 4102,
                keyCodes = listOf(KeyEvent.KEYCODE_MEDIA_NEXT),
            ),
            // Tapping the first upcoming row is "skip to the next track".
            QUEUE_1(
                action = "com.bstream.bstream_music.widget.action.QUEUE_1",
                uri = "musicwidget://playqueue1",
                requestCode = 4103,
                keyCodes = listOf(KeyEvent.KEYCODE_MEDIA_NEXT),
            ),
            // The second row jumps two tracks forward.
            QUEUE_2(
                action = "com.bstream.bstream_music.widget.action.QUEUE_2",
                uri = "musicwidget://playqueue2",
                requestCode = 4104,
                keyCodes = List(2) { KeyEvent.KEYCODE_MEDIA_NEXT },
            ),
            ;

            companion object {
                fun fromAction(action: String?): WidgetAction? {
                    if (action == null) {
                        return null
                    }
                    return entries.firstOrNull { it.action == action }
                }
            }
        }
    }
}
