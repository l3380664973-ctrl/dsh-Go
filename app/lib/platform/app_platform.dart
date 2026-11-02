import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// What this platform can actually do.
///
/// DSH Go was written for Android, where the app may run the DSH engine
/// itself (a patched Linux userland inside PRoot), read the screen through
/// the accessibility service, keep a floating pet above other apps, and
/// install its own APK updates. iOS forbids every one of those, so the iOS
/// build is a **remote client only**: it talks to a `dsh web` on a PC or a
/// server over SSH or DSH Remote (see `docs/ios-port.md`).
///
/// Everything below is a compile-time-safe runtime switch. Feature entry
/// points read it before they are shown, so an iOS build never offers a
/// button that can only fail. The wire protocol itself is unchanged:
/// `packages/dsh_client` and `packages/dsh_remote` are pure Dart and run
/// as-is on iOS.
///
/// Platform channels that the Android side implements (`dsh/runtime`,
/// `dsh/phone`, `dsh/pet_overlay`, …) simply do not exist on iOS. Callers
/// already swallow `MissingPluginException` (54 places in `lib/`), so those
/// paths degrade into no-ops instead of crashing.
abstract final class AppPlatform {
  /// True on a real iOS device/simulator. `kIsWeb` is never the app's target
  /// but is checked first so `dart:io`'s `Platform` is never touched on web.
  static bool get isIOS => !kIsWeb && Platform.isIOS;

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// The on-device DSH engine: a patched DSH plus a Linux userland under
  /// PRoot. Not possible on iOS (no userland, no `fork/exec`, no `ptrace`).
  static bool get supportsLocalEngine => !isIOS;

  /// Screen reading and tapping through the accessibility service, Shizuku,
  /// Sui, root or self-paired ADB. Every one of those channels is Android-only.
  static bool get supportsPhoneControl => !isIOS;

  /// The pet that sits above other apps. The in-app pet is plain Flutter and
  /// works everywhere; only the overlay needs an Android window service.
  static bool get supportsPetOverlay => !isIOS;

  /// Self-updating from a downloaded APK. iOS installs through the App Store,
  /// TestFlight or a re-signed build instead.
  static bool get supportsApkUpdate => !isIOS;

  /// 「后台运行」指南: it deep-links into per-OEM battery settings
  /// (vivo / 小米 / 华为 / 荣耀 / OPPO) that only exist on Android.
  static bool get supportsBackgroundGuide => !isIOS;

  /// `SystemAccessPage`: accessibility, notification listener, usage access
  /// and ADB — all Android-only toggles.
  static bool get supportsSystemAccess => !isIOS;

  /// Per-app refresh-rate override (Android's `preferredDisplayModeId`).
  static bool get supportsRefreshRateOverride => !isIOS;

  /// Voice input currently runs through the Android speech recogniser
  /// (`dsh/voice`). On iOS this needs `speech_to_text` or DSH's own voice
  /// plugin — a port task, not a decision. See `docs/ios-port.md` (M3).
  static bool get supportsVoiceInput => !isIOS;

  /// Local notifications for "turn finished / waiting for you / failed".
  /// iOS needs `UNUserNotificationCenter`; until that lands the setting is
  /// hidden rather than shown as a dead switch. See M3.
  static bool get supportsLocalNotifications => !isIOS;

  /// Custom launcher icon and home-screen shortcuts (Android `ShortcutManager`).
  static bool get supportsLauncherIconCustomisation => !isIOS;
}
