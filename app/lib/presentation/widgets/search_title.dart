import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/chunky.dart';

/// A title bar's search, folded into its magnifier at the right of the
/// [title] (M13-16, decided 2026-11-17; the glossary, and Explore since
/// M13-23): touched, the box slides open leftward across the bar, focused;
/// its ✕ clears the search ([onChanged] with '') and folds it back. A
/// [query] still typed keeps it open. At once with reduced motion. The
/// folded magnifier is named [hint] for screen readers.
class SearchTitle extends StatefulWidget {
  const SearchTitle({
    super.key,
    required this.title,
    required this.hint,
    required this.query,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final String query;
  final ValueChanged<String> onChanged;

  @override
  State<SearchTitle> createState() => _SearchTitleState();
}

class _SearchTitleState extends State<SearchTitle> {
  // Its text comes from the search, so it survives the tab being left.
  late final _text = TextEditingController(text: widget.query);
  final _focus = FocusNode();
  late bool _open = widget.query.isNotEmpty;

  /// The folded box: the magnifier inside the block's border.
  static const _folded = 48 + 2 * AppShape.chunkyBorder;
  static const _height = AppSpace.minTarget + 2 * AppShape.chunkyBorder;
  static const _unfold = Duration(milliseconds: 280);

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _unfoldIt() {
    setState(() => _open = true);
    _focus.requestFocus();
  }

  void _foldIt() {
    _text.clear();
    widget.onChanged('');
    _focus.unfocus();
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _unfold;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The bar's width: the toolbar keeps the screen's margin at its end.
        final full = constraints.maxWidth;
        return SizedBox(
          width: constraints.maxWidth,
          height: _height + AppShape.chunkyButtonShadow,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              AnimatedOpacity(
                opacity: _open ? 0 : 1,
                duration: duration,
                child: ExcludeSemantics(
                  excluding: _open,
                  child: Text(widget.title),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  width: _open ? full : _folded,
                  height: _height,
                  decoration: ChunkySearchField.box,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      AppShape.chunkyButtonRadius - AppShape.chunkyBorder,
                    ),
                    child: _open
                        ? OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: full - 2 * AppShape.chunkyBorder,
                            maxWidth: full - 2 * AppShape.chunkyBorder,
                            child: ChunkySearchField(
                              controller: _text,
                              focusNode: _focus,
                              hint: widget.hint,
                              onChanged: widget.onChanged,
                              onClear: _foldIt,
                              boxed: false,
                            ),
                          )
                        : Semantics(
                            container: true,
                            button: true,
                            label: widget.hint,
                            excludeSemantics: true,
                            child: InkWell(
                              onTap: _unfoldIt,
                              child: const Center(
                                child: Icon(Icons.search, color: AppColors.ink),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
