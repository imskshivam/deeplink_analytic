import 'package:flutter/material.dart';
import 'package:hippo_analytic/analytics_tracker.dart';
import 'package:hippo_analytic/config.dart';
import 'package:hippo_analytic/deep_link_manager.dart';
import 'package:hippo_analytic/event_model.dart';
import 'package:hippo_analytic/widgets/deep_link_wrapper.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // The DeepLinkWrapper initializes the manager with your configuration
    return DeepLinkWrapper(
      config: DeepLinkConfig(
        apiKey: 'your_api_key',
        // The baseUrl should point to your server root
        baseUrl: 'http://192.168.1.24:5000',
        debugMode: true, // Enable debug prints
        enableAnalytics: true, // Ensure analytics are enabled
      ),
      child: MaterialApp(title: 'Deep Link Tester', home: HomePage()),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Use the singleton instance of the manager
  final DeepLinkManager _deepLinkManager = DeepLinkManager();

  @override
  void initState() {
    super.initState();
    // No need to call initialize() here, DeepLinkWrapper does it for you.
    _setupDeepLinkHandlers();

    // After initialization, you can handle any link that opened the app
    _deepLinkManager.handleDeferredDeepLink();
  }

  void _setupDeepLinkHandlers() {
    _deepLinkManager.addHandler(ProductDeepLinkHandler());
  }

  // Creates a deep link and prints it to the console
  Future<void> _createDeepLink() async {
    print("--- Tapped: Create Deep Link ---");
    try {
      final deepLink = await _deepLinkManager.createDeepLink(
        destination: 'https://myapp.com/product/123',
        campaign: 'summer_sale',
        source: 'facebook',
        medium: 'social',
      );

      print('✅ Created deep link (printed in Flutter console): $deepLink');
      print("Check your backend console to see the request to /api/v1/links");
    } catch (e) {
      print('❌ Error creating deep link: $e');
    }
  }

  // Simulates a new app install with a referrer URL
  Future<void> _simulateInstall() async {
    print("--- Tapped: Simulate Install ---");
    const referrer =
        'utm_source=google&utm_medium=cpc&utm_campaign=new_user_promo';
    // await _deepLinkManager.simulateAppInstall(referrer);
    print('✅ Simulated install with referrer: "$referrer"');
    print(
      "This triggers 'install_referrer_received' and 'install_referrer_processed' events.",
    );
  }

  // Tracks a custom analytics event
  Future<void> _trackCustomEvent() async {
    print("--- Tapped: Track Custom Event ---");
    // Use the AnalyticsTracker singleton to track any event
    await AnalyticsTracker().trackEvent(
      'button_click',
      properties: {
        'button_id': 'custom_event_button',
        'page': 'home',
        'is_testing': true,
      },
    );
    print("✅ 'button_click' event added to the queue.");
    print("Events will be sent to the backend in a batch.");
  }

  // Gets and prints the current internal state of the DeepLinkManager
  Future<void> _checkState() async {
    print("--- Tapped: Check State ---");
    final state = await _deepLinkManager.getDeepLinkState();
    print("✅ Current DeepLinkManager State:");
    // Simple print loop for better readability
    state.forEach((key, value) {
      print("  - $key: $value");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Deep Link & Analytics Test')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: _createDeepLink,
                child: Text('1. Create Deep Link'),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: _simulateInstall,
                child: Text('2. Simulate App Install'),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: _trackCustomEvent,
                child: Text('3. Track Custom Event'),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: _checkState,
                child: Text('4. Check Internal State'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _deepLinkManager.dispose();
    super.dispose();
  }
}

// Your handler remains the same
class ProductDeepLinkHandler extends DeepLinkHandler {
  @override
  bool canHandle(DeepLinkData data) {
    return data.path?.contains('product') == true;
  }

  @override
  Future<void> handle(DeepLinkData data) async {
    final productId = data.path?.split('/').last;
    print('✅ Navigating to product with ID: $productId from deep link.');
    // In a real app, you would navigate to the product page here.
  }
}
