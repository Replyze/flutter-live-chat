// Prints the CHANGELOG.md section for a version: the release notes.
//
//   dart tool/changelog_notes.dart 0.1.0            the "## [0.1.0]" section
//   dart tool/changelog_notes.dart 0.1.0 --release  the same, and its heading must carry a date
//
// Exits with 1 when the section is missing or empty (or, with --release,
// still says "Unreleased" instead of "## [0.1.0] - 2026-11-20").
import 'dart:io';

void main(List<String> args) {
  final release = args.contains('--release');
  final version = args
      .firstWhere((a) => !a.startsWith('--'), orElse: () => '')
      .replaceFirst(RegExp('^v'), '');
  if (version.isEmpty) {
    stderr
        .writeln('Usage: dart tool/changelog_notes.dart <version> [--release]');
    exit(1);
  }

  const file = 'CHANGELOG.md';
  final lines = File(file).readAsLinesSync();
  final start = lines.indexWhere((line) => line.startsWith('## [$version]'));
  if (start == -1) {
    stderr.writeln(
        '$file has no "## [$version]" section. Add one before tagging v$version.');
    exit(1);
  }
  if (release &&
      !RegExp(r'^## \[[^\]]+\] - \d{4}-\d{2}-\d{2}\s*$')
          .hasMatch(lines[start])) {
    stderr.writeln(
        'The heading "${lines[start]}" needs the release date: "## [$version] - YYYY-MM-DD".');
    exit(1);
  }
  var end = lines.indexWhere((line) => line.startsWith('## '), start + 1);
  if (end == -1) end = lines.length;
  // Not the link references at the bottom ("[0.1.0]: https://...").
  final notes = lines
      .sublist(start + 1, end)
      .where((line) => !RegExp(r'^\[[^\]]+\]: ').hasMatch(line))
      .join('\n')
      .trim();
  if (notes.isEmpty) {
    stderr.writeln('The "## [$version]" section of $file is empty.');
    exit(1);
  }
  stdout.writeln(notes);
}
