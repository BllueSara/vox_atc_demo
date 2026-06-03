import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vox_atc_demo/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('PTT test screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const VoxAtcDemoApp());
    await tester.pumpAndSettle();

    expect(find.text('Hold to Talk'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
  });
}
