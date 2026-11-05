/// Small formatting helpers (no intl dependency).
String two(int n) => n.toString().padLeft(2, '0');

String fmtTime(DateTime t, {bool seconds = true}) {
  final l = t.toLocal();
  return seconds ? '${two(l.hour)}:${two(l.minute)}:${two(l.second)}' : '${two(l.hour)}:${two(l.minute)}';
}

String fmtDateTime(DateTime t) {
  final l = t.toLocal();
  return '${l.year}-${two(l.month)}-${two(l.day)} ${fmtTime(l, seconds: false)}';
}

String fmtAgo(DateTime? t, {DateTime? now}) {
  if (t == null) return 'never';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 5) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ${d.inMinutes % 60} min ago';
  return '${d.inDays} d ago';
}

String fmtDuration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  return '${d.inHours} h ${d.inMinutes % 60} min';
}

String fmtNum(double? v, int decimals) => v == null || v.isNaN ? '—' : v.toStringAsFixed(decimals);

double cToF(double c) => c * 9 / 5 + 32;

String csvEscape(Object? v) {
  final s = v?.toString() ?? '';
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}
