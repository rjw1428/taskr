import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';

class AddTagScreen extends StatelessWidget {
  final Tag? tag;
  const AddTagScreen({super.key, this.tag});

  @override
  Widget build(BuildContext context) {
    return Material(
        color: Colors.transparent,
        child: Center(
            child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Column(children: [
                    Text(tag == null ? "Add tag" : "Edit tag",
                        style: const TextStyle(fontSize: 40, color: Colors.black)),
                    SizedBox(
                      height: 300,
                      child: TagForm(tag: tag),
                    ),
                  ]),
                ))));
  }
}

class TagForm extends StatefulWidget {
  final Tag? tag;
  const TagForm({super.key, this.tag});

  @override
  TagFormState createState() => TagFormState();
}

class TagFormState extends State<TagForm> {
  final TextEditingController _label = TextEditingController();
  bool apiPending = false;
  bool archived = false;

  Future<void> _submit() async {
    setState(() => apiPending = true);
    if (_label.text.isEmpty) {
      return Future.error('Tag label missing');
    }
    if (widget.tag == null) {
      await TagService().addTag(_label.text);
    } else {
      await TagService().updateTag(widget.tag!.id, _label.text);
    }
    setState(() => apiPending = false);

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tag != null) {
      _label.text = widget.tag!.label;
    }

    return Form(
        child: Column(
      children: [
        TextFormField(
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Tag Name'),
          controller: _label,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter the tag name';
            }
            return null;
          },
        ),
        if (widget.tag != null)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('Archive'),
            Checkbox(value: archived, onChanged: (value) => setState(() => archived = value!))
          ]),
        ElevatedButton(onPressed: apiPending ? null : () => _submit(), child: const Text('Save')),
        ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Close'))
      ],
    ));
  }
}
