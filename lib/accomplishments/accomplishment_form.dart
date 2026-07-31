import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taskr/accomplishments/accomplishment_color.dart';
import 'package:taskr/services/accomplishment.provider.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/shared.dart';

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
  int _difficultyScore = 1;
  String pageHeader = 'Add Accomplishment';
  String actionButton = 'Add';

  @override
  void initState() {
    super.initState();
    if (widget.accomplishment != null) {
      _title = widget.accomplishment!.title;
      _description = widget.accomplishment!.description ?? '';
      _difficultyScore = widget.accomplishment!.difficultyScore;
      pageHeader = 'Edit Accomplishment';
      actionButton = 'Update';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(pageHeader),
      ),
      body: Padding(
        padding: const EdgeInsets.all(Insets.lg),
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
                maxLines: null,
                minLines: 3,
                keyboardType: TextInputType.multiline,
                onSaved: (value) {
                  _description = value!;
                },
              ),
              const SizedBox(height: Insets.lg),
              Row(
                children: [
                  Text('Difficulty: ', style: theme.textTheme.bodyLarge),
                  Text('$_difficultyScore / 10',
                      style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: accomplishmentScoreColor(theme, _difficultyScore))),
                ],
              ),
              Slider(
                value: _difficultyScore.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: _difficultyScore.toString(),
                onChanged: (double value) {
                  setState(() {
                    _difficultyScore = value.round();
                  });
                },
              ),
              const SizedBox(height: Insets.xl),
              PrimaryButton(
                actionButton,
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
                        difficultyScore: _difficultyScore,
                      );
                      Provider.of<AccomplishmentProvider>(context, listen: false)
                          .updateAccomplishment(updatedAccomplishment);
                    } else {
                      final newAccomplishment = Accomplishment(
                        title: _title!,
                        description: _description,
                        date: DateTime.now().toIso8601String(),
                        difficultyScore: _difficultyScore,
                      );
                      Provider.of<AccomplishmentProvider>(context, listen: false).addAccomplishment(newAccomplishment);
                    }

                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
