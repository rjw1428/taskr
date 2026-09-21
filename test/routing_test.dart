import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/routing.dart';
import 'package:taskr/task_list/task_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the tab routes are indexed in order with unique labels', () {
    final indexes = routeConfig.values.map((r) => r.index).toList();
    expect(indexes, List.generate(routeConfig.length, (i) => i));
    expect(routeConfig.values.map((r) => r.label).toSet().length, routeConfig.length);
    expect(routeConfig['/']!.label, 'List');
    // Keys are navigator route names, which are paths.
    expect(routeConfig.keys, everyElement(startsWith('/')));
    expect(routeConfig.keys, containsAll(['/performance', '/goals', '/people', '/backlog']));
    expect((routeConfig['/backlog']!.page as TaskListScreen).isBacklog, isTrue);
    expect((routeConfig['/']!.page as TaskListScreen).isBacklog, isFalse);
    expect(innerNavigatorKey.currentState, isNull);
  });
}
