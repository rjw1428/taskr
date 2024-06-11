import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

var appTheme = ThemeData(
  fontFamily: GoogleFonts.roboto().fontFamily,
  bottomAppBarTheme: const BottomAppBarTheme(
    color: Colors.black87,
  ),
  brightness: Brightness.dark,
  textTheme: const TextTheme(
    bodyLarge: TextStyle(fontSize: 18, color: Colors.red),
    bodyMedium: TextStyle(fontSize: 16, color: Colors.green),
    bodySmall: TextStyle(fontSize: 12, color: Colors.blue),
  ),
  buttonTheme: const ButtonThemeData(
      // buttonColor: Colors.orange,
      ),
);
