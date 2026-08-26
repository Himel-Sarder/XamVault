package com.uniexam.uniexam

import android.app.admin.DeviceAdminReceiver

/**
 * Present so the app *can* be made a Device Owner. It grants nothing by itself.
 *
 * Android will not let an app pin itself without a confirmation dialog unless it owns
 * the device. Provisioning is deliberately hard — a factory-reset device and one adb
 * command, before any account is added — because an app that could silently seize a
 * phone would be malware. That difficulty is the protection, not an obstacle to route
 * around, and there is no API that skips it.
 *
 * On a university-owned exam device:
 *
 *     adb shell dpm set-device-owner com.uniexam.uniexam/.ExamAdminReceiver
 *
 * See docs/android-verification.md for what changes once that succeeds.
 */
class ExamAdminReceiver : DeviceAdminReceiver()
