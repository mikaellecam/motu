import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/learning/content.dart';
import '../../../application/learning/island_path.dart';
import '../../../application/order/order_ticket.dart';
import '../../../application/order/order_tracker.dart';
import '../../../application/wallet/living_island.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../map/archipelago.dart';
import '../map/living_island.dart';
import '../node/mission_player.dart';
import '../node/node_screen.dart';
import 'order_screen.dart';

/// After a buy (BRIEF §4.6, M9-34), on the sea as the art direction's
/// `OrderDone-A` draws it: the wallet's island with the order's building,
/// under construction while it waits or built, what happened and its steps,
/// the missions it completed, then « Retour à l'île » or the wallet.
class OrderDoneScreen extends ConsumerWidget {
  const OrderDoneScreen({
    super.key,
    required this.walletId,
    required this.done,
  });

  final String walletId;
  final OrderDone done;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final orderId = done.outcome.orderId;
    final state = ref.watch(orderTrackerProvider(orderId));
    // The wallet's own city, on the island the lessons greened.
    final buildings = drawnBuildings(
      ref.watch(walletIslandProvider(walletId)).value ?? const [],
    );
    final path = ref.watch(islandPathProvider(actionsEtfIsland)).value;

    return Scaffold(
      // World screens sit on the sea (BRIEF §10.2).
      backgroundColor: AppColors.sea,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screenPadding,
              0,
              AppSpace.screenPadding,
              AppSpace.screenPadding,
            ),
            children: [
              SizedBox(
                height: 240,
                child: CustomPaint(
                  painter: ArchipelagoPainter(
                    buildings: buildings,
                    only: archipelago.firstWhere(
                      (i) => i.id == IslandId.actionsEtf,
                    ),
                    grown: switch (path) {
                      final path? when path.nodes.isNotEmpty =>
                        path.done / path.nodes.length,
                      _ => 1,
                    },
                  ),
                ),
              ),
              switch (state) {
                AsyncValue(:final value?) => _OrderCard(done, value),
                AsyncValue(:final error?) => ChunkyCard(
                  child: ErrorView(
                    failure: error is Failure ? error : const ServerFailure(),
                    onRetry: () =>
                        ref.invalidate(orderTrackerProvider(orderId)),
                  ),
                ),
                _ => const ChunkyCard(child: AsyncSkeleton(lines: 6)),
              },
              for (final (i, n) in (path?.nodes ?? const <PathNode>[]).indexed)
                if (done.missions.contains(n.node.id)) ...[
                  const SizedBox(height: AppSpace.x4),
                  MissionCard(
                    done: true,
                    text: l10n.order_done_mission(n.node.title.of(language)),
                    detail: l10n.order_done_mission_step(i + 1),
                  ),
                ],
              const SizedBox(height: AppSpace.x6),
              Row(
                children: [
                  Expanded(
                    child: ChunkyButton(
                      label: l10n.order_done_island,
                      kind: ChunkyButtonKind.secondary,
                      compact: true,
                      onPressed: () => context.go('/'),
                    ),
                  ),
                  const SizedBox(width: AppSpace.x3),
                  Expanded(
                    child: ChunkyButton(
                      label: l10n.order_done_wallet,
                      compact: true,
                      onPressed: () => context.go('/wallet/$walletId'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the buy did: built or under construction, why it waits and when it
/// goes or at what price it filled, its steps, and « Voir l'ordre ».
class _OrderCard extends StatelessWidget {
  const _OrderCard(this.done, this.view);
  final OrderDone done;
  final OrderView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final name = view.asset.name;
    String day(DateTime t) => formats.date(t.toLocal());
    String time(DateTime t) => formats.time(t.toLocal());
    final line = switch (done.outcome) {
      OrderExecuted(:final fill) => l10n.order_done_filled_line(
        formats.price(fill.price),
      ),
      OrderSent(trip: true) => l10n.order_trip_next,
      OrderSent(:final opensAt?, offline: true) => l10n.order_offline_next(
        day(opensAt),
        time(opensAt),
      ),
      OrderSent(:final opensAt?) => l10n.order_market_closed(
        view.asset.exchange.name,
        day(opensAt),
        time(opensAt),
      ),
      OrderSent() => l10n.order_sent_waiting,
    };
    return LessonCard(
      label: done.built
          ? l10n.order_done_filled_label
          : l10n.order_done_pending_label,
      headline: done.built
          ? l10n.order_done_filled_title(name)
          : l10n.order_done_pending_title(name),
      children: [
        Text(line, style: Theme.of(context).textTheme.bodyLarge),
        Column(children: orderSteps(context, view, chunky: true)),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => context.push(
              '/wallet/${view.detail.walletId}/order/${view.detail.order.id}',
            ),
            child: Text(l10n.order_view),
          ),
        ),
      ],
    );
  }
}
