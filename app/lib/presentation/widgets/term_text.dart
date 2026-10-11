import 'package:flutter/material.dart';

import '../../domain/learning/content.dart';

/// Lesson text with its `{{term}}` links (BRIEF §4.3) in bold: the term's
/// title, or the text a `{{term|text}}` link gives to fit its sentence.
/// Opening the term's sheet on tap comes with the glossary (M6-6).
class TermText extends StatelessWidget {
  const TermText(this.text, {super.key, required this.terms, this.style});

  final String text;

  /// Term titles by id; an unknown id shows as written.
  final Map<String, Localized> terms;
  final TextStyle? style;

  static final _link = RegExp(
    r'\{\{\s*([^{}|]*?)\s*(?:\|\s*([^{}]*?)\s*)?\}\}',
  );

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final spans = <InlineSpan>[];
    var at = 0;
    for (final match in _link.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(at, match.start)));
      final id = match.group(1)!;
      spans.add(
        TextSpan(
          text: match.group(2) ?? terms[id]?.of(language) ?? id,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
      at = match.end;
    }
    spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(
      TextSpan(children: spans),
      style: style ?? Theme.of(context).textTheme.bodyLarge,
    );
  }
}
