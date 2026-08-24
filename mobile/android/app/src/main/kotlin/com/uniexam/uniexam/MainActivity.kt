package com.uniexam.uniexam

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Flutter to the Android security APIs (§37).
 *
 * Two channels: one Flutter calls to enter or leave lockdown, and one this class pushes
 * observations up. Observations are *reported*, never acted on here — deciding what a
 * backgrounded app means is a human's job (§38).
 */
class MainActivity : FlutterActivity() {

    private lateinit var lockdown: ExamLockdown
    private var control: MethodChannel? = null
    private var events: MethodChannel? = null

    /** Set while an exam is running, so lifecycle noise outside an exam is ignored. */
    private var examRunning = false
    private var backgroundedAt: Long? = null

    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var timeChangeReceiver: android.content.BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        lockdown = ExamLockdown(this)

        control = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL)
        events = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)

        control?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterExamLockdown" -> {
                    examRunning = true
                    registerWatchers()
                    result.success(lockdown.enter().toMap())
                }
                "exitExamLockdown" -> {
                    examRunning = false
                    unregisterWatchers()
                    result.success(lockdown.exit().toMap())
                }
                "isSupported" -> result.success(true)
                "isEngaged" -> result.success(lockdown.isEngaged())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Swallows the back gesture while an exam is running.
     *
     * FlutterActivity extends plain [android.app.Activity], so there is no
     * `OnBackPressedDispatcher` to register with; overriding this is the hook that
     * actually exists. Flutter's own `PopScope` covers the widget tree, and this covers
     * the activity — a student must not be able to reverse out of a paper by reflex.
     */
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (examRunning) return
        super.onBackPressed()
    }

    override fun onPause() {
        super.onPause()
        if (examRunning) {
            backgroundedAt = System.currentTimeMillis()
            report("APP_BACKGROUND", emptyMap())
        }
    }

    override fun onResume() {
        super.onResume()
        if (examRunning) {
            val away = backgroundedAt?.let { System.currentTimeMillis() - it }
            backgroundedAt = null
            report("APP_FOREGROUND", if (away != null) mapOf("away_ms" to away) else emptyMap())
        }
    }

    override fun onDestroy() {
        unregisterWatchers()
        super.onDestroy()
    }

    private fun report(eventType: String, metadata: Map<String, Any>) {
        events?.invokeMethod("onSecurityEvent", mapOf("event_type" to eventType, "metadata" to metadata))
    }

    private fun registerWatchers() {
        registerNetworkWatcher()
        registerTimeChangeWatcher()
    }

    private fun registerNetworkWatcher() {
        if (networkCallback != null) return
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = report("NETWORK_RECONNECT", emptyMap())
            override fun onLost(network: Network) = report("NETWORK_DISCONNECT", emptyMap())
        }
        try {
            manager.registerDefaultNetworkCallback(callback)
            networkCallback = callback
        } catch (error: Exception) {
            // Nothing to watch; the absence is not itself an exam problem.
        }
    }

    private fun registerTimeChangeWatcher() {
        if (timeChangeReceiver != null) return
        val receiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                // Recorded for the invigilator. The exam clock is the server's, so a
                // device time change does not alter the remaining time (§34).
                report("DEVICE_TIME_CHANGE", emptyMap())
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
        }
        registerReceiver(receiver, filter)
        timeChangeReceiver = receiver
    }

    private fun unregisterWatchers() {
        networkCallback?.let {
            try {
                val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                manager.unregisterNetworkCallback(it)
            } catch (error: Exception) {
                // Already gone.
            }
        }
        networkCallback = null

        timeChangeReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (error: Exception) {
                // Already gone.
            }
        }
        timeChangeReceiver = null
    }

    companion object {
        private const val CONTROL_CHANNEL = "com.uniexam/exam_security"
        private const val EVENT_CHANNEL = "com.uniexam/exam_events"
    }
}
