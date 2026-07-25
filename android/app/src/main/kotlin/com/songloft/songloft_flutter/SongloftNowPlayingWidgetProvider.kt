package com.songloft.songloft_flutter

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import com.bumptech.glide.Glide
import com.bumptech.glide.request.target.AppWidgetTarget
import io.flutter.plugin.common.MethodChannel

class SongloftNowPlayingWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_PLAY_PAUSE = "com.songloft.songloft_flutter.ACTION_PLAY_PAUSE"
        const val ACTION_PREV = "com.songloft.songloft_flutter.ACTION_PREV"
        const val ACTION_NEXT = "com.songloft.songloft_flutter.ACTION_NEXT"
        const val ACTION_FAVORITE = "com.songloft.songloft_flutter.ACTION_FAVORITE"

        var widgetActionChannel: MethodChannel? = null

        private var lastArtUrl: String = ""
        private var cachedPendingIntents: MutableMap<String, PendingIntent> = mutableMapOf()

        fun triggerUpdate(context: Context) {
            val intent = Intent(context, SongloftNowPlayingWidgetProvider::class.java)
            intent.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            val widgetManager = AppWidgetManager.getInstance(context)
            val ids = widgetManager.getAppWidgetIds(
                ComponentName(context, SongloftNowPlayingWidgetProvider::class.java)
            )
            intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            context.sendBroadcast(intent)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            updateWidget(context, appWidgetManager, id)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action ?: return
        when (action) {
            ACTION_PLAY_PAUSE, ACTION_PREV, ACTION_NEXT, ACTION_FAVORITE -> {
                WidgetMediaActionReceiver.sendAction(context, action)
            }
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val title = prefs.getString("widget_song_title", "Songloft") ?: "Songloft"
        val artist = prefs.getString("widget_song_artist", "") ?: ""
        val artUrl = prefs.getString("widget_song_art_url", "") ?: ""
        val isPlaying = prefs.getBoolean("widget_is_playing", false)
        val isFavorite = prefs.getBoolean("widget_is_favorite", false)
        val position = prefs.getInt("widget_position", 0).toLong()
        val duration = prefs.getInt("widget_duration", 0).toLong()

        val views = RemoteViews(context.packageName, R.layout.now_playing_widget)

        views.setTextViewText(R.id.widget_song_title, title)
        views.setTextViewText(R.id.widget_song_artist, artist)
        views.setViewVisibility(
            R.id.widget_song_artist,
            if (artist.isNotEmpty()) View.VISIBLE else View.GONE
        )

        val playPauseIcon = if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
        views.setImageViewResource(R.id.widget_btn_play_pause, playPauseIcon)

        val favIcon = if (isFavorite) R.drawable.ic_widget_favorite_filled else R.drawable.ic_widget_favorite
        views.setImageViewResource(R.id.widget_btn_favorite, favIcon)

        views.setTextViewText(R.id.widget_time, "${formatTime(position)}/${formatTime(duration)}")
        if (duration > 0) {
            val progress = ((position.toDouble() / duration.toDouble()) * 1000).toInt().coerceIn(0, 1000)
            views.setProgressBar(R.id.widget_progress, 1000, progress, false)
        } else {
            views.setProgressBar(R.id.widget_progress, 1000, 0, false)
        }

        views.setOnClickPendingIntent(
            R.id.widget_btn_prev,
            buildBroadcastPendingIntent(context, ACTION_PREV)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_play_pause,
            buildBroadcastPendingIntent(context, ACTION_PLAY_PAUSE)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_next,
            buildBroadcastPendingIntent(context, ACTION_NEXT)
        )
        views.setOnClickPendingIntent(
            R.id.widget_btn_favorite,
            buildBroadcastPendingIntent(context, ACTION_FAVORITE)
        )

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        views.setOnClickPendingIntent(
            R.id.widget_root,
            PendingIntent.getActivity(
                context, 1, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        )

        if (artUrl.isNotEmpty() && artUrl != lastArtUrl) {
            lastArtUrl = artUrl
            val appWidgetTarget = AppWidgetTarget(
                context, R.id.widget_album_art, views, appWidgetId
            )
            Glide.with(context.applicationContext)
                .asBitmap()
                .load(artUrl)
                .override(208, 208)
                .centerCrop()
                .into(appWidgetTarget)
        } else if (artUrl.isEmpty()) {
            lastArtUrl = ""
            views.setImageViewResource(R.id.widget_album_art, R.mipmap.ic_launcher)
        }

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun formatTime(ms: Long): String {
        val totalSeconds = ms / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return "${minutes}:${seconds.toString().padStart(2, '0')}"
    }

    private fun buildBroadcastPendingIntent(context: Context, action: String): PendingIntent {
        cachedPendingIntents[action]?.let { return it }
        val intent = Intent(context, SongloftNowPlayingWidgetProvider::class.java)
        intent.action = action
        val requestCode = when (action) {
            ACTION_PREV -> 2
            ACTION_NEXT -> 3
            ACTION_FAVORITE -> 4
            else -> 0
        }
        val pi = PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        cachedPendingIntents[action] = pi
        return pi
    }
}