/// Pure URL tokenizer used by the link-aware text widget. Kept free of Flutter
/// imports so it can be unit tested directly.
class LinkToken {
  final String text;
  /// The URL to open, or null for plain text. A bare `www.` host gets `https://`.
  final String? url;
  const LinkToken.plain(this.text) : url = null;
  const LinkToken.link(this.text, this.url);

  bool get isLink => url != null;

  @override
  bool operator ==(Object other) => other is LinkToken && other.text == text && other.url == url;

  @override
  int get hashCode => Object.hash(text, url);

  @override
  String toString() => isLink ? 'Link($text -> $url)' : 'Plain($text)';
}

class LinkParser {
  LinkParser._();

  static final RegExp _pattern = RegExp(r'(?:https?://|www\.)[^\s<>]+', caseSensitive: false);
  static const String _trailing = '.,;:!?)]}\'"';

  static List<LinkToken> tokenize(String input) {
    if (input.isEmpty) return const [LinkToken.plain('')];
    final tokens = <LinkToken>[];
    var cursor = 0;
    for (final m in _pattern.allMatches(input)) {
      var raw = m.group(0)!;
      var end = m.end;
      // Trim trailing punctuation that is almost never part of a pasted link.
      while (raw.isNotEmpty && _trailing.contains(raw[raw.length - 1])) {
        // Keep a closing paren if the link contains a matching opening one
        // (Wikipedia-style URLs).
        if (raw.endsWith(')') && '('.allMatches(raw).length > ')'.allMatches(raw).length - 1) break;
        raw = raw.substring(0, raw.length - 1);
        end--;
      }
      if (m.start > cursor) tokens.add(LinkToken.plain(input.substring(cursor, m.start)));
      final target = raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw;
      tokens.add(LinkToken.link(raw, target));
      cursor = end;
    }
    if (cursor < input.length) tokens.add(LinkToken.plain(input.substring(cursor)));
    if (tokens.isEmpty) tokens.add(LinkToken.plain(input));
    return tokens;
  }

  static bool containsLink(String input) => _pattern.hasMatch(input);
}
