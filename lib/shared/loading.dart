import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/services.dart';

class LoadingScreen extends StatelessWidget {
  final String message;
  const LoadingScreen({super.key, this.message = 'Thinking...'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(message),
        actions: [
          IconButton(
              onPressed: () => AuthService().signOut(),
              icon: const Icon(FontAwesomeIcons.userAstronaut))
        ],
      ),
    );
  }
}
