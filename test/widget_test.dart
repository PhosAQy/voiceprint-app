import 'package:flutter_test/flutter_test.dart';

import 'package:voiceprint/main.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const VoiceprintApp());
    expect(find.text('练习'), findsWidgets);
  });
}
