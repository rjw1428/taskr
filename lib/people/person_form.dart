import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/people.provider.dart';
import 'package:taskr/shared/shared.dart';

class PersonFormPage extends StatefulWidget {
  final Person? person;

  const PersonFormPage({super.key, this.person});

  @override
  State<PersonFormPage> createState() => _PersonFormPageState();
}

class _PersonFormPageState extends State<PersonFormPage> {
  late TextEditingController _nameController;
  late TextEditingController _ageController;
  late TextEditingController _birthdayController;
  late TextEditingController _jobController;
  late TextEditingController _spouseController;
  late List<KidForm> _kids;

  // The picked birthday as a real date. The controller only holds the formatted
  // text for display; storing the DateTime here avoids re-parsing that display
  // string (which is not ISO-8601) when saving.
  DateTime? _birthday;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.person?.name ?? '');
    _ageController = TextEditingController(text: widget.person?.age?.toString() ?? '');
    _birthday = widget.person?.birthday != null ? DateTime.parse(widget.person!.birthday!) : null;
    _birthdayController = TextEditingController(
      text: _birthday != null ? DateFormat('MMM d, yyyy').format(_birthday!) : '',
    );
    _jobController = TextEditingController(text: widget.person?.job ?? '');
    _spouseController = TextEditingController(text: widget.person?.spouse ?? '');
    _kids = (widget.person?.kids ?? []).map((k) => KidForm.fromKid(k)).toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _birthdayController.dispose();
    _jobController.dispose();
    _spouseController.dispose();
    super.dispose();
  }

  Future<void> _selectBirthday() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _birthday = picked;
        _birthdayController.text = DateFormat('MMM d, yyyy').format(picked);
      });
    }
  }

  void _addKid() {
    setState(() {
      _kids.add(KidForm());
    });
  }

  void _removeKid(int index) {
    setState(() {
      _kids.removeAt(index);
    });
  }

  Future<void> _savePerson() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }

    try {
      final kids = _kids.where((k) => k.name.isNotEmpty).map((k) => k.toKid()).toList();

      final person = Person(
        id: widget.person?.id,
        name: _nameController.text.trim(),
        age: _ageController.text.isNotEmpty ? int.tryParse(_ageController.text) : null,
        birthday: _birthday != null ? _birthday!.toIso8601String().split('T')[0] : null,
        job: _jobController.text.trim().isEmpty ? null : _jobController.text.trim(),
        spouse: _spouseController.text.trim().isEmpty ? null : _spouseController.text.trim(),
        kids: kids,
      );

      if (widget.person == null) {
        await context.read<PeopleProvider>().addPerson(person);
      } else {
        await context.read<PeopleProvider>().updatePerson(person);
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
        title: Text(widget.person == null ? 'Add Person' : 'Edit Person'),
        actions: [
          TextButton(
            onPressed: _savePerson,
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
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.sm)),
              ),
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _ageController,
              decoration: InputDecoration(
                labelText: 'Age',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.sm)),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _birthdayController,
              decoration: InputDecoration(
                labelText: 'Birthday',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.sm)),
                suffixIcon: const Icon(FontAwesomeIcons.calendar, size: 16),
              ),
              readOnly: true,
              onTap: _selectBirthday,
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _jobController,
              decoration: InputDecoration(
                labelText: 'Job',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.sm)),
              ),
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _spouseController,
              decoration: InputDecoration(
                labelText: 'Spouse',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.sm)),
              ),
            ),
            const SizedBox(height: Insets.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Kids', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(FontAwesomeIcons.plus, size: 16),
                  onPressed: _addKid,
                  tooltip: 'Add kid',
                ),
              ],
            ),
            const SizedBox(height: Insets.sm),
            ..._kids.asMap().entries.map((entry) {
              final index = entry.key;
              final kid = entry.value;
              return _buildKidForm(index, kid);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildKidForm(int index, KidForm kid) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: t.hairline),
          borderRadius: BorderRadius.circular(Corners.sm),
        ),
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: kid.name,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.sm)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 10),
                    ),
                    onChanged: (value) {
                      kid.name = value;
                    },
                  ),
                ),
                const SizedBox(width: Insets.sm),
                IconButton(
                  icon: Icon(FontAwesomeIcons.trash, size: 16, color: theme.colorScheme.error),
                  onPressed: () => _removeKid(index),
                  tooltip: 'Remove kid',
                ),
              ],
            ),
            const SizedBox(height: Insets.sm),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    initialValue: kid.age?.toString() ?? '',
                    decoration: InputDecoration(
                      labelText: 'Age',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.sm)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 10),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      kid.age = int.tryParse(value);
                    },
                  ),
                ),
                const SizedBox(width: Insets.sm),
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    initialValue: kid.birthday != null
                        ? DateFormat('MMM d').format(DateTime.parse(kid.birthday!))
                        : '',
                    decoration: InputDecoration(
                      labelText: 'Birthday',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Corners.sm)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 10),
                      suffixIcon: const Icon(FontAwesomeIcons.calendar, size: 14),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: kid.birthday != null ? DateTime.parse(kid.birthday!) : DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          kid.birthday = picked.toIso8601String().split('T')[0];
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class KidForm {
  String name = '';
  int? age;
  String? birthday;
  String? dateAdded;

  KidForm();

  KidForm.fromKid(Kid k) {
    name = k.name;
    age = k.age;
    birthday = k.birthday;
    dateAdded = k.dateAdded;
  }

  Kid toKid() {
    return Kid(
      name: name,
      age: age ?? 0,
      birthday: birthday,
      dateAdded: dateAdded ?? DateTime.now().toIso8601String().split('T')[0],
    );
  }
}
