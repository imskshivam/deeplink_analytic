class DeepLinkConfig {
  final String apiKey;
  final String baseUrl;
  final bool enableAnalytics;
  final bool trackScreenViews;
  final bool trackTaps;
  final bool debugMode;

  const DeepLinkConfig({
    required this.apiKey,
     required this.baseUrl,
    this.enableAnalytics = true,
    this.trackScreenViews = true,
    this.trackTaps = false,
    this.debugMode = false,
  });
}