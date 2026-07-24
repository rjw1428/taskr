import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/goals/goal_list.dart';
import 'package:taskr/performance/performance_page.dart';
import 'package:taskr/task_list/task_list.dart';
import 'package:taskr/people/people_list.dart';

class RouteOption {
  final int index;
  final String label;
  final Widget page;
  final IconData icon;
  const RouteOption({required this.index, required this.label, required this.page, required this.icon});
}

final Map<String, RouteOption> routeConfig = {
  '/': const RouteOption(
    index: 0,
    label: "List",
    page: TaskListScreen(),
    icon: FontAwesomeIcons.listCheck,
  ),
  '/performance': const RouteOption(
    index: 1,
    label: "Performance",
    page: PerformancePage(),
    icon: FontAwesomeIcons.gaugeHigh,
  ),
  '/goals': const RouteOption(
    index: 2,
    label: 'Goals',
    page: GoalListPage(),
    icon: FontAwesomeIcons.medal,
  ),
  '/backlog': const RouteOption(
    index: 3,
    label: "Backlog",
    page: TaskListScreen(
      isBacklog: true,
    ),
    icon: FontAwesomeIcons.tableColumns,
  ),
  '/people': const RouteOption(
    index: 4,
    label: "People",
    page: PeopleListPage(),
    icon: FontAwesomeIcons.users,
  )
};

final GlobalKey<NavigatorState> innerNavigatorKey = GlobalKey<NavigatorState>();
