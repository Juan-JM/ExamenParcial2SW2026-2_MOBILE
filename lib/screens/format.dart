/// "hace 5 min", "ayer 14:30": lo más legible para alguien de paso.
String formatRelative(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final difference = current.difference(date);

  if (difference.inMinutes < 1) return 'ahora';
  if (difference.inMinutes < 60) return 'hace ${difference.inMinutes} min';

  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(date.year, date.month, date.day);
  final days = today.difference(day).inDays;
  final time = formatTime(date);

  if (days == 0) return 'hoy $time';
  if (days == 1) return 'ayer $time';

  return '${_two(date.day)}/${_two(date.month)} $time';
}

String formatTime(DateTime date) => '${_two(date.hour)}:${_two(date.minute)}';

String _two(int value) => value.toString().padLeft(2, '0');
