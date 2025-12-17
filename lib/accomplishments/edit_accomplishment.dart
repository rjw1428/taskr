import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/accomplishment.provider.dart';
import 'package:taskr/services/models.dart';

class EditAccomplishmentPage extends StatefulWidget {
  final Accomplishment accomplishment;

  const EditAccomplishmentPage({super.key, required this.accomplishment});

  @override
  _EditAccomplishmentPageState createState() => _EditAccomplishmentPageState();
}

class _EditAccomplishmentPageState extends State<EditAccomplishmentPage> {
  final _formKey = GlobalKey<FormState>();
  late String _title;
  late String _description;
  late Difficulty _difficulty;

  @override
  void initState() {
    super.initState();
    _title = widget.accomplishment.title;
    _description = widget.accomplishment.description ?? '';
    _difficulty = widget.accomplishment.difficulty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Accomplishment'),
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
                    final updatedAccomplishment = Accomplishment(
                      id: widget.accomplishment.id,
                      title: _title,
                      description: _description,
                      date: widget.accomplishment.date,
                      difficulty: _difficulty,
                    );
                    Provider.of<AccomplishmentProvider>(context, listen: false)
                        .updateAccomplishment(updatedAccomplishment);
                    Navigator.pop(context);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
