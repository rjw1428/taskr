import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/routing.dart';
import 'package:taskr/task_list/task_list.dart';
import 'package:taskr/work/work_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the tab routes are indexed in order with unique labels', () {
    final indexes = routeConfig.values.map((r) => r.index).toList();
    expect(indexes, List.generate(routeConfig.length, (i) => i));
    expect(routeConfig.values.map((r) => r.label).toSet().length, routeConfig.length);
    expect(routeConfig['/']!.label, 'List');
    // Keys are navigator route names, which are paths.
    expect(routeConfig.keys, everyElement(startsWith('/')));
    expect(routeConfig.keys, containsAll(['/work', '/performance', '/goals', '/people', '/backlog']));
    // Work sits between List and Performance with the corporate icon.
    expect(routeConfig.values.map((r) => r.label).toList(), ['List', 'Work', 'Performance', 'Goals', 'Backlog', 'People']);
    expect(routeConfig['/work']!.index, 1);
    expect(routeConfig['/work']!.icon, Icons.corporate_fare);
    expect(routeConfig['/work']!.page, isA<WorkPage>());
    expect(requestedRoute.value, isNull);
    expect((routeConfig['/backlog']!.page as TaskListScreen).isBacklog, isTrue);
    expect((routeConfig['/']!.page as TaskListScreen).isBacklog, isFalse);
    expect(innerNavigatorKey.currentState, isNull);
  });
}
