import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';

class JournalModal extends StatefulWidget {
  final String date;
  const JournalModal({super.key, required this.date});

  @override
  State<JournalModal> createState() => _JournalModalState();
}

class _JournalModalState extends State<JournalModal> {
  final _thinkingController = TextEditingController();
  final _feelingController = TextEditingController();
  final _gratitudeController = TextEditingController();
  final _journalService = JournalService();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadEntry();
  }

  Future<void> _loadEntry() async {
    final entry = await _journalService.getEntry(widget.date);
    if (entry != null) {
      _thinkingController.text = entry.thinking ?? '';
      _feelingController.text = entry.feeling ?? '';
      _gratitudeController.text = entry.gratitude ?? '';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final entry = JournalEntry(
      date: widget.date,
      thinking: _thinkingController.text.trim().isEmpty ? null : _thinkingController.text.trim(),
      feeling: _feelingController.text.trim().isEmpty ? null : _feelingController.text.trim(),
      gratitude: _gratitudeController.text.trim().isEmpty ? null : _gratitudeController.text.trim(),
    );
    await _journalService.saveEntry(entry);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _thinkingController.dispose();
    _feelingController.dispose();
    _gratitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Journal — ${widget.date}'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Save', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection('What are you thinking?', _thinkingController),
                  const SizedBox(height: 24),
                  _buildSection('How are you feeling?', _feelingController),
                  const SizedBox(height: 24),
                  _buildSection('What are you grateful for?', _gratitudeController),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: Insets.sm),
        TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Optional...',
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }
}
