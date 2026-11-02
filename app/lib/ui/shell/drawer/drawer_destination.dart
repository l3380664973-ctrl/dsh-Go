/// Secondary destinations the drawer (or something inside it) can open.
/// Pages the drawer opens; [settingsSearch] is ⚙ held down. 快捷入口 stores
/// these by [Enum.name], so a rename here is a change to stored preferences.
enum DrawerDestination { web, remote, plugins, engine, settings, settingsSearch, features }

extension DrawerDestinationHost on DrawerDestination {
  /// Pages that only make sense when the app itself runs the engine: the
  /// on-device web view and the 本机引擎 page. iOS has no engine, so these are
  /// never offered there (see `lib/platform/app_platform.dart`).
  bool get needsLocalEngine => this == DrawerDestination.web || this == DrawerDestination.engine;
}
