import 'package:flutter/material.dart';
import 'package:taskr/auth/auth.dart';
import 'package:taskr/topics/topics.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AuthService().userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        } else if (snapshot.hasError) {
          return const Center(
            child: ErrorMessage(),
          );
        } else if (snapshot.hasData) {
          // Will be null if user is not logged in
          return const TopicsScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
