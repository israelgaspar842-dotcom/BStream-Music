package com.bstream.bstream_music

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.KeyEvent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class MusicWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val views = RemoteViews(context.packageName, R.layout.music_widget)
        views.setTextViewText(
            R.id.tv_title,
            widgetData.getString("title", "Sin reproducción"),
        )
        views.setTextViewText(
            R.id.tv_artist,
            widgetData.getString("artist", "IVG Music"),
        )
        // Play/pause toggle. The tap is broadcast back to this provider, which
        // relays it into the media session that audio_service owns. Routing the
        // relay here instead of through home_widget's isolated background
        // engine is deliberate: that engine is created without a plugin
        // registrant, so no audio plugin is reachable from it.
        views.setOnClickPendingIntent(
            R.id.btn_play,
            PendingIntent.getBroadcast(
                context,
                REQUEST_CODE_TOGGLE_PLAYBACK,
                Intent(context, MusicWidgetProvider::class.java).apply {
                    action = ACTION_TOGGLE_PLAYBACK
                    // `data` keeps the intent distinct so FLAG_UPDATE_CURRENT
                    // refreshes this PendingIntent instead of stacking copies.
                    data = Uri.parse("musicwidget://playpause")
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        appWidgetManager.updateAppWidget(appWidgetIds, views)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE_PLAYBACK) {
            togglePlayback(context)
            return
        }
        super.onReceive(context, intent)
    }

    /**
     * Forwards the widget tap as a media button, the same route the lock screen
     * buttons, the notification and Bluetooth headsets take.
     *
     * androidx resolves the media browser service on its own and delivers the
     * key event through the session, so this works whether or not the Flutter
     * UI is alive, as long as the audio session exists.
     */
    private fun togglePlayback(context: Context) {
        val keyEvent = KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
        val mediaButtonIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(
                context.packageName,
                "com.ryanheise.audioservice.MediaButtonReceiver",
            )
            putExtra(Intent.EXTRA_KEY_EVENT, keyEvent)
        }
        context.sendBroadcast(mediaButtonIntent)
    }

    companion object {
        private const val ACTION_TOGGLE_PLAYBACK =
            "com.bstream.bstream_music.widget.action.TOGGLE_PLAYBACK"
        private const val REQUEST_CODE_TOGGLE_PLAYBACK = 4101
    }
}
