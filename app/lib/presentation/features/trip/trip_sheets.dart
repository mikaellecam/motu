import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/providers.dart';
import '../../../application/trip/trip_runner.dart';
import '../../../application/trip/trip_stop.dart';
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
            FilledButton(
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
              child: Text(l10n.stops_save),
            ),
          ],
        ),
      ),
    );
  }
}

/// « Avancer jusqu'à… » (BRIEF §4.5): a few spans, or a day.
Future<void> showForwardSheet(
  BuildContext context, {
  required String walletId,
  required DateTime from,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ForwardSheet(walletId: walletId, from: from),
);

class _ForwardSheet extends ConsumerStatefulWidget {
  const _ForwardSheet({required this.walletId, required this.from});
  final String walletId;
  final DateTime from;

  @override
  ConsumerState<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends ConsumerState<_ForwardSheet> {
  final _date = TextEditingController();

  @override
  void dispose() {
    _date.dispose();
    super.dispose();
  }

  void _pick(DateTime day) => setState(() {
    String two(int n) => n.toString().padLeft(2, '0');
    _date.text = '${two(day.day)}/${two(day.month)}/${day.year}';
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final text = Theme.of(context).textTheme;
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

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpace.screenPadding,
          0,
          AppSpace.screenPadding,
          AppSpace.screenPadding + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.trip_forward, style: AppText.title),
            const SizedBox(height: AppSpace.x3),
            Wrap(
              spacing: AppSpace.x2,
              children: [
                for (final (label, day) in [
                  (l10n.forward_months(3), months(3)),
                  (l10n.forward_months(6), months(6)),
                  (l10n.forward_year, months(12)),
                ])
                  ActionChip(label: Text(label), onPressed: () => _pick(day)),
              ],
            ),
            const SizedBox(height: AppSpace.x3),
            TextField(
              controller: _date,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                labelText: l10n.wizard_custom,
                hintText: l10n.wizard_custom_hint,
                errorText: error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpace.x2),
            Text(
              l10n.forward_may_stop,
              style: text.bodySmall?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpace.x4),
            ChunkyButton(
              label: switch (check) {
                ForwardOk(:final target) => l10n.forward_go(
                  formats.date(target),
                ),
                _ => l10n.trip_forward,
              },
              onPressed: switch (check) {
                ForwardOk(:final target) => () {
                  ref
                      .read(tripRunnerProvider(widget.walletId).notifier)
                      .advanceTo(target);
                  Navigator.of(context).pop();
                },
                _ => null,
              },
            ),
          ],
        ),
      ),
    );
  }
}
