import 'package:flutter/material.dart';

class ErrorMessage extends StatelessWidget {
  final String message;
  const ErrorMessage({super.key, this.message = ''});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.redAccent.withAlpha(25),
      child: Text(
        message,
        style: const TextStyle(color: Colors.red, fontSize: 16.0),
      ),
    );
  }
}
