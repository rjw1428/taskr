import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/firestore.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/theme.dart';
import 'firebase_options.dart';
import 'package:taskr/routes.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
    return StreamProvider(
      create: (_) => FireStoreService().streamReport(),
      initialData: Report(),
      child: MaterialApp(
        title: 'Flutter Demo',
        theme: appTheme,
        // home: const MyHomePage(title: 'Flutter Demo Home Page'),
        routes: appRoutes,
      ),
    );
  }
}
