import 'package:taskr/auth/auth.dart';
import 'package:taskr/home/home.dart';
import 'package:taskr/profile/profile.dart';
import 'package:taskr/about/about.dart';
import 'package:taskr/topics/topics.dart';

var appRoutes = {
  '/': (context) => const HomeScreen(),
  '/login': (context) => const LoginScreen(),
  '/topics': (context) => const TopicsScreen(),
  '/profile': (context) => const ProfileScreen(),
  '/about': (context) => const AboutScreen(),
};
