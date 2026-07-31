import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/tag.provider.dart';

/// Add or edit a tag. Shown via `showDialog`; renders a themed [AlertDialog].
class AddTagScreen extends StatefulWidget {
  final Tag? tag;
  const AddTagScreen({super.key, this.tag});

  @override
  State<AddTagScreen> createState() => _AddTagScreenState();
}

class _AddTagScreenState extends State<AddTagScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.tag?.label ?? '');
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<TagProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pending = true);
    try {
      if (widget.tag == null) {
        await provider.addTag(_label.text.trim());
      } else {
        await provider.updateTag(widget.tag!.id, _label.text.trim());
      }
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _pending = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not save tag: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.tag != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit tag' : 'Add tag'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _label,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Tag name'),
          onFieldSubmitted: (_) => _submit(),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a tag name' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _pending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _pending ? null : _submit,
          child: _pending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
