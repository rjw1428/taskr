import 'package:flutter/material.dart';

class CoachingDialog extends StatelessWidget {
  final String response;
  const CoachingDialog({super.key, required this.response});

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.all(20),
        child: Material(
            color: Colors.transparent,
            child: Center(
                child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Words from your coach',
                                style: TextStyle(fontSize: 40, color: Colors.black)),
                            Text(response,
                                style: const TextStyle(color: Colors.black, fontSize: 16)),
                            ElevatedButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                                child: const Text('Close'))
                          ],
                        ))))));
  }
}
