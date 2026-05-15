import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:lil_brother/main.dart';
import 'package:lil_brother/providers/tv_provider.dart';

void main() {
    testWidgets('App renders HomeScreen', (WidgetTester tester) async {
        await tester.pumpWidget(
            ChangeNotifierProvider(
                create: (_) => TvProvider(),
                child: const LilBrotherApp(),
            ),
        );
        expect(find.text('lil-brother'), findsOneWidget);
    });
}

