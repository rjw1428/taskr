import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/date.service.dart';
import 'package:taskr/services/models.dart';

class RecurringTaskForm extends StatefulWidget {
  const RecurringTaskForm({super.key, required this.startDate, required this.onRecurringTaskChanged});

  final String? startDate;
  final void Function(RecurringTask) onRecurringTaskChanged;

  @override
  State<RecurringTaskForm> createState() => RecurringTaskFormState();
}

class RecurringTaskFormState extends State<RecurringTaskForm> {
  final _formKey = GlobalKey<FormState>();
  String _recurrenceType = 'Daily';
  int _frequency = 1;
  final Map<String, bool> _daysOfWeek = {
    'Su': false,
    'Mo': false,
    'Tu': false,
    'We': false,
    'Th': false,
    'Fr': false,
    'Sa': false,
  };
  DateTime? _endDate;
  final TextEditingController _endDateController = TextEditingController();
  int _dayOfMonth = 1;
  String? _startDate;

  @override
  void initState() {
    super.initState();
    _startDate = widget.startDate;
    if (_endDate != null) {
      _endDateController.text = DateService().getString(_endDate!);
    }
  }

  @override
  void dispose() {
    _endDateController.dispose();
    super.dispose();
  }

  void _updateParent() {
    final recurringTask = RecurringTask(
      recurrenceType: _recurrenceType,
      frequency: _frequency,
      daysOfWeek: _daysOfWeek,
      endDate: _endDate,
      dayOfMonth: _dayOfMonth,
    );
    widget.onRecurringTaskChanged(recurringTask);
  }

  String? validate() {
    if (!_formKey.currentState!.validate()) {
      return 'Please fix the errors above.';
    }
    if (_recurrenceType == 'Weekly' && !_daysOfWeek.values.any((day) => day)) {
      return 'Please select at least one day for weekly recurrence.';
    }

    // The validator on the TextFormField should handle this, but as a fallback
    if (_endDate == null) {
      return 'Please select an end date.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          DropdownButton<String>(
            value: _recurrenceType,
            onChanged: (String? newValue) {
              setState(() {
                _recurrenceType = newValue!;
                _updateParent();
              });
            },
            items: <String>['Daily', 'Weekly', 'Monthly', 'Yearly'].map<DropdownMenuItem<String>>((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
          ),
          if (_recurrenceType == 'Weekly') ...[
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(
                "Every",
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SizedBox(
                width: 50.0,
                child: TextFormField(
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                  initialValue: _frequency.toString(),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || int.tryParse(value) == null || int.parse(value) < 1) {
                      return 'Invalid';
                    }
                    return null;
                  },
                  onChanged: (value) {
                    _frequency = int.tryParse(value) ?? 1;
                    _updateParent();
                  },
                ),
              ),
              Text(
                "Weeks",
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ]),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _daysOfWeek.keys.map((String key) {
                  return Column(
                    children: [
                      Checkbox(
                        value: _daysOfWeek[key],
                        onChanged: (bool? value) {
                          setState(() {
                            _daysOfWeek[key] = value!;
                            _updateParent();
                          });
                        },
                      ),
                      Text(key),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
          if (_recurrenceType == 'Monthly') ...[
            SizedBox(
              width: 80,
              child: TextFormField(
                initialValue: _dayOfMonth.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
                decoration: const InputDecoration(
                  label: Center(
                    child: Text(
                      'Day of Month',
                    ),
                  ),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || int.tryParse(value) == null || int.parse(value) < 1 || int.parse(value) > 31) {
                    return 'Invalid';
                  }
                  return null;
                },
                onChanged: (value) {
                  _dayOfMonth = int.tryParse(value) ?? 1;
                  _updateParent();
                },
              ),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _endDateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'End Date',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'End date is required';
                    }
                    return null;
                  },
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate:
                          _endDate ?? (_startDate != null ? DateService().getDate(_startDate!) : DateTime.now()),
                      firstDate: _startDate != null ? DateService().getDate(_startDate!) : DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                    );
                    if (date != null) {
                      setState(() {
                        _endDate = date;
                        _endDateController.text = DateService().getString(date);
                        _updateParent();
                      });
                    }
                  },
                ),
              ),
              if (_endDate != null)
                IconButton(
                  onPressed: () {
                    setState(() {
                      _endDate = null;
                      _endDateController.clear();
                      _updateParent();
                    });
                  },
                  icon: const Icon(FontAwesomeIcons.xmark),
                ),
            ],
          )
        ],
      ),
    );
  }
}
