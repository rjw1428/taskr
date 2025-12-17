import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/accomplishment.provider.dart';
import 'package:taskr/services/models.dart';

class AddAccomplishmentPage extends StatefulWidget {
  const AddAccomplishmentPage({super.key});

  @override
  _AddAccomplishmentPageState createState() => _AddAccomplishmentPageState();
}

class _AddAccomplishmentPageState extends State<AddAccomplishmentPage> {
  final _formKey = GlobalKey<FormState>();
  String _title = '';
  String _description = '';
  Difficulty _difficulty = Difficulty.low;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Accomplishment'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
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
                    final newAccomplishment = Accomplishment(
                      title: _title,
                      description: _description,
                      date: DateTime.now().toIso8601String(),
                      difficulty: _difficulty,
                    );
                    Provider.of<AccomplishmentProvider>(context, listen: false)
                        .addAccomplishment(newAccomplishment);
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
