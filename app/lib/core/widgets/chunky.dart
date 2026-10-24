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
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Makes the card a button that presses down onto its shadow.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => onTap == null
      ? _block(0)
      : ChunkyPress(
          depth: AppShape.chunkyCardShadow,
          onTap: onTap,
          builder: _block,
        );

  Widget _block(double sink) => Transform.translate(
    offset: Offset(0, sink),
    child: Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.all(
          Radius.circular(AppShape.chunkyCardRadius),
        ),
        border: const Border.fromBorderSide(
          BorderSide(color: AppColors.ink, width: AppShape.chunkyBorder),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink,
            offset: Offset(0, AppShape.chunkyCardShadow - sink),
          ),
        ],
      ),
      child: child,
    ),
  );
}

/// Pushes a toy block down onto its shadow while it is pressed. The press
/// always plays in full: in a scroll view a tap shorter than 100 ms reports
/// its down and up in the same frame.
class ChunkyPress extends StatefulWidget {
  const ChunkyPress({
    super.key,
    required this.depth,
    required this.onTap,
    required this.builder,
  });

  /// The block's shadow height: how far it sinks.
  final double depth;

  /// Null disables the press.
  final VoidCallback? onTap;

  /// The block sunk by `sink`, from 0 at rest to [depth] pressed.
  final Widget Function(double sink) builder;

  @override
  State<ChunkyPress> createState() => _ChunkyPressState();
}

class _ChunkyPressState extends State<ChunkyPress>
    with SingleTickerProviderStateMixin {
  late final _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 80),
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  Future<void> _release() async {
    await _press.forward();
    if (mounted) _press.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // All null when disabled, so screen readers see no tap action.
      onTapDown: enabled ? (_) => _press.forward() : null,
      onTapUp: enabled ? (_) => _release() : null,
      onTapCancel: enabled ? _press.reverse : null,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, _) => widget.builder(
          Curves.easeOut.transform(_press.value) * widget.depth,
        ),
      ),
    );
  }
}

enum ChunkyButtonKind {
  /// Primary action of a world screen.
  primary,

  /// Companion, mission and level actions.
  progress,

  /// A second way on, beside or under the primary one.
  secondary,
}

/// Toy-block button: pressing pushes it down onto its shadow.
class ChunkyButton extends StatelessWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ChunkyButtonKind.primary,
    this.icon,
    this.compact = false,
  });

  final String label;

  /// Drawn before the label, in its colour (« + » on « Nouveau voyage dans
  /// le temps »).
  final IconData? icon;

  /// Three to a row: a smaller label with a narrow margin (a trip's time
  /// steps).
  final bool compact;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final ChunkyButtonKind kind;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final (fill, text) = switch (kind) {
      _ when !enabled => (AppColors.line, AppColors.muted),
      ChunkyButtonKind.primary => (AppColors.primary, AppColors.surface),
      ChunkyButtonKind.progress => (AppColors.progress, AppColors.ink),
      ChunkyButtonKind.secondary => (AppColors.surface, AppColors.ink),
    };
    final title = Text(
      label,
      textAlign: TextAlign.center,
      style:
          (compact
                  ? AppText.titleXSmall
                  : Theme.of(context).textTheme.titleLarge)
              ?.copyWith(color: text),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: ChunkyPress(
        depth: AppShape.chunkyButtonShadow,
        onTap: onPressed,
        builder: (pressed) {
          // A disabled button lies flat.
          final sink = enabled ? pressed : AppShape.chunkyButtonShadow;
          return Container(
            constraints: const BoxConstraints(minHeight: 52),
            margin: EdgeInsets.only(
              top: sink,
              bottom: AppShape.chunkyButtonShadow - sink,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpace.x1 : AppSpace.x6,
            ),
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
              child: icon == null
                  ? title
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: text),
                        const SizedBox(width: AppSpace.x2),
                        Flexible(child: title),
                      ],
                    ),
            ),
          );
        },
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
    this.mark,
    this.labelStyle,
  });

  final String label;

  /// Body strong by default; a Baloo title where the choice is the screen's
  /// moment (an automatic stop's answers).
  final TextStyle? labelStyle;
  final bool selected;
  final VoidCallback onTap;
  final String? upside;
  final String? downside;

  /// Once checked: ✓ on the right answer, ✗ on a wrong one chosen, with
  /// what screen readers say.
  final ({bool right, String label})? mark;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: ChunkyCard(
          onTap: onTap,
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
                    Text(label, style: labelStyle ?? AppText.bodyStrong),
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
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
              if (mark case final mark?) ...[
                const SizedBox(width: AppSpace.x2),
                Icon(
                  mark.right ? Icons.check_circle : Icons.cancel,
                  color: AppColors.ink,
                  semanticLabel: mark.label,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A square toy block with an icon, back or close on a world screen. Its
/// [label] is what screen readers say.
class ChunkyIconButton extends StatelessWidget {
  const ChunkyIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  static const size = 48.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Its own node: beside a title, it would merge into one « title,
      // close » button.
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: ChunkyPress(
        depth: AppShape.chunkyButtonShadow,
        onTap: onPressed,
        builder: (sink) => Transform.translate(
          offset: Offset(0, sink),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppShape.chunkyButtonRadius),
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
            child: Icon(icon, color: AppColors.ink),
          ),
        ),
      ),
    );
  }
}

/// A world screen's progress: one segment per step, the ones reached filled.
/// Screen readers hear the step in words beside it.
class StepBar extends StatelessWidget {
  const StepBar({super.key, required this.done, required this.of});

  final int done;
  final int of;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < of; i++) ...[
        if (i > 0) const SizedBox(width: AppSpace.x1),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: i < done ? AppColors.progress : AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpace.x2),
              border: Border.all(color: AppColors.ink, width: 2),
            ),
          ),
        ),
      ],
    ],
  );
}

/// What is missing or wrong, in an alert box on a world screen: a warning
/// icon, never colour alone. [action] (a link) goes under the text.
class AlertMessage extends StatelessWidget {
  const AlertMessage(this.text, {super.key, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(AppSpace.x3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppShape.flatCardRadius),
        border: Border.all(color: AppColors.alertText, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(
            child: Icon(
              Icons.warning_amber_rounded,
              color: AppColors.alertText,
            ),
          ),
          const SizedBox(width: AppSpace.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: AppText.label.copyWith(color: AppColors.alertText),
                ),
                ?action,
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
