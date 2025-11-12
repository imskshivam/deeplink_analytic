package com.example.deep_link_analytic

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class DeepLinkFlutterPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var context: Context? = null

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "deep_link_package")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "getInitialLink" -> {
                val initialLink = getInitialLink()
                result.success(initialLink)
            }
            "trackEvent" -> {
                // Handle event tracking from Flutter
                val eventType = call.argument<String>("eventType")
                val properties = call.argument<Map<String, Any>>("properties")
                // Process the event
                result.success(null)
            }
            "createDeepLink" -> {
                val destination = call.argument<String>("destination")
                val campaign = call.argument<String>("campaign")
                val source = call.argument<String>("source")
                val medium = call.argument<String>("medium")
                val content = call.argument<String>("content")
                
                // Here you would call your backend to create the deep link
                // For now, return a mock response
                result.success("https://yourdomain.com/l/abc123")
            }
            else -> result.notImplemented()
        }
    }

    private fun getInitialLink(): String? {
        activity?.intent?.data?.let { uri ->
            return uri.toString()
        }
        return null
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // ActivityAware methods with correct signatures
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        // You can also register for activity results if needed
        // binding.addActivityResultListener(activityResultListener)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }
}