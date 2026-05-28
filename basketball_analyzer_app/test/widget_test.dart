import 'package:flutter_test/flutter_test.dart';
import 'package:basketball_analyzer/app.dart';

void main() {
  testWidgets('App launches and shows navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const BasketballAnalyzerApp());
    expect(find.text('SHOT ANALYZER'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('Stats'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
  });
}
