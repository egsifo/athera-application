import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'data/memory_repository.dart';
import 'data/repository.dart';
import 'data/settings_store.dart';
import 'data/sqlite_repository.dart';
import 'state/app_controller.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await SettingsStore.open();
  final settings = store.load();

  AtheraRepository repo;
  String? warning;
  try {
    if (kIsWeb) {
      // The browser demo has no local database. Say so instead of failing.
      repo = MemoryRepository();
      await repo.init();
      warning = 'Web demo: data is kept in memory only and resets when you reload.';
    } else {
      repo = SqliteRepository();
      await repo.init();
    }
  } catch (e) {
    // Storage failure must not stop the app: fall back to memory and say so.
    repo = MemoryRepository();
    await repo.init();
    warning = 'Local database unavailable ($e). Data is kept in memory only and will be lost on exit.';
  }

  final controller = AppController(
    repo: repo,
    settingsStore: store,
    settings: settings,
    persistenceWarning: warning,
  );
  runApp(AtheraApp(controller: controller));
}
