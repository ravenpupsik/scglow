class MarkGroup {
  MarkGroup(this.first, this.count, this.x);

  final int first;
  final int count;

  final double x;
}

List<MarkGroup> clusterMarks(List<int> timesMs, int totalMs, double barWidth,
    {double merge = 16, int maxGroups = 30}) {
  if (timesMs.isEmpty || totalMs <= 0 || barWidth <= 0) return const [];
  final xs = [
    for (final t in timesMs) (t.clamp(0, totalMs) / totalMs) * barWidth,
  ];
  List<MarkGroup> at(double dist) {
    final out = <MarkGroup>[];
    var start = 0;
    var sum = xs[0];
    for (var i = 1; i <= xs.length; i++) {
      if (i < xs.length && xs[i] - xs[i - 1] < dist) {
        sum += xs[i];
        continue;
      }
      final n = i - start;
      out.add(MarkGroup(start, n, sum / n));
      if (i < xs.length) {
        start = i;
        sum = xs[i];
      }
    }
    return out;
  }

  var dist = merge;
  var groups = at(dist);
  while (groups.length > maxGroups) {
    dist += 8;
    groups = at(dist);
  }
  return groups;
}

int currentCommentIndex(List<int> timesMs, int positionMs) {
  var lo = 0, hi = timesMs.length - 1, ans = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (timesMs[mid] <= positionMs) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}
