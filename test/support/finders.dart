import 'package:flutter_test/flutter_test.dart';
import 'package:scglow/ui/widgets/interactive.dart';

Finder byLabel(String label) => find.byWidgetPredicate(
    (w) => w is Interactive && w.semanticLabel == label,
    description: 'button "$label"');
