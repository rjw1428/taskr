import 'package:taskr/home/home.dart';
import 'package:taskr/performance/performance_page.dart';

var appRoutes = {
  '/': (context) => const HomeScreen(isBacklog: false),
  '/performance': (context) => const PerformancePage(),
  '/backlog': (context) => const HomeScreen(isBacklog: true)
};
