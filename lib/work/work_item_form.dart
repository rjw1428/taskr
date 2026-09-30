import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/work.service.dart';
import 'package:taskr/shared/shared.dart';

/// Bottom-sheet form for creating (item == null) or editing a work item.
/// Editing touches title and notes only; next actions and updates are owned
/// by their own flows so a stale sheet can never clobber them.
class WorkItemForm extends StatefulWidget {
  final WorkItem? item;
  final WorkService? service;
  const WorkItemForm({super.key, this.item, this.service});

  @override
  State<WorkItemForm> createState() => _WorkItemFormState();
}

class _WorkItemFormState extends State<WorkItemForm> {
  late final WorkService _service = widget.service ?? WorkService();
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _notes = TextEditingController(text: widget.item?.notes ?? '');
  final _firstAction = TextEditingController();
  final _firstWaiting = TextEditingController();
  String? _error;
  bool _saving = false;

  bool get _isEdit => widget.item != null;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _firstAction.dispose();
    _firstWaiting.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      if (_isEdit) {
        await _service.updateDetails(widget.item!.id!, title: title, notes: _notes.text.trim());
      } else {
        final actionText = _firstAction.text.trim();
        final waiting = _firstWaiting.text.trim();
        final actions = actionText.isEmpty
            ? const <NextAction>[]
            : [
                NextAction(
                  id: _service.newId(),
                  text: actionText,
                  waitingOn: waiting.isEmpty ? null : waiting,
                  createdAt: _service.now(),
                )
              ];
        await _service.add(WorkItem(title: title, notes: _notes.text.trim(), nextActions: actions));
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e, s) {
      reportError(e, s, _isEdit ? 'Save work item' : 'Add work item');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: _isEdit ? 'Edit work item' : 'New work item',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('work-title'),
              controller: _title,
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Title', errorText: _error),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: Insets.md),
            TextField(
              key: const Key('work-notes'),
              controller: _notes,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes', hintText: 'Context, links, who you are waiting on and since when'),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: Insets.lg),
              const SectionHeader('First next action (optional)', padding: EdgeInsets.only(bottom: Insets.sm)),
              TextField(
                key: const Key('work-first-action'),
                controller: _firstAction,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Next action'),
              ),
              const SizedBox(height: Insets.md),
              TextField(
                key: const Key('work-first-waiting'),
                controller: _firstWaiting,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Waiting on (optional)'),
              ),
            ],
            const SizedBox(height: Insets.xl),
            PrimaryButton(_isEdit ? 'Save' : 'Add', onPressed: _saving ? null : _save),
          ],
        ),
      ),
    );
  }
}
