import 'package:flutter/material.dart';
import 'package:taskr/login/login.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/task_list/task_list.dart';

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
          return const TaskListScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
