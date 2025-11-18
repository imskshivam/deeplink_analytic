import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'event_model.dart';
import 'analytics_tracker.dart';
import 'config.dart';

class DeepLinkManager {
  static final DeepLinkManager _instance = DeepLinkManager._internal();
  factory DeepLinkManager() => _instance;
  DeepLinkManager._internal();

  final AnalyticsTracker _analytics = AnalyticsTracker();
  static const MethodChannel _channel = MethodChannel('hippo_analytic');
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  final List<DeepLinkHandler> _handlers = [];
  late DeepLinkConfig _config;
  int _linkCounter = 0;
  bool _isInitialized = false;

  Future<void> initialize(DeepLinkConfig config) async {
    if (_isInitialized) return;

    _config = config;
    _appLinks = AppLinks();
    await _analytics.initialize(config);
    await _setupDeepLinkStream();
    await _checkInitialUri();
    await _handleInstallReferrer();
    _isInitialized = true;

    if (_config.debugMode) {
      print('✅ DeepLinkManager initialized');
    }
  }

  Future<Map<String, dynamic>?> getInstallReferrer() async {
    try {
      final String? referrerData = await _channel.invokeMethod('getInstallReferrer');
      if (referrerData != null && referrerData.isNotEmpty) {
        final Map<String, dynamic> data = jsonDecode(referrerData);

        await _analytics.trackEvent(
          'install_referrer_received',
          properties: {
            'referrer': data['install_referrer'],
            'click_timestamp': data['referrer_click_timestamp'],
            'install_timestamp': data['install_begin_timestamp'],
            'platform': defaultTargetPlatform.toString(),
          },
        );

        if (_config.debugMode) {
          print('📱 Install Referrer: ${data['install_referrer']}');
        }

        return data;
      }
    } on PlatformException catch (e) {
      if (_config.debugMode) {
        print('❌ Install Referrer Error: ${e.message}');
      }

      await _analytics.trackEvent(
        'install_referrer_error',
        properties: {
          'error_code': e.code,
          'error_message': e.message,
          'platform': defaultTargetPlatform.toString(),
        },
      );
    } catch (e) {
      if (_config.debugMode) {
        print('❌ Unexpected Install Referrer Error: $e');
      }
    }
    return null;
  }

  Future<void> _handleInstallReferrer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasProcessedReferrer = prefs.getBool('has_processed_install_referrer') ?? false;

