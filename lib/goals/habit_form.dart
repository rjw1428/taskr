import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/task_list/recurring_task_form.dart';

/// Create or edit a habit. Manual (no AI); reuses [RecurringTaskForm] for the
/// cadence (with its end-date hidden, since habits are open-ended).
class HabitForm extends StatefulWidget {
  final Habit? habit;
  const HabitForm({super.key, this.habit});

  @override
  State<HabitForm> createState() => _HabitFormState();
}

class _HabitFormState extends State<HabitForm> {
  final _formKey = GlobalKey<FormState>();
  final _recurringKey = GlobalKey<RecurringTaskFormState>();
  late final TextEditingController _title;
  Effort _effort = Effort.low;
  RecurringTask? _recurrence;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.habit?.title ?? '');
    if (widget.habit != null) {
      _effort = widget.habit!.effort;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String _effortLabel(Effort e) => e.name[0].toUpperCase() + e.name.substring(1);

  RecurringTask? get _initialRecurrence {
    final h = widget.habit;
    if (h == null) return null;
    return RecurringTask(
      recurrenceType: h.recurrenceType,
      frequency: h.frequency,
      daysOfWeek: h.daysOfWeek,
      dayOfMonth: h.dayOfMonth ?? 1,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final recurringError = _recurringKey.currentState?.validate();
    if (recurringError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(recurringError)));
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final rt = _recurrence ?? _initialRecurrence ?? RecurringTask(recurrenceType: 'Daily');
    final weekly = rt.recurrenceType == 'Weekly';
    final monthly = rt.recurrenceType == 'Monthly';
    try {
      if (widget.habit == null) {
        await HabitService().addHabit(Habit(
          title: _title.text.trim(),
          effort: _effort,
          recurrenceType: rt.recurrenceType,
          frequency: rt.frequency ?? 1,
          daysOfWeek: weekly ? rt.daysOfWeek : null,
          dayOfMonth: monthly ? (rt.dayOfMonth ?? 1) : null,
          startDate: DateService().getString(DateTime.now()),
          status: 'active',
        ));
      } else {
        final h = widget.habit!;
        h.title = _title.text.trim();
        h.effort = _effort;
        h.recurrenceType = rt.recurrenceType;
        h.frequency = rt.frequency ?? 1;
        h.daysOfWeek = weekly ? rt.daysOfWeek : null;
        h.dayOfMonth = monthly ? (rt.dayOfMonth ?? 1) : null;
        await HabitService().updateHabit(h);
      }
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not save habit: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.habit == null ? 'New Habit' : 'Edit Habit'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Habit'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a habit name' : null,
              ),
              const SizedBox(height: Insets.xl),
              Text('EFFORT', style: theme.textTheme.labelSmall?.copyWith(color: t.textFaint, letterSpacing: 1.4)),
              const SizedBox(height: Insets.sm),
              Wrap(
                spacing: Insets.sm,
                children: Effort.values.map((e) {
                  final p = t.of(e);
                  final selected = _effort == e;
                  return ChoiceChip(
                    label: Text(_effortLabel(e)),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _effort = e),
                    backgroundColor: theme.colorScheme.surface,
                    selectedColor: p.fill,
                    side: BorderSide(color: selected ? p.accent : t.hairline, width: selected ? 1.5 : 1),
                    labelStyle: theme.textTheme.labelLarge?.copyWith(
                      color: selected ? p.ink : t.textMuted,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: Insets.sm),
              Text('Effort sets how many points completing the habit is worth; the streak is tracked separately.',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.textMuted)),
              const SizedBox(height: Insets.xl),
              Text('CADENCE', style: theme.textTheme.labelSmall?.copyWith(color: t.textFaint, letterSpacing: 1.4)),
              const SizedBox(height: Insets.sm),
              RecurringTaskForm(
                key: _recurringKey,
                startDate: DateService().getString(DateTime.now()),
                hideEndDate: true,
                recurringTask: _initialRecurrence,
                onRecurringTaskChanged: (rt) => _recurrence = rt,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
