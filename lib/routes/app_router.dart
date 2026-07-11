import 'package:flutter/material.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/onboarding/profile_setup_screen.dart';
import '../features/conversations/home_screen.dart';
import '../features/messaging/chat_screen.dart';
import '../features/messaging/create_group_screen.dart';
import '../features/messaging/group_chat_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/edit_profile_screen.dart';
import '../features/settings/diagnostics_screen.dart';
import '../repositories/profile_repository.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(
          builder: (_) => const _AuthWrapper(),
        );
      case '/welcome':
        return MaterialPageRoute(
          builder: (_) => const WelcomeScreen(),
        );
      case '/profile-setup':
        return MaterialPageRoute(
          builder: (_) => const ProfileSetupScreen(),
        );
      case '/home':
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
        );
      case '/chat':
        return MaterialPageRoute(
          builder: (_) => const ChatScreen(),
          settings: settings,
        );
      case '/create-group':
        return MaterialPageRoute(
          builder: (_) => const CreateGroupScreen(),
        );
      case '/group-chat':
        return MaterialPageRoute(
          builder: (_) => const GroupChatScreen(),
          settings: settings,
        );
      case '/settings':
        return MaterialPageRoute(
          builder: (_) => const SettingsScreen(),
        );
      case '/edit-profile':
        return MaterialPageRoute(
          builder: (_) => const EditProfileScreen(),
        );
      case '/diagnostics':
        return MaterialPageRoute(
          builder: (_) => const DiagnosticsScreen(),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const _NotFoundScreen(),
        );
    }
  }
}

class _AuthWrapper extends StatelessWidget {
  const _AuthWrapper();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkAuth(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data == true) {
          return const HomeScreen();
        } else {
          return const WelcomeScreen();
        }
      },
    );
  }

  Future<bool> _checkAuth() async {
    return ProfileRepository.instance.hasProfile();
  }
}

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not Found')),
      body: const Center(
        child: Text('Page not found'),
      ),
    );
  }
}
