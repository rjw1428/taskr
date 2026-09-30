import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/work.service.dart';
import 'package:taskr/work/work_archive_page.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  late WorkService service;
  var clock = 1000;
  setUp(() async {
    env = await TestEnv.create();
    clock = 1000;
    service = WorkService()..now = () => ++clock;
  });
  tearDown(() => env.dispose());

  testWidgets('empty state', (tester) async {
    await pumpApp(tester, WorkArchivePage(service: service));
    await settle(tester);
    expect(find.text('Nothing archived'), findsOneWidget);
  });

  testWidgets('lists newest archive first with counts and opens detail', (tester) async {
    final a = await service.add(WorkItem(title: 'Older', nextActions: [NextAction(id: 'x', text: 't', createdAt: 1, completedAt: 2)]));
    final b = await service.add(WorkItem(title: 'Newer'));
    await service.addUpdate(b, 'u');
    await service.archive(a);
    await service.archive(b);
    await pumpApp(tester, WorkArchivePage(service: service));
    await settle(tester);
    expect(tester.getTopLeft(find.text('Newer')).dy < tester.getTopLeft(find.text('Older')).dy, isTrue);
    expect(find.textContaining('1 step done'), findsOneWidget);
    expect(find.textContaining('1 update'), findsOneWidget);
    await tester.tap(find.text('Older'));
    await settle(tester);
    expect(find.text('Archived work'), findsWidgets);
    expect(find.byKey(const Key('detail-restore')), findsOneWidget);
  });
}
