import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/shared.dart';

/// What the next-action sheet hands back. `waitingOn` is null when blank.
typedef NextActionInput = ({String text, String? waitingOn});

/// Bottom sheet that collects a next action's text and optional "waiting on".
/// It persists nothing; the caller pops with a [NextActionInput].
class NextActionForm extends StatefulWidget {
  final NextAction? existing;
  const NextActionForm({super.key, this.existing});

  static Future<NextActionInput?> show(BuildContext context, {NextAction? existing}) =>
      showModalBottomSheet<NextActionInput>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
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
    Navigator.of(context).pop<NextActionInput>((text: text, waitingOn: waiting.isEmpty ? null : waiting));
  }

  @override
  Widget build(BuildContext context) {
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
        ],
      ),
    );
  }
}
