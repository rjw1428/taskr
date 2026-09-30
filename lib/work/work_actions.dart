import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/work.service.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/work/next_action_form.dart';
import 'package:taskr/work/work_export.dart';
import 'package:taskr/work/work_logic.dart';
import 'package:taskr/work/work_update_form.dart';

/// The mutations shared by the card and the detail page, each reading the
/// latest stored item before writing so two screens never race on a stale
/// copy. Every write goes through [WorkService] only.
class WorkActions {
  final WorkService service;
  WorkActions(this.service);

  Future<void> _mutateActions(String id, List<NextAction> Function(List<NextAction>) f) async {
    final item = await service.getActive(id);
    if (item == null) return;
    await service.setNextActions(id, f(item.nextActions));
  }

  Future<void> addNextAction(BuildContext context, String itemId) async {
    final input = await NextActionForm.show(context);
    if (input == null) return;
    final action = NextAction(id: service.newId(), text: input.text, waitingOn: input.waitingOn, createdAt: service.now());
    await guard(() => _mutateActions(itemId, (a) => WorkLogic.addNextAction(a, action)), 'Add next action');
  }

  Future<void> editNextAction(BuildContext context, String itemId, NextAction existing) async {
    final input = await NextActionForm.show(context, existing: existing);
    if (input == null) return;
    await guard(
      () => _mutateActions(itemId, (a) => WorkLogic.updateNextAction(a, existing.id, text: input.text, waitingOn: input.waitingOn)),
      'Edit next action',
    );
  }

  Future<void> sendToEnd(String itemId, String actionId) =>
      guard(() => _mutateActions(itemId, (a) => WorkLogic.sendNextActionToEnd(a, actionId)), 'Send to end');

  /// Completes and offers Undo. Copy is deliberately neutral: this is not a
  /// task and earns nothing.
  Future<void> complete(BuildContext context, String itemId, NextAction action) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await guard(() => _mutateActions(itemId, (a) => WorkLogic.completeNextAction(a, action.id, service.now())), 'Done');
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      content: Text('Done: ${action.text}', maxLines: 1, overflow: TextOverflow.ellipsis),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => guard(() => _mutateActions(itemId, (a) => WorkLogic.undoComplete(a, action.id)), 'Undo'),
      ),
    ));
  }

  Future<void> addUpdate(BuildContext context, String itemId) async {
    final text = await WorkUpdateForm.show(context);
    if (text == null) return;
    await guard(() => service.addUpdate(itemId, text), 'Add update');
  }

  Future<void> archive(String itemId) => guard(() => service.archive(itemId), 'Archive');

  Future<void> restore(String itemId) => guard(() => service.restore(itemId), 'Restore');

  Future<bool> confirmDelete(BuildContext context, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete work item?'),
        content: Text('"$title" and its whole history will be removed. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> delete(String itemId, {required bool archived}) =>
      guard(() => archived ? service.deleteArchived(itemId) : service.delete(itemId), 'Delete');

  Future<void> copyItem(BuildContext context, WorkItem item) async {
    await Clipboard.setData(ClipboardData(text: WorkExport.item(item)));
    showNoticeSnack('Copied "${item.title}" as Markdown');
  }

  Future<void> copyBoard(List<WorkItem> active) async {
    final archived = await service.streamArchived().first;
    await Clipboard.setData(ClipboardData(text: WorkExport.board(active, archived, now: service.now())));
    showNoticeSnack('Copied all work as Markdown');
  }

  /// Runs [op] and routes any failure to the shared error snackbar.
  static Future<void> guard(Future<void> Function() op, String action) async {
    try {
      await op();
    } catch (e, s) {
      reportError(e, s, action);
    }
  }
}
