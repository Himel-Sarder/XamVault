package com.uniexam.uniexam

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.os.Build
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
    private fun startLockTask(): Triple<Boolean, Boolean, String> = try {
        val manager = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val permitted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            manager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            false
        }
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
            else ->
                Triple(false, false, if (permitted) "Lock task refused" else "Lock task unavailable")
        }
    } catch (error: Exception) {
        Triple(false, false, "Lock task unavailable: ${error.javaClass.simpleName}")
    }

    private fun stopLockTask() {
        try {
            activity.stopLockTask()
        } catch (error: Exception) {
            // Not in lock task mode; nothing to release.
        }
    }
}
