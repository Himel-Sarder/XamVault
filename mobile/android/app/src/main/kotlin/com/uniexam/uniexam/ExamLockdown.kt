package com.uniexam.uniexam

import android.app.Activity
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.provider.Settings
import android.view.Display
import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

/**
 * The Android side of secure exam mode (§37).
 *
 * What this can and cannot do is worth stating plainly, because the difference matters
 * (§38):
 *
 *  - `FLAG_SECURE` blocks the system screenshot path and blanks the window in the
 *    recents list and in most screen recorders. It does **not** stop a second phone
 *    pointed at the screen, and vendor-level capture tools on a rooted device can
 *    bypass it.
 *  - Lock Task ("kiosk") mode genuinely pins the app — but only when the app is a
 *    Device Owner, or has been allow-listed by one. On an ordinary personal phone
 *    `startLockTask` produces the *pinning confirmation* variant, which the student can
 *    dismiss. We attempt it, report which variant we got, and let the server record that.
 *
 * Everything here is best-effort and reports its own success, so the app never claims a
 * protection it did not actually get.
 */
class ExamLockdown(private val activity: Activity) {

    private var engaged = false

    /** Result of an attempt to lock down, reported verbatim to Flutter. */
    data class Status(
        val secureFlag: Boolean,
        val immersive: Boolean,
        val lockTask: Boolean,
        val lockTaskIsPinning: Boolean,
        val detail: String,
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "secureFlag" to secureFlag,
            "immersive" to immersive,
            "lockTask" to lockTask,
            "lockTaskIsPinning" to lockTaskIsPinning,
            "detail" to detail,
        )
    }

    fun enter(): Status {
        val secure = applySecureFlag(true)
        val immersive = applyImmersive(true)
        val (locked, pinning, detail) = startLockTask()
        engaged = true
        return Status(secure, immersive, locked, pinning, detail)
    }

    fun exit(): Status {
        stopLockTask()
        val secure = applySecureFlag(false)
        val immersive = applyImmersive(false)
        engaged = false
        return Status(!secure, !immersive, false, false, "Lockdown released")
    }

    /**
     * Steps out of lock task so the app can launch another one, and comes back.
     *
     * A pinned app cannot start the camera: Android refuses to bring another activity
     * to the front, and what the student sees is the exam apparently closing and
     * reopening. A PHOTO_ANSWER question requires exactly that launch, so the pin is
     * released for the length of the excursion and taken again afterwards.
     *
     * `FLAG_SECURE` is deliberately left on throughout. It is the one protection the
     * platform genuinely enforces on an unmanaged device, and there is no reason to
     * drop it while the camera is open.
     */
    fun suspendForExcursion(): Boolean {
        if (!engaged) return false
        stopLockTask()
        return true
    }

    /** Retakes the pin after an excursion. Reports whether it actually got it back. */
    fun resumeAfterExcursion(): Boolean {
        if (!engaged) return false
        val (locked, _, _) = startLockTask()
        return locked
    }

    fun isEngaged(): Boolean = engaged

    /**
     * Blocks screenshots and blanks the window in the recents switcher.
     *
     * The only one of these controls that is genuinely enforced by the platform on an
     * unmanaged device.
     */
    private fun applySecureFlag(on: Boolean): Boolean = try {
        if (on) {
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        true
    } catch (error: Exception) {
        false
    }

    /** Fullscreen with the status and navigation bars hidden. Cosmetic, not a control. */
    private fun applyImmersive(on: Boolean): Boolean = try {
        val controller = WindowInsetsControllerCompat(activity.window, activity.window.decorView)
        WindowCompat.setDecorFitsSystemWindows(activity.window, !on)
        if (on) {
            controller.hide(WindowInsetsCompat.Type.systemBars())
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        } else {
            controller.show(WindowInsetsCompat.Type.systemBars())
        }
        true
    } catch (error: Exception) {
        false
    }

    /**
     * Returns (locked, isMerelyPinning, humanReadableDetail).
     *
     * `isMerelyPinning` true means the student can leave by holding back+recents — the
     * unmanaged-device case. The server records this so an invigilator knows which kind
     * of lockdown was actually in force.
     */
    /**
     * True when this app owns the device, which is the only state in which Android
     * allows lock-task without a confirmation the student can dismiss.
     */
    fun isDeviceOwner(): Boolean = try {
        val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        dpm.isDeviceOwnerApp(activity.packageName)
    } catch (error: Exception) {
        false
    }

    /**
     * Allow-lists this app for lock task, so `startLockTask` locks silently.
     *
     * Only a Device Owner may call this. Without ownership there is no API that
     * suppresses the pinning confirmation -- that is the platform refusing to let any
     * app seize a phone unannounced, and it is a protection rather than a gap.
     */
    private fun permitLockTask(): Boolean = try {
        val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(activity, ExamAdminReceiver::class.java)
        dpm.setLockTaskPackages(admin, arrayOf(activity.packageName))
        true
    } catch (error: Exception) {
        false
    }

    private fun startLockTask(): Triple<Boolean, Boolean, String> = try {
        val manager = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val owned = isDeviceOwner()
        // On a provisioned device this is what turns the dismissible pin into a lock.
        val allowListed = if (owned) permitLockTask() else false

        activity.startLockTask()
        val state = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            manager.lockTaskModeState
        } else {
            ActivityManager.LOCK_TASK_MODE_NONE
        }
        when (state) {
            ActivityManager.LOCK_TASK_MODE_LOCKED ->
                Triple(true, false, "Locked by device policy")
            ActivityManager.LOCK_TASK_MODE_PINNED ->
                Triple(true, true, "Screen pinned; the student can still exit")
            else -> {
                val why = when {
                    owned && !allowListed -> "Device owner could not allow-list lock task"
                    owned -> "Lock task refused by policy"
                    else -> "Lock task unavailable: device is not provisioned"
                }
                Triple(false, false, why)
            }
        }
    } catch (error: Exception) {
        Triple(false, false, "Lock task unavailable: ${error.javaClass.simpleName}")
    }

    /**
     * Conditions the device can see but cannot prevent.
     *
     * Reported, never acted on. Developer mode on a student's own phone is ordinary and
     * means nothing by itself; it matters only as context beside something else, which
     * is exactly the judgement a human should be making rather than this class.
     */
    fun deviceConditions(): List<Pair<String, String>> {
        val found = mutableListOf<Pair<String, String>>()

        fun setting(key: String): Boolean = try {
            Settings.Global.getInt(activity.contentResolver, key, 0) != 0
        } catch (error: Exception) {
            false
        }

        if (setting(Settings.Global.DEVELOPMENT_SETTINGS_ENABLED)) {
            found += "DEVELOPER_MODE" to "Developer options are on"
        }
        if (setting(Settings.Global.ADB_ENABLED)) {
            found += "USB_DEBUGGING" to "USB debugging is on"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && activity.isInMultiWindowMode) {
            found += "SPLIT_SCREEN" to "The app is sharing the screen with another app"
        }
        try {
            val displays = (activity.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager)
                .displays
                .filter { it.displayId != Display.DEFAULT_DISPLAY }
            if (displays.isNotEmpty()) {
                found += "EXTERNAL_DISPLAY" to "A second display is attached"
            }
        } catch (error: Exception) {
            // Nothing to report; the absence of a reading is not itself a finding.
        }
        return found
    }

    private fun stopLockTask() {
        try {
            activity.stopLockTask()
        } catch (error: Exception) {
            // Not in lock task mode; nothing to release.
        }
    }
}
