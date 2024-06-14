import 'package:taskr/home/home.dart';
import 'package:taskr/performance/performance_page.dart';

var appRoutes = {
  '/': (context) => const HomeScreen(),
  '/performance': (context) => const PerformancePage()
};
