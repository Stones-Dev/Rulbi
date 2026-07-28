import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_pairing/iptv_pairing.dart';
import 'package:test/test.dart';

import 'fake_session_crypto.dart';

/// Reloj falso para tests deterministas (ver `Clock` en core): el TTL
/// del token nunca debe compararse contra `DateTime.now()` real.
final class _FakeClock implements Clock {
  _FakeClock(this._now);
  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration by) => _now = _now.add(by);
}

void main() {
  late FakeSessionCrypto crypto;
  late _FakeClock clock;

  setUp(() {
    crypto = FakeSessionCrypto();
    clock = _FakeClock(DateTime.utc(2026, 1, 1));
  });

  ReceiverSession newReceiver() => ReceiverSession(
    deviceName: 'LG Salón',
    host: '192.168.1.34',
    port: 40123,
    crypto: crypto,
    clock: clock,
  );

  group(
    'handshake y transferencia completos, sin red (streams en memoria)',
    () {
      test('con el token del QR', () async {
        final receiver = newReceiver();
        await receiver.startAdvertising();
        final (channelA, channelB) = createInMemoryChannelPair();

        final receiverFuture = receiver.pair(channelA);
        final sender = SenderSession(channel: channelB, crypto: crypto);
        await sender.pairWithToken(receiver.qrPayload.token);
        await sender.established;

        const channel = ChannelRef(sourceId: 's1', key: 'canal-1');
        await sender.sendConfig(
          ConfigPackage(
            favorites: [
              Favorite(channel: channel, updatedAt: DateTime.utc(2025, 1, 1)),
            ],
          ),
        );

        final received = await receiverFuture;
        expect(received.favorites.single.channel, channel);
      });

      test(
        'con el token del QR: el resultado se fusiona con LwwMerger (ADR-003)',
        () async {
          final receiver = newReceiver();
          await receiver.startAdvertising();
          final (channelA, channelB) = createInMemoryChannelPair();

          final receiverFuture = receiver.pair(channelA);
          final sender = SenderSession(channel: channelB, crypto: crypto);
          await sender.pairWithToken(receiver.qrPayload.token);
          await sender.established;

          const incomingChannel = ChannelRef(sourceId: 's1', key: 'canal-1');
          await sender.sendConfig(
            ConfigPackage(
              favorites: [
                Favorite(
                  channel: incomingChannel,
                  updatedAt: DateTime.utc(2025, 1, 1),
                ),
              ],
            ),
          );
          final received = await receiverFuture;

          const localOnlyChannel = ChannelRef(sourceId: 's1', key: 'canal-2');
          final localExisting = [
            Favorite(
              channel: localOnlyChannel,
              updatedAt: DateTime.utc(2025, 6, 1),
            ),
          ];
          final merger = LwwMerger<Favorite>(
            keyOf: (f) => f.channel,
            tiebreaker: (a, b) => a.order >= b.order,
          );

          final merged = merger.merge(localExisting, received.favorites);

          expect(merged.map((f) => f.channel).toSet(), {
            incomingChannel,
            localOnlyChannel,
          });
        },
      );

      test('con el código de 6 dígitos', () async {
        final receiver = newReceiver();
        await receiver.startAdvertising();
        final (channelA, channelB) = createInMemoryChannelPair();

        final receiverFuture = receiver.pair(channelA);
        final sender = SenderSession(channel: channelB, crypto: crypto);
        await sender.pairWithCode(receiver.code.value);
        await sender.established;
        await sender.sendConfig(const ConfigPackage());

        final received = await receiverFuture;
        expect(received.sources, isEmpty);
      });
    },
  );

  test(
    'código incorrecto: el emisor lo detecta y el receptor gasta un intento',
    () async {
      final receiver = newReceiver();
      await receiver.startAdvertising(codeOverride: SixDigitCode('654321'));
      final (channelA, channelB) = createInMemoryChannelPair();

      final receiverFuture = receiver.pair(channelA);
      final sender = SenderSession(channel: channelB, crypto: crypto);
      await sender.pairWithCode('000000'); // distinto del código real (654321)

      await expectLater(
        sender.established,
        throwsA(isA<PairingAuthFactorRejectedError>()),
      );
      await expectLater(
        receiverFuture,
        throwsA(isA<PairingAuthFactorRejectedError>()),
      );
    },
  );

  test('tras 3 intentos fallidos, la sesión del receptor se bloquea', () async {
    final receiver = newReceiver();
    await receiver.startAdvertising(codeOverride: SixDigitCode('654321'));

    for (var attempt = 1; attempt <= 3; attempt++) {
      final (channelA, channelB) = createInMemoryChannelPair();
      final receiverFuture = receiver.pair(channelA);
      final sender = SenderSession(channel: channelB, crypto: crypto);
      await sender.pairWithCode('000000');

      // El emisor siempre detecta el mismo problema desde su lado
      // (no puede abrir el challenge): "intentos agotados" es un
      // concepto exclusivo del receptor, que es quien cuenta.
      await expectLater(
        sender.established,
        throwsA(isA<PairingAuthFactorRejectedError>()),
      );

      if (attempt < 3) {
        await expectLater(
          receiverFuture,
          throwsA(isA<PairingAuthFactorRejectedError>()),
        );
      } else {
        await expectLater(
          receiverFuture,
          throwsA(isA<PairingAttemptsExceededError>()),
        );
      }
    }
  });

  test('token caducado: se rechaza antes de comparar el factor', () async {
    final receiver = newReceiver();
    await receiver.startAdvertising();
    clock.advance(const Duration(minutes: 3)); // TTL por defecto: 2 min

    final (channelA, channelB) = createInMemoryChannelPair();
    final receiverFuture = receiver.pair(channelA);
    final sender = SenderSession(channel: channelB, crypto: crypto);
    await sender.pairWithToken(receiver.qrPayload.token);

    await expectLater(receiverFuture, throwsA(isA<PairingTokenExpiredError>()));
  });

  test(
    'token reutilizado: una segunda conexión con el mismo token se rechaza',
    () async {
      final receiver = newReceiver();
      await receiver.startAdvertising();
      final token = receiver.qrPayload.token;

      final (firstChannelA, firstChannelB) = createInMemoryChannelPair();
      final firstReceiverFuture = receiver.pair(firstChannelA);
      final firstSender = SenderSession(channel: firstChannelB, crypto: crypto);
      await firstSender.pairWithToken(token);
      await firstSender.established;
      await firstSender.sendConfig(const ConfigPackage());
      await firstReceiverFuture;

      final (secondChannelA, secondChannelB) = createInMemoryChannelPair();
      final secondReceiverFuture = receiver.pair(secondChannelA);
      final secondSender = SenderSession(
        channel: secondChannelB,
        crypto: crypto,
      );
      await secondSender.pairWithToken(token);

      await expectLater(
        secondReceiverFuture,
        throwsA(isA<PairingTokenAlreadyUsedError>()),
      );
    },
  );
}
