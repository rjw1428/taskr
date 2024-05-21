import 'package:flutter/material.dart';
import 'package:taskr/shared/shared.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      bottomNavigationBar: BottomNavBar(),
    );
  }
}
