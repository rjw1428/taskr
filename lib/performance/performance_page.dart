import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/services.dart';

import '../shared/shared.dart';

class PerformancePage extends StatelessWidget {
  const PerformancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Performance'),
          actions: [
            IconButton(
                onPressed: () => AuthService().signOut(),
                icon: const Icon(FontAwesomeIcons.userAstronaut))
          ],
        ),
        body: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text('Performance things go here')],
        ),
        bottomNavigationBar: const BottomNavBar(
          selectedIndex: 1,
        ));
  }
}
