import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/shared/design/components.dart';
import 'package:taskr/theme.dart';

Widget _wrap(Widget child) => MaterialApp(theme: lightTheme, home: Scaffold(body: child));

void main() {
  group('AppCard', () {
    testWidgets('renders its child and reacts to taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(AppCard(onTap: () => taps++, child: const Text('card'))));
      expect(find.text('card'), findsOneWidget);
      await tester.tap(find.text('card'));
      expect(taps, 1);
    });

    testWidgets('takes a custom color and radius', (tester) async {
      await tester.pumpWidget(_wrap(const AppCard(color: Colors.red, radius: 4, child: Text('card'))));
      final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, Colors.red);
      expect(decoration.borderRadius, BorderRadius.circular(4));
    });
  });

  group('SectionHeader', () {
    testWidgets('uppercases the title and shows the trailing widget', (tester) async {
      await tester.pumpWidget(_wrap(const SectionHeader('tags', trailing: Icon(Icons.add))));
      expect(find.text('TAGS'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('works without a trailing widget', (tester) async {
      await tester.pumpWidget(_wrap(const SectionHeader('tags')));
      expect(find.text('TAGS'), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    });
  });

  group('buttons', () {
    testWidgets('PrimaryButton expands by default and supports an icon', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_wrap(Column(children: [
        PrimaryButton('Go', onPressed: () => pressed++),
        PrimaryButton('With icon', icon: Icons.add, expand: false, onPressed: () => pressed++),
      ])));
      expect(find.byWidgetPredicate((w) => w is FilledButton), findsNWidgets(2));
      expect(find.byIcon(Icons.add), findsOneWidget);
      await tester.tap(find.text('Go'));
      await tester.tap(find.text('With icon'));
      expect(pressed, 2);
      final expanded = tester.getSize(find.byWidgetPredicate((w) => w is FilledButton).first);
      final compact = tester.getSize(find.byWidgetPredicate((w) => w is FilledButton).last);
      expect(expanded.width, greaterThan(compact.width));
    });

    testWidgets('SecondaryButton is outlined, compact by default and supports an icon', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_wrap(Column(children: [
        SecondaryButton('Quiet', onPressed: () => pressed++),
        SecondaryButton('Wide', icon: Icons.edit, expand: true, onPressed: () => pressed++),
      ])));
      expect(find.byWidgetPredicate((w) => w is OutlinedButton), findsNWidgets(2));
      expect(find.byIcon(Icons.edit), findsOneWidget);
      await tester.tap(find.text('Quiet'));
      await tester.tap(find.text('Wide'));
      expect(pressed, 2);
      final compact = tester.getSize(find.byWidgetPredicate((w) => w is OutlinedButton).first);
      final expanded = tester.getSize(find.byWidgetPredicate((w) => w is OutlinedButton).last);
      expect(expanded.width, greaterThan(compact.width));
    });
  });

  group('EmptyState', () {
    testWidgets('shows icon, title, message and action', (tester) async {
      await tester.pumpWidget(_wrap(const EmptyState(
        icon: Icons.inbox,
        title: 'Nothing here',
        message: 'Add something',
        action: Text('Action'),
      )));
      expect(find.byIcon(Icons.inbox), findsOneWidget);
      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('Add something'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
    });

    testWidgets('omits the optional parts', (tester) async {
      await tester.pumpWidget(_wrap(const EmptyState(icon: Icons.inbox, title: 'Nothing here')));
      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    });
  });

  group('AppBottomSheet', () {
    testWidgets('shows a grab handle, the title and the body', (tester) async {
      await tester.pumpWidget(_wrap(const AppBottomSheet(title: 'Sheet', child: Text('body'))));
      expect(find.text('Sheet'), findsOneWidget);
      expect(find.text('body'), findsOneWidget);
    });

    testWidgets('lifts above the keyboard and works without a title', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: lightTheme,
        home: const MediaQuery(
          data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: 100)),
          child: Material(child: Align(alignment: Alignment.bottomCenter, child: AppBottomSheet(child: Text('body')))),
        ),
      ));
      expect(find.text('body'), findsOneWidget);
      final padding = tester.widget<Padding>(find.ancestor(of: find.byType(DecoratedBox), matching: find.byType(Padding)).first);
      expect(padding.padding, const EdgeInsets.only(bottom: 100));
    });
  });
}
