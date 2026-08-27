// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_diabla/app/app.dart';

void main() {
  testWidgets('LaDiablaApp renders splash screen correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: LaDiablaApp(),
      ),
    );

    // Verificar que el logo del SplashScreen se renderiza
    expect(find.byType(Image), findsOneWidget);

    // Avanzar el tiempo para simular la transición de la Splash Screen
    await tester.pump(const Duration(seconds: 3));
  });
}

