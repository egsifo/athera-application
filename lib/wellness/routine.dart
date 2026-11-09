import 'check_in.dart';

enum RoutineKind { measurement, checkIn, exercise }

class RoutineTask {
  const RoutineTask({
    required this.id,
    required this.title,
    required this.detail,
    required this.kind,
    required this.dueHour,
    this.points = 10,
  });
  final String id;
  final String title;
  final String detail;
  final RoutineKind kind;

  /// Local hour of day when the task becomes due.
  final int dueHour;
  final int points;
}

/// Daily mission routine. Content is a generic, editable template, not a
/// prescription: the real schedule comes from the mission's medical plan.
const List<RoutineTask> kRoutine = [
  RoutineTask(
    id: 'bp_hr',
    title: 'Blood pressure and heart rate',
    detail: 'Sit still for 5 minutes, arm at heart level, cuff on bare upper arm. Do not talk while measuring.',
    kind: RoutineKind.measurement,
    dueHour: 8,
  ),
  RoutineTask(
    id: 'temp',
    title: 'Body temperature',
    detail: 'Measure before exercise and before a hot drink. Note any chills or sweats.',
    kind: RoutineKind.measurement,
    dueHour: 8,
  ),
  RoutineTask(
    id: 'exercise',
    title: 'Exercise session',
    detail: 'Complete the resistance and aerobic work from your mission plan. It protects bones, muscles and the heart.',
    kind: RoutineKind.exercise,
    dueHour: 12,
    points: 20,
  ),
  RoutineTask(
    id: 'spo2',
    title: 'Blood oxygen spot check',
    detail: 'Warm hands, sensor snug on the fingertip, stay still for 30 seconds.',
    kind: RoutineKind.measurement,
    dueHour: 17,
  ),
  RoutineTask(
    id: 'checkin',
    title: 'Daily wellbeing check-in',
    detail: 'Sleep, mood, fatigue and stress. Takes under a minute.',
    kind: RoutineKind.checkIn,
    dueHour: 20,
    points: 15,
  ),
];

enum TaskState { done, due, overdue, upcoming }

class RoutineLogEntry {
  const RoutineLogEntry({
    required this.astronautId,
    required this.taskId,
    required this.day,
    required this.doneAt,
    this.isDemo = false,
  });
  final String astronautId;
  final String taskId;

  /// Local calendar day (yyyy-mm-dd).
  final String day;
  final DateTime doneAt;
  final bool isDemo;
}

class RoutineProgress {
  const RoutineProgress._();

  static int get totalPoints => kRoutine.fold(0, (a, t) => a + t.points);

  /// A task is overdue two hours after it became due.
  static TaskState stateOf(RoutineTask t, DateTime now, Set<String> doneToday) {
    if (doneToday.contains(t.id)) return TaskState.done;
    final h = now.toLocal().hour + now.toLocal().minute / 60.0;
    if (h < t.dueHour) return TaskState.upcoming;
    if (h < t.dueHour + 2) return TaskState.due;
    return TaskState.overdue;
  }

  static Set<String> doneOn(Iterable<RoutineLogEntry> log, String day) =>
      {for (final e in log) if (e.day == day) e.taskId};

  static int pointsFor(Set<String> done) =>
      kRoutine.where((t) => done.contains(t.id)).fold(0, (a, t) => a + t.points);

  /// Consecutive complete days ending today (if complete) or yesterday.
  static int streak(Iterable<RoutineLogEntry> log, DateTime now) {
    final byDay = <String, Set<String>>{};
    for (final e in log) {
      byDay.putIfAbsent(e.day, () => {}).add(e.taskId);
    }
    bool complete(String day) => kRoutine.every((t) => byDay[day]?.contains(t.id) ?? false);
    var d = DateTime(now.toLocal().year, now.toLocal().month, now.toLocal().day);
    if (!complete(dayKey(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (complete(dayKey(d))) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

  /// Share of possible task completions over the last [days] days (0..1).
  static double adherence(Iterable<RoutineLogEntry> log, DateTime now, {int days = 7, String? taskId}) {
    final start = DateTime(now.toLocal().year, now.toLocal().month, now.toLocal().day - (days - 1));
    final keys = {for (var i = 0; i < days; i++) dayKey(DateTime(start.year, start.month, start.day + i))};
    final tasks = taskId == null ? kRoutine.length : 1;
    final done = log.where((e) => keys.contains(e.day) && (taskId == null || e.taskId == taskId)).length;
    return (done / (tasks * days)).clamp(0.0, 1.0);
  }
}
