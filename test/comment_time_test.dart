import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/core/models.dart';
import 'package:scglow/ui/format.dart';

TrackComment parse(Map<String, dynamic> extra) => TrackComment.fromJson({
      'id': 1,
      'body': 'hi',
      'user': {'username': 'u'},
      ...extra,
    });

void main() {
  test('timestamp is read as milliseconds', () {
    expect(parse({'timestamp': 83000}).atMs, 83000);
    expect(formatCommentTime(parse({'timestamp': 83000}).atMs), '1:23');
    expect(formatCommentTime(parse({'timestamp': 3723999}).atMs), '1:02:03');
  });

  test('a real 0 ms stays 0:00', () {
    final c = parse({'timestamp': 0});
    expect(c.atMs, 0);
    expect(formatCommentTime(c.atMs), '0:00');
  });

  test('null or missing timestamp shows a dash', () {
    expect(parse({'timestamp': null}).atMs, isNull);
    expect(parse({}).atMs, isNull);
    expect(formatCommentTime(parse({}).atMs), '—');
  });

  test('numeric strings and doubles are accepted, junk is not', () {
    expect(parse({'timestamp': '15069'}).atMs, 15069);
    expect(parse({'timestamp': 15069.4}).atMs, 15069);
    expect(parse({'timestamp': 'abc'}).atMs, isNull);
  });
}
