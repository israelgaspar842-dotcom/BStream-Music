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
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
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
        // Every instance is built and published on its own. A single failure
        // inside one id must not take the rest of the widget down, and the host
        // always receives a RemoteViews it can render: when a step fails the
        // layout simply keeps the default declared in music_widget.xml.
        appWidgetIds.forEach { appWidgetId ->
            val views = RemoteViews(context.packageName, R.layout.music_widget)
            try {
                applyState(context, views, widgetData)
            } catch (error: Throwable) {
                Log.w(TAG, "Widget $appWidgetId rendered partially", error)
            }
            try {
                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (error: Throwable) {
                Log.e(TAG, "Could not publish widget $appWidgetId", error)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = WidgetAction.fromAction(intent.action)
        if (action == null) {
            super.onReceive(context, intent)
            return
        }
        try {
            // The relay is the authoritative control: home_widget dispatches its
            // Dart callback in an isolated engine with no plugin registrant, so no
            // audio plugin is reachable from there on Android. A queue tap jumps
            // that many tracks forward.
            action.keyCodes.forEach { keyCode -> sendMediaButton(context, keyCode) }
        } catch (error: Throwable) {
            Log.w(TAG, "Could not relay ${action.name} to the media session", error)
        }
        // Mirror the tap into home_widget's background pipeline so the Dart
        // callback observes the same URI the button was bound to. Never fatal.
        forwardToDart(context, action.uri)
    }

    /**
     * Fills every piece of the widget. Each optional step is isolated, so a
     * failure in one only degrades that step.
     */
    private fun applyState(
        context: Context,
        views: RemoteViews,
        widgetData: SharedPreferences,
    ) {
        val isPlaying = widgetData.getBoolean("isPlaying", false)
        val progress = widgetData.getInt("progress", 0).coerceIn(0, MAX_PROGRESS)

        // Core state: plain set* actions, covered by the per-instance catch in
        // onUpdate. These must always succeed for the widget to make sense.
        views.setTextViewText(
            R.id.tv_title,
            widgetData.getString("title", null) ?: DEFAULT_TITLE,
        )
        views.setTextViewText(
            R.id.tv_artist,
            widgetData.getString("artist", null) ?: DEFAULT_ARTIST,
        )
        views.setTextViewText(
            R.id.tv_elapsed,
            widgetData.getString("elapsed", null) ?: DEFAULT_CLOCK,
        )
        views.setTextViewText(
            R.id.tv_remaining,
            widgetData.getString("remaining", null) ?: DEFAULT_CLOCK,
        )
        views.setProgressBar(R.id.pb_progress, MAX_PROGRESS, progress, false)
        views.setImageViewResource(
            R.id.btn_play,
            if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play,
        )

        // Optional from here on.
        guarded("queue icons") {
            views.setInt(R.id.iv_queue_1, "setColorFilter", COLOR_NOTE)
            views.setInt(R.id.iv_queue_2, "setColorFilter", COLOR_NOTE)
            views.setInt(R.id.iv_queue_3, "setColorFilter", COLOR_NOTE)
            views.setInt(R.id.iv_queue_4, "setColorFilter", COLOR_NOTE)
        }

        guarded("artwork") { bindArtwork(views, widgetData.getString("coverPath", null)) }
        guarded("queue rows") {
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
            bindQueueRow(
                views,
                R.id.row_queue_3,
                R.id.tv_queue_3_title,
                R.id.tv_queue_3_duration,
                widgetData.getString("queue3Title", null)?.trim() ?: "",
                widgetData.getString("queue3Duration", null) ?: "",
            )
            bindQueueRow(
                views,
                R.id.row_queue_4,
                R.id.tv_queue_4_title,
                R.id.tv_queue_4_duration,
                widgetData.getString("queue4Title", null)?.trim() ?: "",
                widgetData.getString("queue4Duration", null) ?: "",
            )
        }

        // One guard per PendingIntent: a host that rejects one intent must not
        // leave the other controls dead.
        guarded("intent PREVIOUS") {
            views.setOnClickPendingIntent(
                R.id.btn_prev,
                transportPendingIntent(context, WidgetAction.PREVIOUS),
            )
        }
        guarded("intent PLAY_PAUSE") {
            views.setOnClickPendingIntent(
                R.id.btn_play,
                transportPendingIntent(context, WidgetAction.PLAY_PAUSE),
            )
        }
        guarded("intent NEXT") {
            views.setOnClickPendingIntent(
                R.id.btn_next,
                transportPendingIntent(context, WidgetAction.NEXT),
            )
        }
        guarded("intent QUEUE_1") {
            views.setOnClickPendingIntent(
                R.id.row_queue_1,
                transportPendingIntent(context, WidgetAction.QUEUE_1),
            )
        }
        guarded("intent QUEUE_2") {
            views.setOnClickPendingIntent(
                R.id.row_queue_2,
                transportPendingIntent(context, WidgetAction.QUEUE_2),
            )
        }
        guarded("intent QUEUE_3") {
            views.setOnClickPendingIntent(
                R.id.row_queue_3,
                transportPendingIntent(context, WidgetAction.QUEUE_3),
            )
        }
        guarded("intent QUEUE_4") {
            views.setOnClickPendingIntent(
                R.id.row_queue_4,
                transportPendingIntent(context, WidgetAction.QUEUE_4),
            )
        }

        guarded("open app") {
            val openApp =
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            views.setOnClickPendingIntent(R.id.widget_root, openApp)
        }
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
        } catch (error: Throwable) {
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
            // Invisible keeps the row's share of the weighted space, so the
            // populated rows above never collapse into a different layout.
            views.setViewVisibility(rowId, View.INVISIBLE)
            return
        }
        views.setViewVisibility(rowId, View.VISIBLE)
        views.setTextViewText(titleId, title)
        views.setTextViewText(durationId, duration)
    }

    /**
     * Builds the vinyl: a black disc, two groove rings, the artwork clipped into
     * the center label and the spindle hole. Both bitmaps stay small on
     * purpose: every RemoteViews bitmap crosses the Binder at update time, and
     * the transaction has a hard size limit.
     */
    private fun drawVinyl(cover: Bitmap?): Bitmap {
        val output = Bitmap.createBitmap(VINYL_SIZE, VINYL_SIZE, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val center = VINYL_SIZE / 2f

        paint.color = COLOR_VINYL
        canvas.drawCircle(center, center, center, paint)

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = VINYL_SIZE / 160f
        paint.color = COLOR_GROOVE
        canvas.drawCircle(center, center, center * 0.90f, paint)
        canvas.drawCircle(center, center, center * 0.775f, paint)

        paint.style = Paint.Style.FILL
        if (cover != null && !cover.isRecycled) {
            paint.shader = BitmapShader(
                cover,
                Shader.TileMode.CLAMP,
                Shader.TileMode.CLAMP,
            )
            canvas.drawCircle(center, center, center * 0.575f, paint)
            paint.shader = null
        } else {
            paint.color = COLOR_LABEL
            canvas.drawCircle(center, center, center * 0.575f, paint)
        }

        paint.color = COLOR_HOLE
        canvas.drawCircle(center, center, center * 0.0625f, paint)
        return output
    }

    /**
     * Blurred, rounded-corner version of the artwork for the card background.
     *
     * The blur is a cheap downscale-upscale pass: no deprecated RenderScript,
     * and the scrim on top hides whatever softness remains. Returns null when
     * there is no artwork, so the caller can hide the layer entirely.
     */
    private fun drawBackgroundArt(cover: Bitmap?): Bitmap? {
        if (cover == null || cover.isRecycled) {
            return null
        }
        val output = Bitmap.createBitmap(BG_WIDTH, BG_HEIGHT, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val thumb = Bitmap.createScaledBitmap(
            cover,
            BG_WIDTH / BG_BLUR_FACTOR,
            BG_HEIGHT / BG_BLUR_FACTOR,
            true,
        )
        val soft = Bitmap.createScaledBitmap(thumb, BG_WIDTH, BG_HEIGHT, true)
        thumb.recycle()
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = BitmapShader(soft, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        }
        canvas.drawRoundRect(
            RectF(0f, 0f, BG_WIDTH.toFloat(), BG_HEIGHT.toFloat()),
            BG_CORNER_RADIUS,
            BG_CORNER_RADIUS,
            paint,
        )
        soft.recycle()
        return output
    }

    /** Shows the vinyl, or the vector disc when there is no artwork. */
    private fun bindArtwork(views: RemoteViews, coverPath: String?) {
        val cover = loadCoverBitmap(coverPath)
        if (cover == null) {
            views.setImageViewResource(R.id.iv_cover, R.drawable.ic_widget_vinyl_base)
            views.setViewVisibility(R.id.iv_bg_art, View.GONE)
            return
        }
        val background = drawBackgroundArt(cover)
        if (background == null) {
            views.setViewVisibility(R.id.iv_bg_art, View.GONE)
        } else {
            views.setViewVisibility(R.id.iv_bg_art, View.VISIBLE)
            views.setImageViewBitmap(R.id.iv_bg_art, background)
        }
        views.setImageViewBitmap(R.id.iv_cover, drawVinyl(cover))
        // Both draws are done: the square source can go now.
        cover.recycle()
    }

    /**
     * Decodes the artwork Dart resolved on disk, downscaled to
     * [COVER_SIZE]. Returns null when the path is missing, unreadable or is
     * not an image, which is the signal to fall back to the vector disc.
     */
    private fun loadCoverBitmap(path: String?): Bitmap? {
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
        return Bitmap.createScaledBitmap(decoded, COVER_SIZE, COVER_SIZE, true)
            .also { if (it != decoded) decoded.recycle() }
    }

    /** Runs an optional widget step, logging instead of failing the widget. */
    private inline fun guarded(label: String, block: () -> Unit) {
        try {
            block()
        } catch (error: Throwable) {
            Log.w(TAG, "Widget step failed ($label)", error)
        }
    }

    companion object {
        private const val TAG = "BStreamWidget"
        private const val DEFAULT_TITLE = "Sin reproducción"
        private const val DEFAULT_ARTIST = "IVG Music"
        private const val DEFAULT_CLOCK = "0:00"
        private const val MAX_PROGRESS = 100

        // Bitmap sizes. Deliberately small: RemoteViews parcels its bitmaps
        // through the Binder, which has a hard size limit per transaction.
        private const val COVER_SIZE = 160
        private const val VINYL_SIZE = 160
        private const val BG_WIDTH = 160
        private const val BG_HEIGHT = 90
        private const val BG_BLUR_FACTOR = 8
        private const val BG_CORNER_RADIUS = 22f

        private val COLOR_VINYL = Color.parseColor("#121216")
        private val COLOR_LABEL = Color.parseColor("#1A1A22")
        private val COLOR_HOLE = Color.parseColor("#0A0A0E")
        private val COLOR_GROOVE = Color.parseColor("#26FFFFFF")
        private val COLOR_NOTE = Color.parseColor("#00F5D4")

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
            // A queue row jumps that many tracks forward, one media key each.
            QUEUE_1(
                action = "com.bstream.bstream_music.widget.action.QUEUE_1",
                uri = "musicwidget://playqueue1",
                requestCode = 4103,
                keyCodes = listOf(KeyEvent.KEYCODE_MEDIA_NEXT),
            ),
            QUEUE_2(
                action = "com.bstream.bstream_music.widget.action.QUEUE_2",
                uri = "musicwidget://playqueue2",
                requestCode = 4104,
                keyCodes = List(2) { KeyEvent.KEYCODE_MEDIA_NEXT },
            ),
            QUEUE_3(
                action = "com.bstream.bstream_music.widget.action.QUEUE_3",
                uri = "musicwidget://playqueue3",
                requestCode = 4105,
                keyCodes = List(3) { KeyEvent.KEYCODE_MEDIA_NEXT },
            ),
            QUEUE_4(
                action = "com.bstream.bstream_music.widget.action.QUEUE_4",
                uri = "musicwidget://playqueue4",
                requestCode = 4106,
                keyCodes = List(4) { KeyEvent.KEYCODE_MEDIA_NEXT },
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