      if (!hasProcessedReferrer) {
        final referrerData = await getInstallReferrer();

        if (referrerData != null && referrerData['install_referrer'] != null) {
          final String? installReferrer = referrerData['install_referrer']?.toString();

          if (installReferrer != null && installReferrer.isNotEmpty) {
            await _processInstallReferrer(installReferrer);
            await prefs.setBool('has_processed_install_referrer', true);

            if (_config.debugMode) {
              print('✅ Install referrer processed: $installReferrer');
            }
          }
        }
        await prefs.setBool('has_processed_install_referrer', true);
      }
    } catch (e) {
      if (_config.debugMode) {
        print('❌ Error handling install referrer: $e');
      }
    }
  }

  Future<void> _processInstallReferrer(String installReferrer) async {
    try {
      final params = Uri.splitQueryString(installReferrer);
      final mockUrl = 'https://install.referrer?$installReferrer';
      final uri = Uri.parse(mockUrl);

      await _analytics.trackEvent(
        'install_referrer_processed',
        properties: {
          'raw_referrer': installReferrer,
          'utm_source': params['utm_source'],
          'utm_medium': params['utm_medium'],
          'utm_campaign': params['utm_campaign'],
          'utm_content': params['utm_content'],
          'utm_term': params['utm_term'],
        },
      );

      await _handleDeepLink(uri);
    } catch (e) {
      if (_config.debugMode) {
        print('❌ Error processing install referrer: $e');
      }
    }
  }

  Future<void> _setupDeepLinkStream() async {
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri? uri) {
        if (uri != null) {
          _handleDeepLink(uri);
        }
      },
      onError: (err) {
        if (_config.debugMode) {
          print('Deep link stream error: $err');
        }
      },
    );
  }

  Future<void> _checkInitialUri() async {
    try {
      final Uri? initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        await _handleDeepLink(initialUri);
      }
    } catch (e) {
      if (_config.debugMode) {
        print('Initial URI error: $e');
      }
    }
  }

  Future<void> _handleDeepLink(Uri uri) async {
    final deepLinkData = DeepLinkData.fromUri(uri);

    await _analytics.trackEvent(
      'deep_link_received',
      properties: {
        'url': deepLinkData.originalUrl,
        'path': deepLinkData.path,
        'query_parameters': deepLinkData.queryParameters,
      },
    );

    if (_config.debugMode) {
      print('🔗 Deep link received: ${uri.toString()}');
    }

    await _storeDeferredDeepLink(deepLinkData.originalUrl);

    for (final handler in _handlers) {
      if (handler.canHandle(deepLinkData)) {
        await handler.handle(deepLinkData);
        return;
      }
    }

    await _navigateFromDeepLink(deepLinkData);
  }

  Future<void> _navigateFromDeepLink(DeepLinkData data) async {
    if (_config.debugMode) {
      print('🧭 Navigating from deep link: ${data.originalUrl}');
      print('📍 Path: ${data.path}');
      print('🔍 Query params: ${data.queryParameters}');
    }
  }

  Future<void> _storeDeferredDeepLink(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deferred_deep_link', url);

      if (_config.debugMode) {
        print('💾 Stored deferred deep link: $url');
      }
    } catch (e) {
      if (_config.debugMode) {
        print('❌ Error storing deferred deep link: $e');
      }
    }
  }

  Future<String> createDeepLink({
    required String destination,
    String? campaign,
    String? source,
    String? medium,
    String? content,
    Map<String, String>? customParams,
  }) async {
    try {
      _linkCounter++;
      final linkId = 'link_$_linkCounter';

      final mockDeepLink = _buildMockDeepLink(
        linkId: linkId,
        destination: destination,
        campaign: campaign,
        source: source,
        medium: medium,
        content: content,
        customParams: customParams,
      );

      await _storeCreatedDeepLink(
        id: linkId,
        deepLink: mockDeepLink,
        destination: destination,
        campaign: campaign,
        source: source,
        medium: medium,
        content: content,
        customParams: customParams,
      );

      await _analytics.trackEvent(
        'deep_link_created',
        properties: {
          'link_id': linkId,
          'deep_link': mockDeepLink,
          'destination': destination,
          'campaign': campaign,
          'source': source,
          'medium': medium,
          'content': content,
        },
      );

      if (_config.debugMode) {
        print('🔗 Created deep link: $mockDeepLink');
      }

      return mockDeepLink;
    } catch (e) {
      if (_config.debugMode) {
        print('❌ Error creating deep link: $e');
      }
      rethrow;
    }
  }

  String _buildMockDeepLink({
    required String linkId,
    required String destination,
    String? campaign,
    String? source,
    String? medium,
    String? content,
    Map<String, String>? customParams,
  }) {
    final params = <String, String>{
      'dest': Uri.encodeComponent(destination),
      if (campaign != null) 'utm_campaign': campaign,
      if (source != null) 'utm_source': source,
      if (medium != null) 'utm_medium': medium,
      if (content != null) 'utm_content': content,
      ...?customParams,
    };

    final queryString = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    return 'https://deeplink.example.com/link/$linkId?$queryString';
  }

  Future<void> _storeCreatedDeepLink({
    required String id,
    required String deepLink,
    required String destination,
    String? campaign,
    String? source,
    String? medium,
    String? content,
    Map<String, String>? customParams,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final existingLinksJson = prefs.getStringList('created_deep_links') ?? [];
    final List<Map<String, dynamic>> existingLinks = existingLinksJson
        .map((json) => jsonDecode(json) as Map<String, dynamic>)
        .toList();

    final linkData = {
      'id': id,
      'deep_link': deepLink,
      'destination': destination,
      'campaign': campaign,
      'source': source,
      'medium': medium,
      'content': content,
      'custom_params': customParams,
      'created_at': DateTime.now().toIso8601String(),
      'click_count': 0,
    };

    existingLinks.add(linkData);

    final updatedJson = existingLinks.map((e) => jsonEncode(e)).toList();
    await prefs.setStringList('created_deep_links', updatedJson);
  }

  Future<void> handleDeferredDeepLink() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deferredLink = prefs.getString('deferred_deep_link');

      if (deferredLink != null && deferredLink.isNotEmpty) {
        final uri = Uri.parse(deferredLink);
        await _handleDeepLink(uri);
        await prefs.remove('deferred_deep_link');

        if (_config.debugMode) {
          print('🔄 Handled deferred deep link: $deferredLink');
        }
      }
    } catch (e) {
      if (_config.debugMode) {
        print('❌ Error handling deferred deep link: $e');
      }
    }
  }

  Future<void> checkPendingInstallReferrer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingReferrer = prefs.getString('pending_install_referrer');

      if (pendingReferrer != null && pendingReferrer.isNotEmpty) {
        await _processInstallReferrer(pendingReferrer);
        await prefs.remove('pending_install_referrer');

        if (_config.debugMode) {
          print('✅ Processed pending install referrer: $pendingReferrer');
        }
      }
    } catch (e) {
      if (_config.debugMode) {
        print('❌ Error checking pending install referrer: $e');
      }
    }
  }

  Future<void> simulateAppInstall(String referrerUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_install_referrer', referrerUrl);
      await prefs.setBool('has_processed_install_referrer', false);

      await _handleInstallReferrer();

      if (_config.debugMode) {
        print('🎯 Simulated app install with referrer: $referrerUrl');
      }
    } catch (e) {
      if (_config.debugMode) {
        print('❌ Error simulating app install: $e');
      }
    }
  }

  void addHandler(DeepLinkHandler handler) {
    _handlers.add(handler);
  }

  void removeHandler(DeepLinkHandler handler) {
    _handlers.remove(handler);
  }

  void clearHandlers() {
    _handlers.clear();
  }

  Future<void> trackClick(String linkId, {String? destination}) async {
    await _analytics.trackDeepLinkClick(linkId, destination: destination);
  }

  Future<void> trackConversion(
    String linkId,
    double value, {
    Map<String, dynamic>? metadata,
  }) async {
    await _analytics.trackConversion(linkId, value, metadata: metadata);
  }

  Future<Map<String, dynamic>> getDeepLinkState() async {
    final prefs = await SharedPreferences.getInstance();
    final deferredLink = prefs.getString('deferred_deep_link');
    final pendingReferrer = prefs.getString('pending_install_referrer');
    final hasProcessedReferrer = prefs.getBool('has_processed_install_referrer') ?? false;

    return {
      'hasDeferredLink': deferredLink != null && deferredLink.isNotEmpty,
      'deferredLink': deferredLink,
      'hasPendingInstallReferrer': pendingReferrer != null && pendingReferrer.isNotEmpty,
      'pendingInstallReferrer': pendingReferrer,
      'hasProcessedInstallReferrer': hasProcessedReferrer,
      'handlersCount': _handlers.length,
      'isInitialized': _isInitialized,
    };
  }

  void dispose() {
    _linkSubscription?.cancel();
    _analytics.dispose();
  }
}