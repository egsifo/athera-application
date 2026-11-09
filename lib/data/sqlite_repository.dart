import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/ai_models.dart';
import '../domain/models.dart';
import '../wellness/check_in.dart';
import '../wellness/routine.dart';
import 'repository.dart';

/// SQLite persistence with versioned migrations.
///
/// To change the schema: append a new entry to [_migrations] (key = new
/// version), bump nothing else. Existing installs run only the missing steps.
class SqliteRepository implements AtheraRepository {
  SqliteRepository({this.databasePath});
  final String? databasePath;
  Database? _db;

  static final Map<int, List<String>> _migrations = {
    1: [
      '''CREATE TABLE astronauts(
        id TEXT PRIMARY KEY, name TEXT NOT NULL, callsign TEXT NOT NULL,
        role TEXT NOT NULL, is_demo INTEGER NOT NULL DEFAULT 0)''',
      '''CREATE TABLE devices(
        id TEXT PRIMARY KEY, astronaut_id TEXT NOT NULL, name TEXT NOT NULL,
        measures TEXT NOT NULL, is_demo INTEGER NOT NULL DEFAULT 0)''',
      '''CREATE TABLE observations(
        id TEXT PRIMARY KEY, astronaut_id TEXT NOT NULL, device_id TEXT NOT NULL,
        type TEXT NOT NULL, value REAL NOT NULL, unit TEXT NOT NULL,
        measured_at INTEGER NOT NULL, received_at INTEGER NOT NULL,
        source TEXT NOT NULL, quality TEXT NOT NULL, synced INTEGER NOT NULL DEFAULT 0)''',
      'CREATE INDEX idx_obs_astro_time ON observations(astronaut_id, measured_at)',
      '''CREATE TABLE forecasts(
        id INTEGER PRIMARY KEY AUTOINCREMENT, astronaut_id TEXT NOT NULL,
        generated_at INTEGER NOT NULL, is_demo INTEGER NOT NULL DEFAULT 0, json TEXT NOT NULL)''',
      '''CREATE TABLE risk_assessments(
        id INTEGER PRIMARY KEY AUTOINCREMENT, astronaut_id TEXT NOT NULL,
        generated_at INTEGER NOT NULL, is_demo INTEGER NOT NULL DEFAULT 0, json TEXT NOT NULL)''',
      '''CREATE TABLE alerts(
        id TEXT PRIMARY KEY, category TEXT NOT NULL, severity TEXT NOT NULL,
        astronaut_id TEXT, source TEXT NOT NULL, status TEXT NOT NULL,
        title TEXT NOT NULL, detail TEXT NOT NULL, dedupe_key TEXT, data TEXT NOT NULL,
        is_demo INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''',
      'CREATE INDEX idx_alerts_created ON alerts(created_at)',
      '''CREATE TABLE emergency_events(
        id TEXT PRIMARY KEY, astronaut_id TEXT NOT NULL, created_at INTEGER NOT NULL,
        is_demo INTEGER NOT NULL DEFAULT 0, json TEXT NOT NULL)''',
      '''CREATE TABLE sync_records(
        id TEXT PRIMARY KEY, kind TEXT NOT NULL, started_at INTEGER NOT NULL,
        count INTEGER NOT NULL, status TEXT NOT NULL, note TEXT NOT NULL)''',
    ],
    2: [
      '''CREATE TABLE check_ins(
        id TEXT PRIMARY KEY, astronaut_id TEXT NOT NULL, at INTEGER NOT NULL,
        is_demo INTEGER NOT NULL DEFAULT 0, json TEXT NOT NULL)''',
      'CREATE INDEX idx_checkins_astro ON check_ins(astronaut_id, at)',
      '''CREATE TABLE routine_log(
        astronaut_id TEXT NOT NULL, task_id TEXT NOT NULL, day TEXT NOT NULL,
        done_at INTEGER NOT NULL, is_demo INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(astronaut_id, task_id, day))''',
    ],
  };

  static int get schemaVersion => _migrations.keys.reduce((a, b) => a > b ? a : b);

  @override
  String get backendName => 'SQLite v$schemaVersion';

