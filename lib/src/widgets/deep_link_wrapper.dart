import 'package:flutter/material.dart';
import 'package:hippo_analytic/src/analytics_tracker.dart';
import 'package:hippo_analytic/src/config.dart';
import 'package:hippo_analytic/src/deep_link_manager.dart';
import 'package:hippo_analytic/src/event_model.dart';

class DeepLinkWrapper extends StatefulWidget {
  final DeepLinkConfig config;
  final Widget child;
  final bool enableScreenTracking;
  final List<DeepLinkHandler>? customHandlers;

  const DeepLinkWrapper({
    Key? key,
    required this.config,
    required this.child,
    this.enableScreenTracking = true,
    this.customHandlers,
  }) : super(key: key);

  @override
  _DeepLinkWrapperState createState() => _DeepLinkWrapperState();
}

class _DeepLinkWrapperState extends State<DeepLinkWrapper>
    with WidgetsBindingObserver {
  final DeepLinkManager _deepLinkManager = DeepLinkManager();
  final AnalyticsTracker _analytics = AnalyticsTracker();

  @override
  void initState() {
    super.initState();
    _initializeSDK();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _initializeSDK() async {
    await _deepLinkManager.initialize(widget.config);

    widget.customHandlers?.forEach(_deepLinkManager.addHandler);

    await _deepLinkManager.handleDeferredDeepLink();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _analytics.trackAppForeground();
        _deepLinkManager.handleDeferredDeepLink();
        break;
      case AppLifecycleState.paused:
        _analytics.trackAppBackground();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinkManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
