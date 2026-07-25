package com.songloft.songloft_flutter

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 桌面小组件动作桥接层。
 *
 * 小组件按钮（上一曲/播放/下一曲/收藏）点击时，原生 BroadcastReceiver 通过
 * SongloftNowPlayingWidgetProvider.widgetActionChannel 调用此 MethodChannel，
 * Dart 侧收到回调后执行对应逻辑，无需启动 Activity。
 */
class WidgetActionPlugin(context: Context, flutterEngine: FlutterEngine) {

    companion object {
        private const val CHANNEL = "com.songloft/widget_action"
    }

    init {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { _, _ -> }
        SongloftNowPlayingWidgetProvider.widgetActionChannel = channel
    }
}