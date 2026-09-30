import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:taskr/shared/design/tokens.dart';
import 'package:taskr/shared/error_reporting.dart';
import 'package:taskr/shared/link_parser.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

/// How [LinkText] opens a URL. Returns true on success. Tests replace it so
/// nothing leaves the process; production launches externally.
typedef LinkLauncher = Future<bool> Function(Uri uri);

Future<bool> _externalLauncher(Uri uri) => launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);

/// Body text whose URLs are tappable. Plain text renders exactly as [style];
/// links get the accent color and an underline.
class LinkText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final LinkLauncher? launcher;

  /// Process-wide override, used by tests that mount screens containing links.
  static LinkLauncher? debugLauncher;

  const LinkText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.launcher,
  });

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _open(String url) async {
    final launch = widget.launcher ?? LinkText.debugLauncher ?? _externalLauncher;
    final uri = Uri.tryParse(url);
    var ok = false;
    try {
      ok = uri != null && await launch(uri);
    } catch (_) {
      ok = false;
    }
    if (!ok) showNoticeSnack('Could not open link');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = widget.style ?? theme.textTheme.bodyMedium ?? DefaultTextStyle.of(context).style;
    if (!LinkParser.containsLink(widget.text)) {
      return Text(widget.text, style: base, maxLines: widget.maxLines, overflow: widget.overflow);
    }
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final linkStyle = base.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );
    final spans = <InlineSpan>[];
    for (final token in LinkParser.tokenize(widget.text)) {
      if (token.isLink) {
        final r = TapGestureRecognizer()..onTap = () => _open(token.url!);
        _recognizers.add(r);
        spans.add(TextSpan(text: token.text, style: linkStyle, recognizer: r));
      } else {
        spans.add(TextSpan(text: token.text));
      }
    }
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}

/// Small helper so callers outside the widget tree can reuse the accent style.
TextStyle linkStyleFor(BuildContext context, TextStyle base) => base.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).appTokens.textMuted,
    );
