class AnalyticsEvent {
  final String eventId;
  final String type;
  final String? userId;
  final String? sessionId;
  final DateTime timestamp;
  final Map<String, dynamic> properties;
  final Map<String, dynamic> deviceInfo;
  final Map<String, dynamic> appInfo;

  AnalyticsEvent({
    required this.type,
    this.userId,
    this.sessionId,
    this.properties = const {},
    this.deviceInfo = const {},
    this.appInfo = const {},
  })  : eventId = 'event_${DateTime.now().millisecondsSinceEpoch}',
        timestamp = DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'type': type,
      'userId': userId,
      'sessionId': sessionId,
      'timestamp': timestamp.toIso8601String(),
      'properties': properties,
      'deviceInfo': deviceInfo,
      'appInfo': appInfo,
    };
  }
}

class DeepLinkData {
  final String originalUrl;
  final String? path;
  final Map<String, String> queryParameters;
  final String? campaign;
  final String? source;
  final String? medium;
  final String? content;

  DeepLinkData({
    required this.originalUrl,
    this.path,
    this.queryParameters = const {},
    this.campaign,
    this.source,
    this.medium,
    this.content,
  });

  factory DeepLinkData.fromUri(Uri uri) {
    return DeepLinkData(
      originalUrl: uri.toString(),
      path: uri.path,
      queryParameters: uri.queryParameters,
      campaign: uri.queryParameters['utm_campaign'],
      source: uri.queryParameters['utm_source'],
      medium: uri.queryParameters['utm_medium'],
      content: uri.queryParameters['utm_content'],
    );
  }
}

abstract class DeepLinkHandler {
  bool canHandle(DeepLinkData data);
  Future<void> handle(DeepLinkData data);
}