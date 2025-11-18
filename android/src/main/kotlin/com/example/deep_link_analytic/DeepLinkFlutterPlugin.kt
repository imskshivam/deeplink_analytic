package com.yourcompany.deeplink

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONObject
import java.util.concurrent.Executors

class DeepLinkFlutterPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var referrerClient: InstallReferrerClient? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "deep_link_package")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getInstallReferrer" -> getInstallReferrer(result)
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "getInitialLink" -> getInitialLink(result)
            else -> result.notImplemented()
        }
    }

    private fun getInstallReferrer(result: Result) {
        try {
            referrerClient = InstallReferrerClient.newBuilder(context).build()
            referrerClient?.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    when (responseCode) {
                        InstallReferrerClient.InstallReferrerResponse.OK -> {
                            // Connection established
                            try {
                                val response = referrerClient?.installReferrer
                                val referrerData = JSONObject().apply {
                                    put("install_referrer", response?.installReferrer ?: "")
                                    put("referrer_click_timestamp", response?.referrerClickTimestampSeconds ?: 0)
                                    put("install_begin_timestamp", response?.installBeginTimestampSeconds ?: 0)
                                    put("referrer_click_timestamp_server", response?.referrerClickTimestampServerSeconds ?: 0)
                                    put("install_begin_timestamp_server", response?.installBeginTimestampServerSeconds ?: 0)
                                    put("install_version", response?.installVersion ?: "")
                                    put("google_play_instant", response?.googlePlayInstantParam ?: false)
                                }
                                result.success(referrerData.toString())
                            } catch (e: Exception) {
                                result.error("REFERRER_ERROR", "Failed to get referrer details", e.message)
                            } finally {
                                referrerClient?.endConnection()
                            }
                        }
                        InstallReferrerClient.InstallReferrerResponse.FEATURE_NOT_SUPPORTED -> {
                            result.error("NOT_SUPPORTED", "Install Referrer not supported", null)
                        }
                        InstallReferrerClient.InstallReferrerResponse.SERVICE_UNAVAILABLE -> {
                            result.error("SERVICE_UNAVAILABLE", "Service unavailable", null)
                        }
                        else -> {
                            result.error("UNKNOWN_ERROR", "Unknown error: $responseCode", null)
                        }
                    }
                }

                override fun onInstallReferrerServiceDisconnected() {
                    result.error("SERVICE_DISCONNECTED", "Service disconnected", null)
                }
            })
        } catch (e: Exception) {
            result.error("INIT_ERROR", "Failed to initialize referrer client", e.message)
        }
    }

    private fun getInitialLink(result: Result) {
        // Implementation for getting initial deep link
        result.success(null)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        referrerClient?.endConnection()
    }
}