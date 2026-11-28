import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/ui/widgets/marquee_text.dart';

const _long = 'Beautiful Mistakes Mix';

Widget _host({required bool enabled, String text = _long, double width = 160}) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: MarqueeText(
            text,
            enabled: enabled,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );

double _textX(WidgetTester tester) =>
    tester.getTopLeft(find.text(_long).last).dx;

void main() {
  testWidgets('a title that does not fit is ellipsized and scrolls slowly on hover', (tester) async {
    await tester.pumpWidget(_host(enabled: true));
    var text = tester.widget<Text>(find.text(_long));
    expect(text.overflow, TextOverflow.ellipsis);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(900, 500));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byType(MarqueeText)));
    await tester.pump();
    text = tester.widget<Text>(find.text(_long));
    expect(text.softWrap, isFalse, reason: 'the full title is laid out while hovered');

    final x0 = _textX(tester);
    await tester.pump(const Duration(seconds: 2));
    final x1 = _textX(tester);
    expect(x1, lessThan(x0), reason: 'it moves left');
    expect(x0 - x1, lessThan(MarqueeText.speed * 2 + 1), reason: 'at most 30 dp per second');
    await tester.pump(const Duration(seconds: 30));
    expect(_textX(tester), lessThanOrEqualTo(x0));

    await mouse.moveTo(const Offset(900, 500));
    await tester.pump();
    expect(_textX(tester), x0, reason: 'it rests at the start again');
    expect(tester.widget<Text>(find.text(_long)).overflow, TextOverflow.ellipsis);
  });

  testWidgets('a title that fits, or a disabled marquee, never scrolls', (tester) async {
    await tester.pumpWidget(_host(enabled: true, text: 'Short', width: 300));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.byType(MarqueeText)));
    await tester.pump();
    final x0 = tester.getTopLeft(find.text('Short')).dx;
    await tester.pump(const Duration(seconds: 3));
    expect(tester.getTopLeft(find.text('Short')).dx, x0);

    await tester.pumpWidget(_host(enabled: false));
    await mouse.moveTo(tester.getCenter(find.byType(MarqueeText)));
    await tester.pump();
    final y0 = _textX(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(_textX(tester), y0);
    expect(tester.widget<Text>(find.text(_long)).overflow, TextOverflow.ellipsis);
  });
}
