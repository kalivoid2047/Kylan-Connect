import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kylan_connect/features/messaging/create_group_screen.dart';

void main() {
  group('CreateGroupScreen Widget Tests', () {
    testWidgets('should display the name field and create action',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CreateGroupScreen(),
          ),
        ),
      );

      expect(find.text('New Group'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Group name'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
    });

    testWidgets('should reject an empty group name', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CreateGroupScreen(),
          ),
        ),
      );

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a group name'), findsOneWidget);
    });

    testWidgets('should require at least two members', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CreateGroupScreen(),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Group name'),
        'Weekend Trip',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Pick at least 2 members'), findsOneWidget);
    });
  });
}
