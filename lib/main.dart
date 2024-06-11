import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:taskr/firebase_options.dart';
import 'package:taskr/theme.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        theme: appTheme,
        title: 'Taskr To-Do App',
        home: Scaffold(
            appBar: AppBar(
              title: const Text(
                'Taskr',
              ),
            ),
            body: Container(
              padding: const EdgeInsets.only(top: 24),
              child: const Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'Hello World',
                        textAlign: TextAlign.center,
                      ),
                    )
                  ]),
            )));
  }
}
