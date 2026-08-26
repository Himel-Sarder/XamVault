# Android exam-lockdown verification (§68)

Phase 12 ships in the APK and its Kotlin compiles, but **its behaviour on real hardware
has never been observed**. Everything below has to be checked by a person holding a
phone; none of it can be asserted from a test suite, because what is being verified is
what the *operating system* does, not what our code asks it to do.

Record the result of each step. A failure here is information, not a defect to hide —
several of these are expected to fail on an ordinary personal phone, and the app is
built to say so rather than to pretend otherwise.

---

## 1. Before you start

**Build and install**

```
flutter build apk --release --dart-define=API_BASE_URL=http://<host-lan-ip>:8000/api/v1
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The phone and the API host must be on the same network, and the API must be bound to
`0.0.0.0` rather than `127.0.0.1` — otherwise the phone cannot reach it and every step
below fails for a reason that has nothing to do with lockdown.

**Note the device class.** The results differ, legitimately, between:

| Device | Expect |
|---|---|
| Ordinary personal phone | `FLAG_SECURE` enforced; Lock Task is *pinning*, which the student can dismiss, and which prompts before it starts |
| Device Owner / provisioned | `FLAG_SECURE` enforced; Lock Task genuinely locked, with **no prompt** |

**Provisioning a university device.** Silent pinning requires Device Owner, and Android
only grants it on a freshly reset device with no accounts added:

```
adb shell dpm set-device-owner com.uniexam.uniexam/.ExamAdminReceiver
```

That difficulty is deliberate and there is no API that avoids it — an app able to seize
a phone unannounced would be malware. On an unprovisioned personal phone the
confirmation dialog cannot be suppressed by any means, and the app reports which of the
two it actually got rather than implying the stronger one.

Write down which one you tested. A result is meaningless without it.

**Set up an exam** with secure mode on, published, with your student account approved,
and a window open now.

---

## 2. The checklist

### 2.1 Screenshots are actually blocked

1. Start the exam.
2. Press the screenshot key combination.

**Expect:** the screenshot fails, and Android says so ("Can't take screenshot due to
security policy" or similar wording). This is the one control an unmanaged phone
genuinely enforces.

**If it succeeds:** `FLAG_SECURE` is not in force. Check the banner — it should not be
claiming screenshots are blocked. A wrong claim here is worse than no claim.

### 2.2 The banner tells the truth

3. Read the banner at the top of the exam screen.

**Expect** exactly one of:

| Banner | Means |
|---|---|
| "Device locked to this exam" | Lock Task genuinely locked — managed device only |
| "Screenshots are blocked." | `FLAG_SECURE` on, pinning dismissible — the normal phone case |
| "Device lockdown is not available here. Activity is still recorded." | Neither available |

**The banner must match what §2.1 actually did.** This is the single most important
check on the list: the app's honesty about its own limits is the feature.

### 2.3 Recents shows nothing

4. Open the app switcher.

**Expect:** the UniExam card is blank or shows a placeholder, not the exam paper.

### 2.4 The back gesture does not leave the paper

5. Press back, and swipe back from the screen edge.

**Expect:** nothing happens. The paper stays.

### 2.5 Leaving is recorded, not punished

6. Go to the home screen. Wait about five seconds. Return to the app.

**Expect:**
- the exam resumes on the same question, with answers intact;
- the countdown reflects *server* time — it does not pause while you are away;
- afterwards, the teacher's security log for this attempt shows `APP_BACKGROUND` and
  `APP_FOREGROUND`, the latter with an `away_ms` of roughly 5000.

**Expect NOT:** the attempt being auto-submitted, or any accusation. §38 — the app
records, a human decides.

### 2.5b Conditions the device can see but not stop

7. Before starting, turn on **Developer options** and **USB debugging**. Start an exam.
8. Mid-exam, try **split screen** with another app.
9. If you have a cable or dongle, attach an **external display**.

**Expect:** the teacher's *Exam activity* screen records `Developer options are on`,
`USB debugging is on`, `SPLIT_SCREEN` and `EXTERNAL_DISPLAY`. None of them ends the
attempt or blocks anything — the app cannot prevent these and does not pretend to.

Developer mode on a student's own phone is ordinary and means nothing by itself. It is
recorded because it is context beside something else, and reading it that way is a
human's job.

### 2.6 Pinning, and its honest limit

10. If the banner said "Screenshots are blocked" (the unmanaged case), try to leave by
   holding **back + recents** together.

**Expect:** you can leave. That is the documented limitation of pinning on an
unmanaged device, not a bug. The server should already hold a `LOCKDOWN_ENGAGED` event
whose detail says `Screen pinned; the student can still exit`.

This step exists to confirm the *claim* matches reality. Do not report the ability to
exit as a defect — report a mismatch between the banner and reality as one.

### 2.7 Changing the clock does not buy time

8. Mid-exam, change the device time forward by an hour. Return to the exam.

**Expect:** the remaining time is unchanged (§34 — the clock is the server's), and a
`DEVICE_TIME_CHANGE` event appears in the log.

### 2.8 Losing the network

9. Turn on aeroplane mode for a few seconds, then off.

**Expect:** an answer saved while offline reports a failure but does not lose what was
typed; on reconnection saving resumes. `NETWORK_DISCONNECT` and `NETWORK_RECONNECT`
appear in the log.

### 2.9 Submitting releases the device

10. Submit the exam.

**Expect:** pinning is released, screenshots work again, and the phone behaves normally.
A student must never be left pinned inside a finished exam — this is checked in the
widget tests too, but the platform half can only be seen here.

### 2.10 A call interrupts

11. Start another exam and ring the phone from another number.

**Expect:** the call arrives (nothing here may block a phone call), the attempt survives,
and returning to the app resumes the paper. `APP_BACKGROUND`/`APP_FOREGROUND` recorded.

---

## 3. What this checklist does not establish

Passing every step above does **not** make a personal Android phone cheat-proof, and the
project does not claim it does (§67). None of the following is addressed by any control
in this app:

- a second phone, or a camera, pointed at the screen;
- a rooted device with vendor capture tools that bypass `FLAG_SECURE`;
- another person sitting beside the candidate;
- a second device on the same desk.

What the lockdown buys is a raised effort bar and an evidence trail. Invigilation is
still a human activity.

---

## 4. Recording the outcome

For each step, note: pass / fail / not applicable, the device class, the Android
version, and the exact banner text seen. A failure with the banner *correctly* reporting
the limitation is a pass for §2.2 and a documented platform limit — not a defect.
