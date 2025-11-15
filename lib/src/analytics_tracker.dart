import 'dart:async';
import 'dart:convert'; 
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'event_model.dart';
import 'config.dart';

class AnalyticsTracker {
  static final AnalyticsTracker _instance = AnalyticsTracker._internal();
  factory AnalyticsTracker() => _instance;
  AnalyticsTracker._internal();

  late DeepLinkConfig _config;
  late String _userId;
  late String _sessionId;
  final List<AnalyticsEvent> _eventQueue = [];
  bool _isInitialized = false;
  Timer? _flushTimer;

  Future<void> initialize(DeepLinkConfig config) async {
    _config = config;
    await _initializeUser();
    await _initializeSession();
    _startFlushTimer();
    _isInitialized = true;

    await trackAppLaunch();
  }

  Future<void> _initializeUser() async {
    final prefs = await SharedPreferences.getInstance();
    _userId =
        prefs.getString('deeplink_user_id') ??
        'user_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString('deeplink_user_id', _userId);
  }

  Future<void> _initializeSession() async {
    _sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    await trackEvent('session_start');
  }

  Future<void> trackEvent(
    String eventType, {
    Map<String, dynamic> properties = const {},
  }) async {
    if (!_isInitialized || !_config.enableAnalytics) return;

    final deviceInfo = await _getDeviceInfo();
    final appInfo = await _getAppInfo();

    final event = AnalyticsEvent(
      type: eventType,
      userId: _userId,
      sessionId: _sessionId,
      properties: properties,
      deviceInfo: deviceInfo,
      appInfo: appInfo,
    );

    _eventQueue.add(event);

    if (_eventQueue.length >= 10) {
      await _flushEvents();
    }
  }

  Future<void> trackScreenView(String screenName) async {
    await trackEvent('screen_view', properties: {'screen_name': screenName});
  }

  Future<void> trackTap(
    String elementId, {
    String? elementType,
    String? text,
  }) async {
    await trackEvent(
      'tap',
      properties: {
        'element_id': elementId,
        'element_type': elementType,
        'text': text,
      },
    );
  }

  Future<void> trackDeepLinkClick(String linkId, {String? destination}) async {
    await trackEvent(
      'deep_link_click',
      properties: {'link_id': linkId, 'destination': destination},
    );
  }

  Future<void> trackConversion(
    String linkId,
    double value, {
    Map<String, dynamic>? metadata,
  }) async {
    await trackEvent(
      'conversion',
      properties: {'link_id': linkId, 'value': value, ...?metadata},
    );
  }

  Future<void> trackAppLaunch() async {
    await trackEvent('app_launch');
  }

  Future<void> trackAppBackground() async {
    await trackEvent('app_background');
    await _flushEvents();
  }

  Future<void> trackAppForeground() async {
    await _initializeSession();
    await trackEvent('app_foreground');
  }

  void _startFlushTimer() {
    _flushTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _flushEvents();
    });
  }

  Future<void> _flushEvents() async {
    if (_eventQueue.isEmpty) return;

    final List<AnalyticsEvent> eventsToSend = List<AnalyticsEvent>.from(
      _eventQueue,
    );
    _eventQueue.clear();

    try {
      if (_config.debugMode) {
        print('📤 Attempting to send ${eventsToSend.length} events...');
      }

      final response = await http.post(
        // <-- FIX 2: Corrected the endpoint URL
        Uri.parse('${_config.baseUrl}/api/v1/events'), 
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_config.apiKey}', // Also good practice to send API key
        },
        body: jsonEncode({
          'events': eventsToSend.map((e) => e.toJson()).toList(),
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (_config.debugMode) {
          print('✅ Successfully sent ${eventsToSend.length} events.');
        }
        // <-- FIX 3: Do NOT re-add events on success. The events are sent.
      } else {
        if (_config.debugMode) {
          print('⚠️ Failed to send events. Status: ${response.statusCode}. Re-queuing events.');
        }
        _eventQueue.addAll(eventsToSend); // Re-add events if server returns an error
      }
    } catch (e) {
      // <-- FIX 3: Only re-add events if an exception occurs (e.g., no network)
      _eventQueue.addAll(eventsToSend); 
      if (_config.debugMode) {
        print('❌ Failed to send events due to an error: $e. Re-queuing events.');
      }
    }
  }

  Future<Map<String, dynamic>> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    final packageInfo = await PackageInfo.fromPlatform();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidInfo = await deviceInfo.androidInfo;
      return {
        'platform': 'android',
        'os_version': androidInfo.version.release,
        'device_model': androidInfo.model,
        'device_brand': androidInfo.brand,
        'app_version': packageInfo.version,
        'app_build': packageInfo.buildNumber,
      };
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return {
        'platform': 'ios',
        'os_version': iosInfo.systemVersion,
        'device_model': iosInfo.utsname.machine,
        'device_name': iosInfo.name,
        'app_version': packageInfo.version,
        'app_build': packageInfo.buildNumber,
      };
    }

    return {'platform': 'unknown', 'app_version': packageInfo.version};
  }

  Future<Map<String, dynamic>> _getAppInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return {
      'app_name': packageInfo.appName,
      'package_name': packageInfo.packageName,
      'version': packageInfo.version,
      'build_number': packageInfo.buildNumber,
    };
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushEvents();
  }
}