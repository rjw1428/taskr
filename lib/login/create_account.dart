import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/login/login.dart';
import 'package:taskr/services/auth.service.dart';
import 'package:taskr/shared/shared.dart';

/// Route for [CreateAccount], registered in `app.dart`.
const createAccountRoute = '/create-account';

/// Sign-up screen.
///
/// Google is the only provider, so there is no form here — the whole page is
/// one button plus the copy that tells the user what they are agreeing to.
/// Signing up and signing in are the same Google call; the difference is only
/// whether an account already existed, which [AuthService.signUpWithGoogle]
/// reports so this page can say "welcome back" instead of silently doing
/// nothing surprising.
class CreateAccount extends StatefulWidget {
  const CreateAccount({super.key});

  @override
  CreateAccountState createState() => CreateAccountState();
}

class CreateAccountState extends State<CreateAccount> {
  bool _busy = false;
  String? _error;

  Future<void> _signUp() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await AuthService().signUpWithGoogle();
    // The sign-in round trip outlives the route if the user backed out of it.
    if (!mounted) return;

    switch (result.outcome) {
      case SignUpOutcome.created:
      case SignUpOutcome.alreadyExisted:
        if (result.outcome == SignUpOutcome.alreadyExisted) {
          showNoticeSnack('You already had an account — signed you in.');
        }
        // The auth gate below this route rebuilds into the app on its own; this
        // page just has to get out of the way.
        Navigator.of(context).pop();
      case SignUpOutcome.cancelled:
        // Dismissing the picker is a deliberate "not now", not an error.
        setState(() => _busy = false);
      case SignUpOutcome.failed:
        setState(() {
          _busy = false;
          _error = describeError(result.error ?? 'Google sign-in failed');
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ContentColumn(
      child: Scaffold(
        appBar: AppBar(title: const Text('Create account')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset('assets/images/logo.png', height: 140, width: 140),
                const SizedBox(height: Insets.xl),
                Text(
                  'Create your taskr account',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Insets.md),
                Text(
                  'Taskr uses your Google account to sign you in, so there is no '
                  'password to set or remember.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.appTokens.textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Insets.xl),
                if (_error != null) ...[
                  ErrorMessage(message: _error!),
                  const SizedBox(height: Insets.xl),
                ],
                LoginButton(
                  icon: FontAwesomeIcons.google,
                  text: 'Sign up with Google',
                  color: Colors.blue,
                  maxWidth: 300,
                  loginMethod: _signUp,
                  busy: _busy,
                ),
                const SizedBox(height: Insets.lg),
                Text(
                  'We store your email address and the tasks, goals and notes you create. Nothing else.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.appTokens.textFaint),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Insets.xl),
                TextButton(
                  // Pops back to the login screen rather than pushing it, so
                  // the two pages can't stack up on each other.
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Already have an account? Log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
