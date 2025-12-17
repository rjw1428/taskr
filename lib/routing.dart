import 'package:taskr/accomplishments/accomplishments_page.dart';
import 'package:taskr/home/home.dart';
import 'package:taskr/performance/performance_page.dart';
import 'package:taskr/settings/settings.dart';

var appRoutes = {
  '/': (context) => const HomeScreen(isBacklog: false),
  '/performance': (context) => const PerformancePage(),
  '/backlog': (context) => const HomeScreen(isBacklog: true),
  '/settings': (context) => const SettingsPage(),
  '/accomplishments': (context) => const AccomplishmentsPage(),
};
