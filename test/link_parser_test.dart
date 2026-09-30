import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/shared/link_parser.dart';

void main() {
  group('LinkParser.tokenize', () {
    test('https link in a sentence, trailing period excluded', () {
      final t = LinkParser.tokenize('See https://example.atlassian.net/browse/ABC-123 for details.');
      expect(t, [
        const LinkToken.plain('See '),
        const LinkToken.link('https://example.atlassian.net/browse/ABC-123', 'https://example.atlassian.net/browse/ABC-123'),
        const LinkToken.plain(' for details.'),
      ]);
    });

    test('bare www link gets https target', () {
      final t = LinkParser.tokenize('www.github.com/org/repo/pull/42');
      expect(t.single.isLink, isTrue);
      expect(t.single.text, 'www.github.com/org/repo/pull/42');
      expect(t.single.url, 'https://www.github.com/org/repo/pull/42');
    });

    test('no links yields one plain token', () {
      expect(LinkParser.tokenize('just words'), [const LinkToken.plain('just words')]);
      expect(LinkParser.tokenize(''), [const LinkToken.plain('')]);
      expect(LinkParser.containsLink('just words'), isFalse);
    });

    test('multiple links with plain text between', () {
      final t = LinkParser.tokenize('a https://one.test b http://two.test/x, c');
      expect(t.map((x) => x.text), ['a ', 'https://one.test', ' b ', 'http://two.test/x', ', c']);
      expect(t.where((x) => x.isLink).length, 2);
      expect(LinkParser.containsLink('a https://one.test'), isTrue);
    });

    test('trailing punctuation variants are trimmed', () {
      for (final p in ['.', ',', ';', ')', '!', '?', '"']) {
        final t = LinkParser.tokenize('(https://x.test/p$p');
        expect(t[1].url, 'https://x.test/p', reason: 'punct $p');
        expect(t[2].text, p);
      }
    });

    test('balanced parentheses inside a link are kept', () {
      final t = LinkParser.tokenize('https://en.wikipedia.org/wiki/Dart_(programming_language)');
      expect(t.single.url, 'https://en.wikipedia.org/wiki/Dart_(programming_language)');
    });

    test('link at end and at start', () {
      expect(LinkParser.tokenize('go https://a.test').last.isLink, isTrue);
      expect(LinkParser.tokenize('https://a.test go').first.isLink, isTrue);
    });

    test('token toString and equality', () {
      const l = LinkToken.link('a', 'b');
      expect(l.toString(), contains('->'));
      expect(const LinkToken.plain('x').toString(), 'Plain(x)');
      expect(l, const LinkToken.link('a', 'b'));
      expect(l.hashCode, const LinkToken.link('a', 'b').hashCode);
    });
  });
}
