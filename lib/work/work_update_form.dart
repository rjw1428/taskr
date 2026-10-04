import 'package:flutter/material.dart';
import 'package:taskr/shared/shared.dart';

/// Bottom sheet for a dated progress update. Pops with the text, or null.
class WorkUpdateForm extends StatefulWidget {
  const WorkUpdateForm({super.key});

  static Future<String?> show(BuildContext context) => showAppSheet<String>(
        context,
        builder: (_) => const WorkUpdateForm(),
      );

  @override
  State<WorkUpdateForm> createState() => _WorkUpdateFormState();
}

class _WorkUpdateFormState extends State<WorkUpdateForm> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Update is required');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: 'Add update',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('work-update-text'),
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'What happened?', errorText: _error),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: Insets.xl),
          PrimaryButton('Add', onPressed: _submit),
        ],
      ),
    );
  }
}
