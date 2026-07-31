import 'dart:io';
import 'package:yaml/yaml.dart';

void main() async {
  // Get commit hash
  final commitResult = await Process.run('git', ['rev-parse', '--short', 'HEAD']);
  final commitHash = commitResult.stdout.toString().trim();

  // Get version from pubspec.yaml
  final pubspecFile = File('pubspec.yaml');
  final pubspecContent = await pubspecFile.readAsString();
  final pubspec = loadYaml(pubspecContent);
  final version = pubspec['version'];

  // Read about.dart
  final aboutFile = File('lib/about/about.dart');
  String aboutFileContent = await aboutFile.readAsString();

  // Replace version
  aboutFileContent = aboutFileContent.replaceFirst(
    RegExp(r"static const appVersion = '.*';"),
    "static const appVersion = '$version';",
  );

  // Replace commit hash
  aboutFileContent = aboutFileContent.replaceFirst(
    RegExp(r"static const appCommit = '.*';"),
    "static const appCommit = '$commitHash';",
  );

  // Write back to about.dart
  await aboutFile.writeAsString(aboutFileContent);

  stdout.writeln('Successfully updated lib/about/about.dart with version: $version and commit: $commitHash');
}
