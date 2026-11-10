String formatDuration(Duration d, {bool showMs = false}) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final base = h > 0 ? '$h:$m:$s' : '$m:$s';
  if (!showMs) return base;
  final cs = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(
    2,
    '0',
  );
  return '$base.$cs';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatRelativeDate(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final hh = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final time =
      '$hh:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today, $time';
  if (diff == 1) return 'Yesterday, $time';
  if (diff < 7 && diff > 0) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[t.weekday - 1]}, $time';
  }
  final y = t.year == now.year ? '' : ' ${t.year}';
  return '${_months[t.month - 1]} ${t.day}$y';
}

String resolutionLabel(int w, int h) {
  final s = w < h ? w : h;
  if (s == 0) return '—';
  if (s >= 2100) return '4K';
  if (s >= 1400) return '1440p';
  if (s >= 1000) return '1080p';
  if (s >= 700) return '720p';
  if (s >= 470) return '480p';
  return '${s}p';
}
