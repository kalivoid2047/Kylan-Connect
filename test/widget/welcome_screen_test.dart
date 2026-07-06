import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kylan_connect/features/onboarding/welcome_screen.dart';

void main() {
  group('WelcomeScreen Widget Tests', () {
    testWidgets('should display branding logo and tagline',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: WelcomeScreen(),
          ),
        ),
      );

      // The app name is presented as a logo image plus the tagline, rather
      // than a literal "Kylan Connect" text title.
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Offline Peer-to-Peer Messaging'), findsOneWidget);
    });

    testWidgets('should display feature list', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: WelcomeScreen(),
          ),
        ),
      );

      expect(find.text('Automatic Device Discovery'), findsOneWidget);
      expect(find.text('End-to-End Encryption'), findsOneWidget);
      expect(find.text('No Internet Required'), findsOneWidget);
    });

    testWidgets('should have get started button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: WelcomeScreen(),
          ),
        ),
      );

      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('should navigate to profile setup on button tap', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: const WelcomeScreen(),
            routes: {
              '/profile-setup': (context) => const Scaffold(body: Text('Profile Setup')),
            },
          ),
        ),
      );

      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      expect(find.text('Profile Setup'), findsOneWidget);
    });
  });
}
