import 'package:flutter/material.dart';

enum Priority { high, medium, low }

Map<Priority, Color> priorityColors = {
  Priority.high: Color.fromARGB(255, 87, 10, 10),
  Priority.medium: Color.fromARGB(255, 177, 148, 23),
  Priority.low: const Color.fromARGB(255, 40, 79, 42),
};
