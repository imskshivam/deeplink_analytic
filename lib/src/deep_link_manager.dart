import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'event_model.dart';
import 'analytics_tracker.dart';
import 'config.dart';

class DeepLinkManager {
  static final DeepLinkManager _instance = DeepLinkManager._internal();
  factory DeepLinkManager() => _instance;
  DeepLinkManager._internal();

  final AnalyticsTracker _analytics = AnalyticsTracker();
  late DeepLinkConfig _config;
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  final List<DeepLinkHandler> _handlers = [];

  Future<void> initialize(DeepLinkConfig config) async {
    _config = config;
    _appLinks = AppLinks();
    await _analytics.initialize(config);
    await _setupDeepLinkStream();
    await _checkInitialUri();
  }

  Future<void> _setupDeepLinkStream() async {
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri? uri) {
        // Changed to Uri? parameter
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
      final Uri? initialUri = await _appLinks
          .getInitialLink(); // Explicit Uri? type
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

    // Check if we have a handler for this path
    for (final handler in _handlers) {
      if (handler.canHandle(deepLinkData)) {
        await handler.handle(deepLinkData);
        return;
      }
    }

    // Default handling
    await _navigateFromDeepLink(deepLinkData);
  }

  Future<void> _navigateFromDeepLink(DeepLinkData data) async {
    if (_config.debugMode) {
      print('Deep link received: ${data.originalUrl}');
      print('Path: ${data.path}');
      print('Query params: ${data.queryParameters}');
    }
    await _storeDeferredDeepLink(data.originalUrl);
  }

  Future<void> _storeDeferredDeepLink(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deferred_deep_link', url);
    } catch (e) {
      if (_config.debugMode) {
        print('Error storing deferred deep link: $e');
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
      final Map<String, dynamic> payload = {
        'destination': destination,
        if (campaign != null) 'campaign': campaign,
        if (source != null) 'source': source,
        if (medium != null) 'medium': medium,
        if (content != null) 'content': content,
        if (customParams != null) 'custom_params': customParams,
      };

      final response = await http.post(
        Uri.parse('${_config.baseUrl}'),
        headers: {
          'Authorization': '${_config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['deepLink'];
      } else {
        throw Exception(
          'Failed to create deep link: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      if (_config.debugMode) {
        print('Error creating deep link: $e');
      }
      rethrow;
    }
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
          print('Handled deferred deep link: $deferredLink');
        }
      }
    } catch (e) {
      if (_config.debugMode) {
        print('Error handling deferred deep link: $e');
      }
    }
  }

  Future<bool> launchDeepLink(
    String url, {
    bool useExternalBrowser = false,
  }) async {
    try {
      final Uri uri = Uri.parse(url);

      // Track the click before launching
      await _analytics.trackDeepLinkClick(url, destination: url);

      if (useExternalBrowser) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        return await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (_config.debugMode) {
        print('Error launching deep link: $e');
      }
      return false;
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

  // Method to get current deep link state
  Future<Map<String, dynamic>> getDeepLinkState() async {
    final prefs = await SharedPreferences.getInstance();
    final deferredLink = prefs.getString('deferred_deep_link');

    return {
      'hasDeferredLink': deferredLink != null && deferredLink.isNotEmpty,
      'deferredLink': deferredLink,
      'handlersCount': _handlers.length,
      'isInitialized': _config != null,
    };
  }

  void dispose() {
    _linkSubscription?.cancel();
    _analytics.dispose();
  }
}
