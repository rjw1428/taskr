import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/work/work_export.dart';

int ms(String day) => DateTime.parse(day).millisecondsSinceEpoch;

void main() {
  final full = WorkItem(
    title: 'Migrate billing',
    notes: 'Ticket: https://jira.test/ABC-1\nWaiting since Monday.',
    createdAt: ms('2026-09-01'),
    nextActions: [
      NextAction(id: 'a', text: 'Get numbers', createdAt: ms('2026-09-02'), waitingOn: 'Finance'),
      NextAction(id: 'b', text: 'Draft RFC', createdAt: ms('2026-09-02'), completedAt: ms('2026-09-05')),
      NextAction(id: 'c', text: 'Review PR', createdAt: ms('2026-09-06')),
    ],
    updates: [WorkUpdate(id: 'u', text: 'Shipped phase 1', createdAt: ms('2026-09-07'))],
  );

  test('full item golden', () {
    expect(WorkExport.item(full), '''
## Migrate billing
_Created 2026-09-01_

Ticket: https://jira.test/ABC-1
Waiting since Monday.

### Next actions
- [ ] Get numbers  (waiting on Finance)
- [x] Draft RFC  (done 2026-09-05)
- [ ] Review PR

### Updates
- 2026-09-07: Shipped phase 1''');
  });

  test('minimal item golden', () {
    final min = WorkItem(title: 'Only title', createdAt: ms('2026-09-10'));
    expect(WorkExport.item(min), '''
## Only title
_Created 2026-09-10_

### Next actions''');
  });

  test('archived item golden', () {
    final arch = WorkItem(title: 'Done proj', createdAt: ms('2026-08-01'), archivedAt: ms('2026-09-20'));
    expect(WorkExport.item(arch), '''
## Done proj
_Created 2026-08-01, archived 2026-09-20_

### Next actions''');
  });

  test('board with both sections golden', () {
    final a1 = WorkItem(title: 'First', createdAt: ms('2026-09-01'));
    final a2 = WorkItem(title: 'Second', createdAt: ms('2026-09-02'));
    final arch = WorkItem(title: 'Old', createdAt: ms('2026-08-01'), archivedAt: ms('2026-08-15'));
    expect(WorkExport.board([a1, a2], [arch], now: ms('2026-09-29')), '''
_Exported 2026-09-29_

# Work

## First
_Created 2026-09-01_

### Next actions

## Second
_Created 2026-09-02_

### Next actions

# Archived

## Old
_Created 2026-08-01, archived 2026-08-15_

### Next actions''');
  });

  test('board with no archived items golden', () {
    final a1 = WorkItem(title: 'First', createdAt: ms('2026-09-01'));
    expect(WorkExport.board([a1], [], now: ms('2026-09-29')), '''
_Exported 2026-09-29_

# Work

## First
_Created 2026-09-01_

### Next actions

# Archived

_None_''');
  });

  test('empty board', () {
    final out = WorkExport.board([], [], now: ms('2026-09-29'));
    expect(out.split('_None_').length - 1, 2);
  });
}
