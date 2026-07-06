import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kylan_connect/features/onboarding/profile_setup_screen.dart';

void main() {
  group('ProfileSetupScreen Widget Tests', () {
    testWidgets('should display profile setup form', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ProfileSetupScreen(),
          ),
        ),
      );

      expect(find.text('Create Profile'), findsNWidgets(2));
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('should validate empty display name', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ProfileSetupScreen(),
          ),
        ),
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Display name is required'), findsOneWidget);
    });

    testWidgets('should display color picker', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ProfileSetupScreen(),
          ),
        ),
      );

      expect(find.text('Choose Avatar Color'), findsOneWidget);
    });

    testWidgets('should update avatar preview when typing name', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ProfileSetupScreen(),
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField), 'John');
      await tester.pump();

      expect(find.text('J'), findsOneWidget);
    });
  });
}
