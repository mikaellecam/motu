import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/wallet/livret_line.dart';
import 'package:finance_companion/application/wallet/wallet_providers.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/remote/frankfurter_api.dart';
import 'package:finance_companion/data/repositories/fx_service.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/wallet/order.dart';
import 'package:finance_companion/domain/wallet/trip_engine.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';
import '../../fakes/fake_frankfurter.dart';

Decimal d(String s) => Decimal.parse(s);
Money eur(String s) => Money.book(d(s), Currency.eur);

void main() {
  late AppDatabase db;
  late ProviderContainer c;
  late WalletRepository wallets;
  const live = WalletRepository.liveWalletId;

  // The fake backend's Livret: 1,7 % since 1 August 2026, 22 950 € ceiling.
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final wall = WallClock(DateTime.utc(2026, 10, 8, 12));
    final backend = FakeBackend();
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveClockProvider.overrideWithValue(wall),
        marketRepositoryProvider.overrideWithValue(
          MarketRepository(
            db,
            BackendApi('http://t', adapter: backend),
            wallClock: wall,
          ),
        ),
        fxServiceProvider.overrideWithValue(
          FxService(
            db,
            FrankfurterApi(adapter: FakeFrankfurter()),
            wallClock: wall,
          ),
        ),
      ],
    );
    wallets = c.read(walletRepositoryProvider);
    await wallets.ensureLiveWallet(DateTime.utc(2026, 10, 5, 9));
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<LivretLine> line(String walletId) {
    c.listen(livretLineProvider(walletId), (_, _) {});
    return c.read(livretLineProvider(walletId).future);
  }

  LivretTransfer transfer(String walletId, {required bool deposit}) {
    c.listen(livretTransferProvider(walletId, deposit), (_, _) {});
    return c.read(livretTransferProvider(walletId, deposit).notifier);
  }

  List<String> codes(String walletId, {required bool deposit}) => [
    for (final e in c.read(livretTransferProvider(walletId, deposit)).errors)
      e.code,
  ];

  test(
    'an empty Livret: the rate and ceiling of the day, the cash free',
    () async {
      final l = await line(live);
      expect(l.day, DateTime.utc(2026, 10, 8));
      expect((l.balance, l.accrued), (eur('0'), Decimal.zero));
      expect((l.rate, l.ceiling), (d('0.017'), eur('22950')));
      expect(l.availableCash, eur('50000'));
    },
  );

  test('a deposit moves cash to the Livret, the total unchanged', () async {
    final t = transfer(live, deposit: true);
    t.setAmount('1 000', await line(live));
    expect(await t.submit(await line(live)), eur('1000'));
    final l = await line(live);
    expect(l.balance, eur('1000'));
    expect(l.availableCash, eur('49000'));
    final overview = await c.read(walletOverviewProvider(live).future);
    expect(overview.total, d('50000'));
  });

  test('a withdrawal brings it back', () async {
    await wallets.moveToLivret(live, DateTime.utc(2026, 10, 8), eur('1000'));
    final t = transfer(live, deposit: false);
    t.setAmount('400', await line(live));
    expect(await t.submit(await line(live)), eur('400'));
    expect((await line(live)).balance, eur('600'));
  });

  test(
    'the ceiling and the cash bound a deposit, the balance a withdrawal',
    () async {
      final l = await line(live);
      final dep = transfer(live, deposit: true)..setAmount('30000', l);
      expect(codes(live, deposit: true), ['livret_ceiling']);
      dep.setAmount('60000', l);
      expect(codes(live, deposit: true), [
        'insufficient_cash',
        'livret_ceiling',
      ]);
      expect(await dep.submit(l), isNull);
      expect((await line(live)).balance, eur('0'));

      transfer(live, deposit: false).setAmount('10', l);
      expect(codes(live, deposit: false), ['livret_insufficient_balance']);
    },
  );

  test('nothing typed: quiet until a try, then « above zero »', () async {
    final l = await line(live);
    final t = transfer(live, deposit: true)..setAmount('', l);
    expect(codes(live, deposit: true), isEmpty);
    expect(await t.submit(l), isNull);
    expect(codes(live, deposit: true), ['amount_not_positive']);
  });

  test('interest shows once a fortnight has closed', () async {
    // In on 1 September: earns from the 16th; 16–30 September closed on
    // 1 October; 1–15 October still open on the 8th.
    await wallets.moveToLivret(live, DateTime.utc(2026, 9, 1), eur('1000'));
    final l = await line(live);
    expect(l.accrued, ratio(d('1000') * d('0.017'), Decimal.fromInt(24)));
  });

  test('a trip books on its own day', () async {
    await wallets.createWallet(
      id: 'trip',
      kind: WalletKind.trip,
      name: 'Octobre',
      startDate: DateTime.utc(2026, 10, 5),
      startingCash: eur('10000'),
      params: WalletParams(
        rules: TradingRules(
          fxFeeRate: Decimal.zero,
          fixedFee: const Money.zero(Currency.eur),
          fractionalShares: true,
        ),
        monthlyContribution: const Money.zero(Currency.eur),
        stops: const StopConditions(),
      ),
      createdAt: DateTime.utc(2026, 10, 8),
    );
    final l = await line('trip');
    expect(l.day, DateTime.utc(2026, 10, 5));
    final t = transfer('trip', deposit: true)..setAmount('2500', l);
    await t.submit(l);
    final w = await wallets.load('trip');
    expect(w.livretMovements.single.date, DateTime.utc(2026, 10, 5));
    expect(w.livretMovements.single.amount, eur('2500'));
  });
}
