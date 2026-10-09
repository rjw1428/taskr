import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/shared.dart';

/// What the next-action sheet hands back. `waitingOn` is null when blank, and
/// `remove` asks the caller to delete the action instead of saving — only the
/// edit sheet can set it, so the add path never sees it true.
typedef NextActionInput = ({String text, String? waitingOn, bool remove});

/// Bottom sheet that collects a next action's text and optional "waiting on".
/// It persists nothing; the caller pops with a [NextActionInput]. Editing an
/// existing action also offers Remove, which deletes it outright — the caller
/// owns the Undo.
class NextActionForm extends StatefulWidget {
  final NextAction? existing;
  const NextActionForm({super.key, this.existing});

  static Future<NextActionInput?> show(BuildContext context, {NextAction? existing}) =>
      showAppSheet<NextActionInput>(
        context,
        builder: (_) => NextActionForm(existing: existing),
      );

  @override
  State<NextActionForm> createState() => _NextActionFormState();
}

class _NextActionFormState extends State<NextActionForm> {
  late final _text = TextEditingController(text: widget.existing?.text ?? '');
  late final _waiting = TextEditingController(text: widget.existing?.waitingOn ?? '');
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _waiting.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Next action is required');
      return;
    }
    final waiting = _waiting.text.trim();
    Navigator.of(context)
        .pop<NextActionInput>((text: text, waitingOn: waiting.isEmpty ? null : waiting, remove: false));
  }

  /// Closes with the delete request. The text is whatever the field holds and
  /// goes unread; validation is skipped because nothing is being saved.
  void _remove() => Navigator.of(context)
      .pop<NextActionInput>((text: _text.text.trim(), waitingOn: null, remove: true));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBottomSheet(
      title: widget.existing == null ? 'Next action' : 'Edit next action',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('next-action-text'),
            controller: _text,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'What is the next step?', errorText: _error),
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: Insets.md),
          TextField(
            key: const Key('next-action-waiting'),
            controller: _waiting,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Waiting on (optional)', hintText: 'A person, a team, a delivery'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: Insets.xl),
          PrimaryButton(widget.existing == null ? 'Add' : 'Save', onPressed: _submit),
          if (widget.existing != null) ...[
            const SizedBox(height: Insets.sm),
            TextButton.icon(
              key: const Key('next-action-remove'),
              onPressed: _remove,
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              icon: const Icon(FontAwesomeIcons.trashCan, size: 14),
              label: const Text('Remove'),
            ),
          ],
        ],
      ),
    );
  }
}
