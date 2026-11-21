String formatDuration(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

String formatMs(int ms) => formatDuration(Duration(milliseconds: ms));

String formatCommentTime(int? ms) => ms == null ? '—' : formatMs(ms);
