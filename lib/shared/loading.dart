import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/services.dart';

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thinking...'),
        actions: [
          IconButton(
              onPressed: () => AuthService().signOut(),
              icon: const Icon(FontAwesomeIcons.userAstronaut))
        ],
      ),
    );
  }
}
