import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Attached to the root [MaterialApp] so any layer — including services with no
/// [BuildContext] and the top-level zone error handler — can surface a snackbar.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Human-readable text for a backend failure, always including the underlying
/// error code so a report from the field is actionable.
String describeError(Object error) {
  if (error is FirebaseFunctionsException) {
    return 'Server call failed (${error.code})${error.message != null ? ': ${error.message}' : ''}';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return "Save rejected by the server (permission-denied). The change wasn't stored.";
      case 'unauthenticated':
        return "You're signed out — sign in again to save changes.";
      case 'unavailable':
        return "Can't reach the server (unavailable). The change isn't saved yet.";
      case 'deadline-exceeded':
        return 'The server took too long (deadline-exceeded). The change may not be saved.';
      case 'not-found':
        return "That item no longer exists on the server (not-found).";
      case 'failed-precondition':
        return 'Save failed (failed-precondition)${error.message != null ? ': ${error.message}' : ''}';
      case 'resource-exhausted':
        return 'Quota exceeded (resource-exhausted). Try again later.';
      default:
        return 'Save failed (${error.code})${error.message != null ? ': ${error.message}' : ''}';
    }
  }
  if (error is PlatformException) {
    return 'Save failed (${error.code})${error.message != null ? ': ${error.message}' : ''}';
  }
  if (error is SocketException) {
    return "Can't reach the server — check your connection.";
  }
  if (error is TimeoutException) {
    return 'The server took too long to respond.';
  }
  return error.toString();
}

String? _lastMessage;
DateTime? _lastShownAt;

/// Shows [error] in an error-styled snackbar. [action] names what was being
/// attempted ("Couldn't save task"), so the user knows which change was lost.
///
/// Identical messages inside a few seconds are collapsed — a failing batch
/// (e.g. a recurring series) would otherwise queue one snackbar per write.
void showErrorSnack(Object error, {String? action, DateTime? now}) {
  final detail = describeError(error);
  _showSnack(action == null ? detail : '$action — $detail', isError: true, now: now);
}

/// Shows a neutral (non-error) notice, e.g. a write that is queued offline.
void showNoticeSnack(String message, {DateTime? now}) => _showSnack(message, isError: false, now: now);

void _showSnack(String message, {required bool isError, DateTime? now}) {
  final at = now ?? DateTime.now();
  if (_lastMessage == message && _lastShownAt != null && at.difference(_lastShownAt!) < const Duration(seconds: 4)) {
    return;
  }
  _lastMessage = message;
  _lastShownAt = at;
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger == null) {
    debugPrint('No messenger available for: $message');
    return;
  }
  final scheme = Theme.of(messenger.context).colorScheme;
  final fg = isError ? scheme.onErrorContainer : null;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(color: fg)),
      backgroundColor: isError ? scheme.errorContainer : null,
      duration: Duration(seconds: isError ? 6 : 4),
      action: SnackBarAction(
        label: 'Dismiss',
        textColor: fg,
        onPressed: () => scaffoldMessengerKey.currentState?.hideCurrentSnackBar(),
      ),
    ));
}

/// Logs [error] and surfaces it to the user. Use from anywhere a write can fail
/// — including `catch` blocks in services that have no context.
void reportError(Object error, [StackTrace? stack, String? action]) {
  debugPrint('ERROR${action != null ? ' ($action)' : ''}: $error');
  if (stack != null) debugPrintStack(stackTrace: stack);
  showErrorSnack(error, action: action);
}

/// Runs a write and reports any failure as a snackbar instead of throwing.
/// Returns null when the write failed, so callers can skip follow-up UI (a
/// `pop()`, an optimistic list update) that would otherwise imply success.
Future<T?> guardWrite<T>(Future<T> Function() op, {String? action}) async {
  try {
    return await op();
  } catch (e, s) {
    reportError(e, s, action);
    return null;
  }
}

@visibleForTesting
void resetErrorSnackDedupe() {
  _lastMessage = null;
  _lastShownAt = null;
}
