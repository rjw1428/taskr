import 'package:flutter/material.dart';

enum Effort { high, medium, low }

Map<Effort, Color> priorityColors = {
  Effort.high: Color.fromARGB(255, 87, 10, 10),
  Effort.medium: Color.fromARGB(255, 177, 148, 23),
  Effort.low: const Color.fromARGB(255, 40, 79, 42),
};
