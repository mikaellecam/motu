import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/providers.dart';
import '../../../application/trip/trip_runner.dart';
import '../../../application/trip/trip_stop.dart';
import '../../../application/learning/content.dart';
import '../../../application/wallet/wallet_providers.dart';
import '../../widgets/term_text.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/wallet/trip_engine.dart';
import '../../../domain/wallet/trip_setup.dart';
import '../../../domain/wallet/trip_start.dart';

/// Changes a trip's automatic stops: the wizard's switches (BRIEF §4.5).
Future<void> showStopsSheet(
  BuildContext context, {
  required String walletId,
  required StopConditions current,
  required Money contribution,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _StopsSheet(
    walletId: walletId,
    current: current,
    contribution: contribution,
  ),
);

class _StopsSheet extends ConsumerStatefulWidget {
  const _StopsSheet({
    required this.walletId,
    required this.current,
    required this.contribution,
  });

  final String walletId;
  final StopConditions current;
  final Money contribution;

  @override
  ConsumerState<_StopsSheet> createState() => _StopsSheetState();
}

class _StopsSheetState extends ConsumerState<_StopsSheet> {
  late var _portfolio = widget.current.drawdown != null;
  late var _position = widget.current.positionLoss != null;
  late var _order = widget.current.orderFilled;
  late var _contribution = widget.current.contribution;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    Widget switchTile(String label, bool value, ValueChanged<bool> set) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value,
          onChanged: (on) => setState(() => set(on)),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screenPadding,
          0,
          AppSpace.screenPadding,
          AppSpace.screenPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.wizard_stops, style: AppText.title),
            Text(
              l10n.wizard_stops_hint,
              style: text.bodySmall?.copyWith(color: AppColors.muted),
            ),
            switchTile(
              l10n.wizard_stop_portfolio,
              _portfolio,
              (on) => _portfolio = on,
            ),
            switchTile(
              l10n.wizard_stop_position,
              _position,
              (on) => _position = on,
            ),
            switchTile(l10n.wizard_stop_order, _order, (on) => _order = on),
            if (widget.contribution.isPositive)
              switchTile(
                l10n.wizard_stop_contribution,
                _contribution,
                (on) => _contribution = on,
              ),
            const SizedBox(height: AppSpace.x4),
            ChunkyButton(
              label: l10n.stops_save,
              onPressed: () async {
                await ref
                    .read(stopActionsProvider(widget.walletId).notifier)
                    .updateStops(
                      stopsFrom(
                        portfolio: _portfolio,
                        position: _position,
                        orderFilled: _order,
                        contribution: _contribution,
                      ),
                    );
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// « Avancer jusqu'à… » (BRIEF §4.5, artboard `TripFF-A`): a span or a day,
/// and the trip's automatic stops, changed before time moves.
Future<void> showForwardSheet(
  BuildContext context, {
  required String walletId,
  required DateTime from,
  required StopConditions stops,
  required Money contribution,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ForwardSheet(
    walletId: walletId,
    from: from,
    stops: stops,
    contribution: contribution,
  ),
);

class _ForwardSheet extends ConsumerStatefulWidget {
  const _ForwardSheet({
    required this.walletId,
    required this.from,
    required this.stops,
    required this.contribution,
  });
  final String walletId;
  final DateTime from;
  final StopConditions stops;
  final Money contribution;

  @override
  ConsumerState<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends ConsumerState<_ForwardSheet> {
  final _date = TextEditingController();
  final _dateFocus = FocusNode();
  DateTime? _preset;
  var _custom = false;
  late final List<bool> _initial;
  late final List<bool> _stops;

  @override
  void initState() {
    super.initState();
    _initial = [
      widget.stops.drawdown != null,
      widget.stops.positionLoss != null,
      widget.stops.orderFilled,
      widget.stops.contribution,
    ];
    _stops = [..._initial];
  }

  @override
  void dispose() {
    _date.dispose();
    _dateFocus.dispose();
    super.dispose();
  }

  void _pick(DateTime day) => setState(() {
    String two(int n) => n.toString().padLeft(2, '0');
    _date.text = '${two(day.day)}/${two(day.month)}/${day.year}';
    _preset = day;
    _custom = false;
  });

  Future<void> _go(DateTime target) async {
    final navigator = Navigator.of(context);
    // The trip's own stops, as its settings change them (decided 2026-10-25).
    if (!listEquals(_stops, _initial)) {
      await ref
          .read(stopActionsProvider(widget.walletId).notifier)
          .updateStops(
            stopsFrom(
              portfolio: _stops[0],
              position: _stops[1],
              orderFilled: _stops[2],
              contribution: _stops[3],
            ),
          );
    }
    ref.read(tripRunnerProvider(widget.walletId).notifier).advanceTo(target);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final from = widget.from;
    final today = ref.watch(liveClockProvider).now();
    final typed = _date.text.trim();
    final check = typed.isEmpty
        ? null
        : checkForward(parseDay(typed), from: from, today: today);
    DateTime months(int n) {
      final last = DateTime.utc(from.year, from.month + n + 1, 0).day;
      return DateTime.utc(
        from.year,
        from.month + n,
        from.day <= last ? from.day : last,
      );
    }

    final error = switch (check) {
      ForwardUnreadable() => l10n.wizard_date_unreadable,
      ForwardNotAfter(:final from) => l10n.forward_not_after(
        formats.date(from),
      ),
      ForwardTooLate(:final latest) => l10n.forward_too_late(
        formats.date(latest),
      ),
      _ => null,
    };
    final idle = switch (check) {
      ForwardOk(:final target) => contributionOnTheWay(
        ref.watch(idleContributionProvider(widget.walletId)).value,
        target: target,
      ),
      _ => null,
    };
    final terms =
        ref
            .watch(glossaryTermsProvider)
            .value
            ?.map((id, t) => MapEntry(id, t.title)) ??
        const {};
    final section = AppText.label.copyWith(color: AppColors.ink);
    final muted = AppText.caption.copyWith(color: AppColors.muted);

    Widget stop(String label, int i) => CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label),
      value: _stops[i],
      onChanged: (on) => setState(() => _stops[i] = on ?? false),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpace.screenPadding,
          0,
          AppSpace.screenPadding,
          AppSpace.screenPadding + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.trip_forward, style: AppText.title)),
                ChunkyIconButton(
                  icon: Icons.close,
                  label: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Text(l10n.forward_intro, style: muted),
            const SizedBox(height: AppSpace.x4),
            Text(l10n.forward_span, style: section),
            const SizedBox(height: AppSpace.x2),
            Wrap(
              spacing: AppSpace.x2,
              runSpacing: AppSpace.x2,
              children: [
                for (final (label, day) in [
                  (l10n.forward_months(1), months(1)),
                  (l10n.forward_months(3), months(3)),
                  (l10n.forward_year, months(12)),
                ])
                  ChunkyChip(
                    label: label,
                    selected: !_custom && _preset == day,
                    onTap: () => _pick(day),
                  ),
                ChunkyChip(
                  label: l10n.wizard_custom,
                  selected: _custom,
                  onTap: () {
                    setState(() => _custom = true);
                    _dateFocus.requestFocus();
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpace.x4),
            Text(l10n.forward_until, style: section),
            const SizedBox(height: AppSpace.x2),
            TextField(
              controller: _date,
              focusNode: _dateFocus,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                hintText: l10n.wizard_custom_hint,
                errorText: error,
                filled: true,
                fillColor: AppColors.surface,
                suffixIcon: const ExcludeSemantics(
                  child: Icon(Icons.calendar_today_outlined),
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _custom = true),
            ),
            const SizedBox(height: AppSpace.x4),
            Text(l10n.forward_stops, style: section),
            const SizedBox(height: AppSpace.x2),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3),
                child: Column(
                  children: [
                    stop(l10n.forward_stop_portfolio, 0),
                    stop(l10n.forward_stop_position, 1),
                    stop(l10n.forward_stop_order, 2),
                    if (widget.contribution.isPositive)
                      stop(l10n.wizard_stop_contribution, 3),
                  ],
                ),
              ),
            ),
            if (idle != null) ...[
              const SizedBox(height: AppSpace.x3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExcludeSemantics(
                    child: Icon(
                      Icons.calendar_today_outlined,
                      size: 18,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(width: AppSpace.x2),
                  Expanded(
                    child: TermText(
                      l10n.forward_idle_contribution(
                        formats.dayMonth(idle),
                        '{{dca|DCA}}',
                      ),
                      terms: terms,
                      style: muted,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpace.x4),
            ChunkyButton(
              label: switch (check) {
                ForwardOk(:final target) => l10n.forward_go(
                  formats.date(target),
                ),
                _ => l10n.trip_forward,
              },
              onPressed: switch (check) {
                ForwardOk(:final target) => () => _go(target),
                _ => null,
              },
            ),
          ],
        ),
      ),
    );
  }
}
