import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/login/create_account.dart';
import 'package:taskr/services/auth.service.dart';
import 'package:taskr/shared/shared.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ContentColumn(child: Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: Center(
          child: Container(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Image.asset('assets/images/logo.png', height: 200, width: 200),
            LoginButton(
              icon: FontAwesomeIcons.google,
              text: "Login with Google",
              color: Colors.blue,
              loginMethod: AuthService().googleLogin,
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pushNamed(createAccountRoute),
              child: const Text('New here? Create an account'),
            ),
          ],
        ),
      )),
    ));
  }
}

class LoginButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  final Function loginMethod;

  /// Caps the button's width. The default fits "Login with Google"; a longer
  /// label needs more room or it wraps onto a second line.
  final double maxWidth;

  /// Shows a spinner in place of the icon and ignores taps. A sign-in round
  /// trip is slow enough that without this the button looks inert and invites
  /// a second tap, which opens a second account picker.
  final bool busy;

  const LoginButton(
      {super.key,
      required this.text,
      required this.icon,
      required this.color,
      required this.loginMethod,
      this.maxWidth = 200.0,
      this.busy = false});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ElevatedButton.icon(
        icon: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(
                icon,
                // Icon sits on a brand-colored sign-in button; white for contrast.
                color: Colors.white,
                size: 20,
              ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.all(Insets.xl),
          backgroundColor: color,
          foregroundColor: Colors.white,
        ),
        onPressed: busy ? null : () => loginMethod(),
        label: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