  Database get _d {
    final db = _db;
    if (db == null) throw PersistenceException('Database not initialised');
    return db;
  }

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on DatabaseException catch (e) {
      throw PersistenceException(e.toString());
    }
  }

  @override
  Future<void> init() => _guard(() async {
        final path = databasePath ?? p.join(await getDatabasesPath(), 'athera.db');
        _db = await openDatabase(
          path,
          version: schemaVersion,
          onCreate: (db, version) async {
            for (var v = 1; v <= version; v++) {
              for (final sql in _migrations[v] ?? const <String>[]) {
                await db.execute(sql);
              }
            }
          },
          onUpgrade: (db, from, to) async {
            for (var v = from + 1; v <= to; v++) {
              for (final sql in _migrations[v] ?? const <String>[]) {
                await db.execute(sql);
              }
            }
          },
        );
      });

  @override
  Future<void> saveAstronauts(List<Astronaut> items) => _guard(() async {
        final b = _d.batch();
        for (final a in items) {
          b.insert('astronauts', a.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await b.commit(noResult: true);
      });

  @override
  Future<List<Astronaut>> astronauts() =>
      _guard(() async => (await _d.query('astronauts', orderBy: 'id')).map(Astronaut.fromRow).toList());

  @override
  Future<void> saveDevices(List<Device> items) => _guard(() async {
        final b = _d.batch();
        for (final x in items) {
          b.insert('devices', x.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await b.commit(noResult: true);
      });

  @override
  Future<List<Device>> devices() =>
      _guard(() async => (await _d.query('devices', orderBy: 'id')).map(Device.fromRow).toList());

  @override
  Future<void> insertObservations(List<Observation> items) => _guard(() async {
        if (items.isEmpty) return;
        final b = _d.batch();
        for (final o in items) {
          b.insert('observations', o.toRow(), conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await b.commit(noResult: true);
      });

  @override
  Future<List<Observation>> observations(
    String astronautId, {
    DateTime? since,
    DateTime? until,
    bool excludeSimulated = false,
  }) =>
      _guard(() async {
        final where = StringBuffer('astronaut_id = ?');
        final args = <Object?>[astronautId];
        if (since != null) {
          where.write(' AND measured_at >= ?');
          args.add(since.toUtc().millisecondsSinceEpoch);
        }
        if (until != null) {
          where.write(' AND measured_at <= ?');
          args.add(until.toUtc().millisecondsSinceEpoch);
        }
        if (excludeSimulated) where.write(" AND source <> 'demo'");
        final rows = await _d.query('observations',
            where: where.toString(), whereArgs: args, orderBy: 'measured_at ASC');
        return rows.map(Observation.fromRow).whereType<Observation>().toList();
      });

  @override
  Future<int> pendingSyncCount() => _guard(() async {
        final r = await _d.rawQuery('SELECT COUNT(*) AS c FROM observations WHERE synced = 0');
        return (r.first['c'] as int?) ?? 0;
      });

  @override
  Future<void> markAllSynced() => _guard(() async {
        await _d.rawUpdate('UPDATE observations SET synced = 1 WHERE synced = 0');
      });

  @override
  Future<void> pruneObservations(DateTime before) => _guard(() async {
        await _d.delete('observations',
            where: 'measured_at < ?', whereArgs: [before.toUtc().millisecondsSinceEpoch]);
      });

  @override
  Future<void> saveForecast(ForecastResult f) => _guard(() async {
        await _d.insert('forecasts', {
          'astronaut_id': f.astronautId,
          'generated_at': f.generatedAt.toUtc().millisecondsSinceEpoch,
          'is_demo': f.isMock ? 1 : 0,
          'json': jsonEncode(f.toJson()),
        });
      });

  @override
  Future<ForecastResult?> latestForecast(String astronautId) => _guard(() async {
        final rows = await _d.query('forecasts',
            where: 'astronaut_id = ?', whereArgs: [astronautId], orderBy: 'generated_at DESC', limit: 1);
        if (rows.isEmpty) return null;
        try {
          return ForecastResult.parse(jsonDecode(rows.first['json'] as String));
        } on AiException {
          return null;
        }
      });

  @override
  Future<void> saveRisk(RiskResult r) => _guard(() async {
        await _d.insert('risk_assessments', {
          'astronaut_id': r.astronautId,
          'generated_at': r.generatedAt.toUtc().millisecondsSinceEpoch,
          'is_demo': (r.isMock || r.inputSimulated) ? 1 : 0,
          'json': jsonEncode(r.toJson()),
        });
      });

  @override
  Future<List<RiskResult>> riskHistory(String astronautId, {int limit = 200}) => _guard(() async {
        final rows = await _d.query('risk_assessments',
            where: 'astronaut_id = ?', whereArgs: [astronautId], orderBy: 'generated_at DESC', limit: limit);
        final out = <RiskResult>[];
        for (final r in rows) {
          try {
            out.add(RiskResult.parse(jsonDecode(r['json'] as String)));
          } on AiException {
            // Skip rows that no longer match the contract.
          }
        }
        return out.reversed.toList();
      });

  @override
  Future<void> upsertAlert(AlertEvent a) => _guard(() async {
        await _d.insert('alerts', a.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      });

  @override
  Future<List<AlertEvent>> alerts({
    String? astronautId,
    AlertCategory? category,
    AlertSeverity? severity,
    DateTime? since,
    bool openOnly = false,
    int limit = 500,
  }) =>
      _guard(() async {
        final where = <String>[];
        final args = <Object?>[];
        if (astronautId != null) {
          where.add('astronaut_id = ?');
          args.add(astronautId);
        }
        if (category != null) {
          where.add('category = ?');
          args.add(category.name);
        }
        if (severity != null) {
          where.add('severity = ?');
          args.add(severity.name);
        }
        if (since != null) {
          where.add('created_at >= ?');
          args.add(since.toUtc().millisecondsSinceEpoch);
        }
        if (openOnly) where.add("status <> 'resolved'");
        final rows = await _d.query('alerts',
            where: where.isEmpty ? null : where.join(' AND '),
            whereArgs: args,
            orderBy: 'created_at DESC',
            limit: limit);
        return rows.map(AlertEvent.fromRow).toList();
      });

  @override
  Future<void> saveEmergency(EmergencyEvent e) => _guard(() async {
        await _d.insert('emergency_events', e.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      });

  @override
  Future<List<EmergencyEvent>> emergencies({int limit = 100}) => _guard(() async {
        final rows = await _d.query('emergency_events', orderBy: 'created_at DESC', limit: limit);
        return rows.map(EmergencyEvent.fromRow).toList();
      });

  @override
  Future<void> addSyncRecord(SyncRecord r) => _guard(() async {
        await _d.insert(
          'sync_records',
          {
            'id': r.id,
            'kind': r.kind,
            'started_at': r.startedAt.toUtc().millisecondsSinceEpoch,
            'count': r.count,
            'status': r.status,
            'note': r.note,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

  @override
  Future<List<SyncRecord>> syncRecords({int limit = 20}) => _guard(() async {
        final rows = await _d.query('sync_records', orderBy: 'started_at DESC', limit: limit);
        return rows
            .map((r) => SyncRecord(
                  id: r['id'] as String,
                  kind: r['kind'] as String,
                  startedAt: DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int, isUtc: true),
                  count: r['count'] as int,
                  status: r['status'] as String,
                  note: r['note'] as String,
                ))
            .toList();
      });

  @override
  Future<void> saveCheckIn(CheckIn c) => _guard(() async {
        await _d.insert(
          'check_ins',
          {
            'id': c.id,
            'astronaut_id': c.astronautId,
            'at': c.at.toUtc().millisecondsSinceEpoch,
            'is_demo': c.isDemo ? 1 : 0,
            'json': jsonEncode(c.toJson()),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

  @override
  Future<List<CheckIn>> checkIns(String astronautId, {int limit = 60}) => _guard(() async {
        final rows = await _d.query('check_ins',
            where: 'astronaut_id = ?', whereArgs: [astronautId], orderBy: 'at DESC', limit: limit);
        return [for (final r in rows) CheckIn.fromJson((jsonDecode(r['json']! as String) as Map).cast<String, Object?>())];
      });

  @override
  Future<void> setRoutineDone(RoutineLogEntry e, bool done) => _guard(() async {
        if (done) {
          await _d.insert(
            'routine_log',
            {
              'astronaut_id': e.astronautId,
              'task_id': e.taskId,
              'day': e.day,
              'done_at': e.doneAt.toUtc().millisecondsSinceEpoch,
              'is_demo': e.isDemo ? 1 : 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          await _d.delete('routine_log',
              where: 'astronaut_id = ? AND task_id = ? AND day = ?', whereArgs: [e.astronautId, e.taskId, e.day]);
        }
      });

  @override
  Future<List<RoutineLogEntry>> routineLog(String astronautId, {String? sinceDay}) => _guard(() async {
        final rows = await _d.query(
          'routine_log',
          where: sinceDay == null ? 'astronaut_id = ?' : 'astronaut_id = ? AND day >= ?',
          whereArgs: sinceDay == null ? [astronautId] : [astronautId, sinceDay],
        );
        return [
          for (final r in rows)
            RoutineLogEntry(
              astronautId: r['astronaut_id']! as String,
              taskId: r['task_id']! as String,
              day: r['day']! as String,
              doneAt: DateTime.fromMillisecondsSinceEpoch(r['done_at']! as int, isUtc: true),
              isDemo: r['is_demo'] == 1,
            ),
        ];
      });

  @override
  Future<void> deleteDemoData() => _guard(() async {
        final b = _d.batch();
        b.delete('check_ins', where: 'is_demo = 1');
        b.delete('routine_log', where: 'is_demo = 1');
        b.delete('observations', where: "source = 'demo'");
        b.delete('forecasts', where: 'is_demo = 1');
        b.delete('risk_assessments', where: 'is_demo = 1');
        b.delete('alerts', where: 'is_demo = 1');
        b.delete('emergency_events', where: 'is_demo = 1');
        await b.commit(noResult: true);
      });
}
