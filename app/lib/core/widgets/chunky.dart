import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// "The game is talking to you" family (BRIEF §10.1): map, island path, node
/// player, wizard, companion cards, missions. White surface, thick ink border,
/// hard offset shadow, like a toy block.
class ChunkyCard extends StatelessWidget {
  const ChunkyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.x4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(
          Radius.circular(AppShape.chunkyCardRadius),
        ),
        border: Border.fromBorderSide(
          BorderSide(color: AppColors.ink, width: AppShape.chunkyBorder),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink,
            offset: Offset(0, AppShape.chunkyCardShadow),
          ),
        ],
      ),
      child: child,
    );
  }
}

enum ChunkyButtonKind {
  /// Primary action of a world screen.
  primary,

  /// Companion, mission and level actions.
  progress,
}

/// Toy-block button: pressing pushes it down onto its shadow.
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ChunkyButtonKind.primary,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final ChunkyButtonKind kind;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _pressed = false;

  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final (fill, text) = switch (widget.kind) {
      _ when !enabled => (AppColors.line, AppColors.muted),
      ChunkyButtonKind.primary => (AppColors.primary, AppColors.surface),
      ChunkyButtonKind.progress => (AppColors.progress, AppColors.ink),
    };
    final sink = _pressed || !enabled ? AppShape.chunkyButtonShadow : 0.0;

    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        // All null when disabled, so screen readers see no tap action.
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 52),
          margin: EdgeInsets.only(
            top: sink,
            bottom: AppShape.chunkyButtonShadow - sink,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.x6),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: const BorderRadius.all(
              Radius.circular(AppShape.chunkyButtonRadius),
            ),
            border: Border.all(
              color: AppColors.ink,
              width: AppShape.chunkyBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink,
                offset: Offset(0, AppShape.chunkyButtonShadow - sink),
              ),
            ],
          ),
          // Shrink-wraps the label, or fills the width when stretched.
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: text),
            ),
          ),
        ),
      ),
    );
  }
}

/// One answer among several, as a toy block: the onboarding questions, a
/// lesson's choices, an automatic stop's answers. A choice with a trade-off
/// shows what it gains (+) and what it risks (−) under its label.
class ChunkyChoice extends StatelessWidget {
  const ChunkyChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.upside,
    this.downside,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? upside;
  final String? downside;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ChunkyCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.x4,
              vertical: AppSpace.x3,
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: AppSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppText.bodyStrong),
                      for (final (icon, line) in [
                        (Icons.add, upside),
                        (Icons.remove, downside),
                      ])
                        if (line != null)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpace.x1),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ExcludeSemantics(
                                  child: Icon(
                                    icon,
                                    size: AppSpace.x4,
                                    color: AppColors.muted,
                                  ),
                                ),
                                const SizedBox(width: AppSpace.x2),
                                Expanded(
                                  child: Text(
                                    line,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
