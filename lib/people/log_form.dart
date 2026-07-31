import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/people.provider.dart';
import 'package:taskr/shared/shared.dart';

class LogFormPage extends StatefulWidget {
  final String personId;
  final ConversationLog? log;

  const LogFormPage({
    super.key,
    required this.personId,
    this.log,
  });

  @override
  State<LogFormPage> createState() => _LogFormPageState();
}

class _LogFormPageState extends State<LogFormPage> {
  late TextEditingController _entryController;
  late TextEditingController _dateController;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _entryController = TextEditingController(text: widget.log?.entry ?? '');
    _selectedDate = widget.log != null ? DateTime.parse(widget.log!.date) : DateTime.now();
    _dateController = TextEditingController(
      text: DateFormat('MMM d, yyyy').format(_selectedDate),
    );
  }

  @override
  void dispose() {
    _entryController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('MMM d, yyyy').format(picked);
      });
    }
  }

  Future<void> _saveLog() async {
    if (_entryController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry cannot be empty')),
      );
      return;
    }

    final log = ConversationLog(
      id: widget.log?.id,
      date: _selectedDate.toIso8601String().split('T')[0],
      entry: _entryController.text,
    );

    try {
      if (widget.log == null) {
        await context.read<PeopleProvider>().addLog(widget.personId, log);
      } else {
        await context.read<PeopleProvider>().updateLog(widget.personId, widget.log!.id!, log);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.log == null ? 'Add Log Entry' : 'Edit Log Entry'),
        actions: [
          TextButton(
            onPressed: _saveLog,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _dateController,
              decoration: InputDecoration(
                labelText: 'Date',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.sm)),
                suffixIcon: const Icon(FontAwesomeIcons.calendar, size: 16),
              ),
              readOnly: true,
              onTap: _selectDate,
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _entryController,
              decoration: InputDecoration(
                labelText: 'What did you discuss?',
                hintText: 'E.g., Talked about his new job, asked about the kids...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.sm)),
                alignLabelWithHint: true,
              ),
              minLines: 5,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      ),
    );
  }
}
