import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../domain/learning/content.dart';
import '../features/glossary/term_sheet.dart';

/// Lesson text with its `{{term}}` links (BRIEF §4.3): the term's title, or
/// the text a `{{term|text}}` link gives to fit its sentence, in bold and
/// underlined; a tap opens the term's sheet (or [onTerm]).
class TermText extends StatefulWidget {
  const TermText(
    this.text, {
    super.key,
    required this.terms,
    this.style,
    this.onTerm,
  });

  final String text;

  /// Term titles by id; an unknown id shows as written, without a link.
  final Map<String, Localized> terms;
  final TextStyle? style;

  /// What a tap on a link does; the term's sheet when null.
  final void Function(String termId)? onTerm;

  @override
  State<TermText> createState() => _TermTextState();
}

class _TermTextState extends State<TermText> {
  static final _link = RegExp(
    r'\{\{\s*([^{}|]*?)\s*(?:\|\s*([^{}]*?)\s*)?\}\}',
  );
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final language = Localizations.localeOf(context).languageCode;
    final spans = <InlineSpan>[];
    var at = 0;
    for (final match in _link.allMatches(widget.text)) {
      spans.add(TextSpan(text: widget.text.substring(at, match.start)));
      final id = match.group(1)!;
      final known = widget.terms.containsKey(id);
      final recognizer = known
          ? (TapGestureRecognizer()..onTap = () => (widget.onTerm ?? _open)(id))
          : null;
      if (recognizer != null) _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: match.group(2) ?? widget.terms[id]?.of(language) ?? id,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            decoration: known ? TextDecoration.underline : null,
            decorationColor: AppColors.ink,
          ),
          recognizer: recognizer,
        ),
      );
      at = match.end;
    }
    spans.add(TextSpan(text: widget.text.substring(at)));
    return Text.rich(
      TextSpan(children: spans),
      style: widget.style ?? Theme.of(context).textTheme.bodyLarge,
    );
  }

  void _open(String termId) => showTermSheet(context, termId);
}
