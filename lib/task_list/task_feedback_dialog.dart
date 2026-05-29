import 'package:flutter/material.dart';

class TaskFeedbackDialog extends StatefulWidget {
  final String? existingFeedback;
  const TaskFeedbackDialog({super.key, this.existingFeedback});

  @override
  State<TaskFeedbackDialog> createState() => _TaskFeedbackDialogState();
}

class _TaskFeedbackDialogState extends State<TaskFeedbackDialog> {
  static const _options = [
    ('too_easy', 'Too easy'),
    ('too_hard', 'Too hard'),
    ('not_relevant', 'Not relevant'),
    ('enjoyed', 'Enjoyed this'),
  ];

  String? _selected;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.existingFeedback != null) {
      final parts = widget.existingFeedback!.split('|');
      final chip = parts[0];
      if (_options.any((o) => o.$1 == chip)) {
        _selected = chip;
        if (parts.length > 1) {
          _commentController.text = parts.sublist(1).join('|');
        }
      } else {
        _commentController.text = widget.existingFeedback!;
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  String? _buildResult() {
    final comment = _commentController.text.trim();
    if (_selected == null && comment.isEmpty) return null;
    if (_selected != null && comment.isNotEmpty) return '$_selected|$comment';
    if (_selected != null) return _selected;
    return comment;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('How was this task?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _options.map((option) {
              final isSelected = _selected == option.$1;
              return ChoiceChip(
                label: Text(option.$2),
                selected: isSelected,
                selectedColor: Colors.orange,
                onSelected: (selected) {
                  setState(() {
                    _selected = selected ? option.$1 : null;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _commentController,
            decoration: const InputDecoration(
              hintText: 'Additional comments (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_buildResult()),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
