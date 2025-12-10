import 'package:flutter/material.dart';

enum Effort { high, medium, low, info }

Map<Effort, Color> priorityColors = {
  Effort.high: const Color.fromARGB(255, 87, 10, 10),
  Effort.medium: const Color.fromARGB(255, 177, 148, 23),
  Effort.low: const Color.fromARGB(255, 40, 79, 42),
  Effort.info: const Color.fromARGB(255, 0, 0, 0),
};

Map<Effort, Color> dropdownColors = {
  Effort.high: Colors.red,
  Effort.medium: Colors.yellow,
  Effort.low: Colors.green,
  Effort.info: Colors.white
};

enum Days { mon, tus, wed, thurs, fri, sat, sun }

List<Color> chartColors = [
  Colors.green,
  Colors.red,
  Colors.blue,
  Colors.orange,
  Colors.green.shade900,
  Colors.white,
  Colors.yellow,
  Colors.pink,
  Colors.blueGrey,
  Colors.red.shade900,
  Colors.green,
  Colors.green,
  Colors.green,
];
