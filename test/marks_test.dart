import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/app/marks.dart';

void main() {
  test('marks closer than 16 dp merge, far ones stay single', () {
    final g = clusterMarks([11000, 13000, 15000, 40000, 200000], 222000, 444);
    expect(g.map((e) => e.count), [3, 1, 1]);
    expect(g.first.first, 0);
    expect(g[1].first, 3);
  });

  test('more than 30 groups: distance grows, nothing dropped', () {
    final times = [for (var i = 0; i < 40; i++) i * 10000];
    final g = clusterMarks(times, 400000, 800);
    expect(g.length, lessThanOrEqualTo(30));
    expect(g.fold<int>(0, (s, e) => s + e.count), 40);
  });

  test('matches the Glass Harbor mock groups', () {
    const t = [11, 13, 15, 24, 32, 47, 49, 58, 71, 84, 93, 102, 110, 112, 114,
      117, 128, 139, 151, 160, 162, 164, 176, 188, 199, 210, 218];
    final g = clusterMarks([for (final s in t) s * 1000], 222000, 538);
    expect(g.where((e) => e.count > 1).map((e) => e.count), [3, 2, 4, 3]);
  });

  test('current comment is the last with t <= position', () {
    final t = [1000, 5000, 9000];
    expect(currentCommentIndex(t, 500), -1);
    expect(currentCommentIndex(t, 5000), 1);
    expect(currentCommentIndex(t, 8999), 1);
    expect(currentCommentIndex(t, 100000), 2);
  });
}
