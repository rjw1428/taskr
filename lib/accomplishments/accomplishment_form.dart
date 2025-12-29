import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/accomplishment.provider.dart';
import 'package:taskr/services/models.dart';

class AccomplishmentForm extends StatefulWidget {
  final Accomplishment? accomplishment;

  const AccomplishmentForm({super.key, this.accomplishment});

  @override
  State<AccomplishmentForm> createState() => _AccomplishmentFormState();
}

class _AccomplishmentFormState extends State<AccomplishmentForm> {
  final _formKey = GlobalKey<FormState>();
  String? _title;
  String? _description;
  Difficulty _difficulty = Difficulty.low;
  String pageHeader = 'Add Accomplishment';
  String actionButton = 'Add';

  @override
  void initState() {
    super.initState();
    if (widget.accomplishment != null) {
      _title = widget.accomplishment!.title;
      _description = widget.accomplishment!.description ?? '';
      _difficulty = widget.accomplishment!.difficulty;
      pageHeader = 'Edit Accomplishment';
      actionButton = 'Update';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(pageHeader),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                initialValue: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
                onSaved: (value) {
                  _title = value!;
                },
              ),
              TextFormField(
                initialValue: _description,
                decoration: const InputDecoration(labelText: 'Description'),
                onSaved: (value) {
                  _description = value!;
                },
              ),
              DropdownButtonFormField<Difficulty>(
                value: _difficulty,
                decoration: const InputDecoration(labelText: 'Difficulty'),
                items: Difficulty.values.map((Difficulty difficulty) {
                  return DropdownMenuItem<Difficulty>(
                    value: difficulty,
                    child: Text(difficulty.toString().split('.').last),
                  );
                }).toList(),
                onChanged: (Difficulty? newValue) {
                  setState(() {
                    _difficulty = newValue!;
                  });
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    _formKey.currentState!.save();
                    if (_title == null) {
                      debugPrint('Title Required');
                      return;
                    }
                    if (_description == null) {
                      debugPrint('Description Required');
                      return;
                    }
                    if (widget.accomplishment != null) {
                      final updatedAccomplishment = Accomplishment(
                        id: widget.accomplishment!.id,
                        title: _title!,
                        description: _description,
                        date: widget.accomplishment!.date,
                        difficulty: _difficulty,
                      );
                      Provider.of<AccomplishmentProvider>(context, listen: false)
                          .updateAccomplishment(updatedAccomplishment);
                    } else {
                      final newAccomplishment = Accomplishment(
                        title: _title!,
                        description: _description,
                        date: DateTime.now().toIso8601String(),
                        difficulty: _difficulty,
                      );
                      Provider.of<AccomplishmentProvider>(context, listen: false).addAccomplishment(newAccomplishment);
                    }

                    Navigator.pop(context);
                  }
                },
                child: Text(actionButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
