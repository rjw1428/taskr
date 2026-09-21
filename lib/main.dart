import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart';
import 'package:taskr/app.dart';
import 'package:taskr/firebase_options.dart';
import 'package:taskr/services/parking_notifications.dart';
import 'package:taskr/services/parking_work.dart';
import 'package:taskr/shared/shared.dart';

export 'package:taskr/app.dart' show MyApp, navigatorKey;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // This isolate starts cold — main() has not run in it. Without a binding
  // there are no platform channels, and without a Firebase app the handler
  // throws before reaching any of our code, silently drawing nothing.
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Firebase already initialized in background isolate: $e');
  }

  debugPrint('Handling a background message: ${message.data}');

  // The prompt has to be drawn locally even with the app terminated, because
  // FCM cannot render the Yes/No action buttons itself. The push is data-only,
  // so if this does not draw it, nothing does.
  if (message.data['type'] == parkingPromptType) {
    try {
      await initLocalNotifications();
      await showParkingPrompt(message.data);
    } catch (e, s) {
      // A throw here is invisible in release, and the symptom is simply no
      // notification — the hardest possible thing to diagnose from a phone.
      debugPrint('Failed to draw parking prompt: $e\n$s');
    }
  }

  // The result push carries a `notification` block, so Android has already
  // drawn it by the time this runs — nothing to display, but this is the only
  // Dart that sees it while the app is backgrounded, and so the only chance to
  // get the confirmation into the notification centre.
  if (message.data['type'] == parkingResultType) {
    try {
      await recordParkingResult(message.data);
    } catch (e, s) {
      debugPrint('Failed to record parking result: $e\n$s');
    }
  }
}

void main() async {
  // Everything runs inside a guarded zone so a write that fails without a local
  // try/catch (most `await service.x()` calls in button handlers) surfaces as an
  // error snackbar instead of dying silently in the console.
  runZonedGuarded(_bootstrap, (error, stack) => reportError(error, stack));
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter error: ${details.exception}');
  };
  // Errors from platform callbacks that never reach the zone handler.
  PlatformDispatcher.instance.onError = (error, stack) {
    reportError(error, stack);
    return true;
  };
  await dotenv.load(fileName: ".env");
  await Workmanager().initialize(parkingCallbackDispatcher);
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase already initialized: $e');
  }

  if (kIsWeb) {
    // Mobile keeps an offline cache by default; web does not. Without one a
    // listener that re-attaches (every tab switch, every rebuilt StreamBuilder)
    // re-reads its whole result set instead of resuming from what it had.
    try {
      FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
    } catch (e) {
      debugPrint('Firestore web persistence unavailable: $e');
    }
  }

  // if (kDebugMode) {
  //   try {
  //     debugPrint('Using local setup');
  //     FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  //     await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  //   } catch (e) {
  //     debugPrint(e.toString());
  //   }
  // }

  // Handle background messages
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize local notifications for foreground display
  if (!kIsWeb) {
    await initLocalNotifications();
  }

  runApp(const MyApp());
}
