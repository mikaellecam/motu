import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Rules from CLAUDE.md that a grep can enforce.
void main() {
  final sources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.contains('/core/l10n/app_localizations'));

  test('colors only come from core/theme tokens', () {
    final rawColor = RegExp(r'\bColor\(0x|\bColor\.from|\bColors\.');
    final offenders = [
      for (final file in sources)
        if (!file.path.startsWith('lib/core/theme/') &&
            rawColor.hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(offenders, isEmpty);
  });
}
