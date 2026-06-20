import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../features/settings/data/settings_api.dart';
import 'app_preferences.dart';

Timer? _pushDebounceTimer;

/// 登录成功后从服务端拉取偏好并覆盖本地。
/// 服务端全是默认值（首次使用）时反向推送本地值。
Future<void> syncPreferencesFromServer(Dio dio) async {
  try {
    final prefs = await AppPreferences.create();
    final api = SettingsApi(dio: dio);
    final serverPrefs = await api.getUserPreferences();
    if (serverPrefs.isAllDefaults()) {
      await api.updateUserPreferences(_collectLocal(prefs));
    } else {
      await _applyToLocal(prefs, serverPrefs);
    }
  } catch (e) {
    debugPrint('[PreferenceSync] sync from server failed: $e');
  }
}

/// 将当前本地偏好推送到服务端（防抖 500ms，fire-and-forget）。
void pushPreferencesToServer(Dio dio) {
  _pushDebounceTimer?.cancel();
  _pushDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
    try {
      final prefs = await AppPreferences.create();
      final api = SettingsApi(dio: dio);
      await api.updateUserPreferences(_collectLocal(prefs));
    } catch (e) {
      debugPrint('[PreferenceSync] push failed: $e');
    }
  });
}

UserPreferences _collectLocal(AppPreferences prefs) {
  final themeModeStr = switch (prefs.getThemeMode()) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
  return UserPreferences(
    themeMode: themeModeStr,
    playMode: prefs.getPlayMode(),
    playlistViewMode: prefs.getPlaylistViewMode(),
    audioQuality: prefs.getAudioQuality(),
    localCacheMaxSize: prefs.getLocalCacheMaxSize(),
    volume: prefs.getVolume(),
  );
}

Future<void> _applyToLocal(
  AppPreferences prefs,
  UserPreferences serverPrefs,
) async {
  final themeMode = switch (serverPrefs.themeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  await prefs.setThemeMode(themeMode);
  await prefs.setPlayMode(serverPrefs.playMode);
  await prefs.setPlaylistViewMode(serverPrefs.playlistViewMode);
  await prefs.setAudioQuality(serverPrefs.audioQuality);
  await prefs.setLocalCacheMaxSize(serverPrefs.localCacheMaxSize);
  await prefs.setVolume(serverPrefs.volume);
}
