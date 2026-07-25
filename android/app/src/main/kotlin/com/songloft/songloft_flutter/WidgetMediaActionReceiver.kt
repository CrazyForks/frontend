package com.songloft.songloft_flutter

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.KeyEvent

class WidgetMediaActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_PLAY_PAUSE = "com.songloft.songloft_flutter.ACTION_PLAY_PAUSE"
        const val ACTION_PREV = "com.songloft.songloft_flutter.ACTION_PREV"
        const val ACTION_NEXT = "com.songloft.songloft_flutter.ACTION_NEXT"
        const val ACTION_FAVORITE = "com.songloft.songloft_flutter.ACTION_FAVORITE"

        private val MEDIA_BUTTON_RECEIVER =
            ComponentName("com.songloft.songloft_flutter", "com.ryanheise.audioservice.MediaButtonReceiver")

        fun sendAction(context: Context, action: String) {
            val intent = Intent(context, WidgetMediaActionReceiver::class.java)
            intent.action = action
            context.sendBroadcast(intent)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action == ACTION_FAVORITE) {
            SongloftNowPlayingWidgetProvider.widgetActionChannel?.invokeMethod("onWidgetAction", "favorite")
            return
        }
        val keyCode = when (action) {
            ACTION_PREV -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            ACTION_NEXT -> KeyEvent.KEYCODE_MEDIA_NEXT
            else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
        }
        sendMediaButtonToReceiver(context, keyCode)
    }

    private fun sendMediaButtonToReceiver(context: Context, keyCode: Int) {
        val downIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = MEDIA_BUTTON_RECEIVER
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        context.sendBroadcast(downIntent)

        val upIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = MEDIA_BUTTON_RECEIVER
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_UP, keyCode))
        }
        context.sendBroadcast(upIntent)
    }
}