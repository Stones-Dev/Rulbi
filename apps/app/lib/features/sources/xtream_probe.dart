import 'package:iptv_protocols/iptv_protocols.dart';

import 'probe_result.dart';

/// Resumen del "Probar conexión" del Formulario Xtream (ui-spec §2.9):
/// estado de cuenta, caducidad y nº de streams en directo, antes de
/// guardar la fuente.
final class XtreamProbeSummary {
  const XtreamProbeSummary({required this.account, this.liveStreamCount});

  final XtreamAccount account;

  /// Best-effort: `null` si `get_live_streams` falla tras una
  /// autenticación correcta — la cuenta sigue siendo válida, solo no se
  /// pudo contar. No degrada todo el probe a fallo por esto (la
  /// autenticación es lo que "Probar conexión" promete comprobar).
  final int? liveStreamCount;

  @override
  String toString() =>
      'XtreamProbeSummary(${account.status}, live: ${liveStreamCount ?? "?"})';
}

abstract interface class XtreamProbe {
  Future<ProbeResult<XtreamProbeSummary>> probe({
    required Uri host,
    required String username,
    required String password,
  });
}

/// Implementación real sobre `XtreamClient` (`packages/protocols`, T1.4):
/// reutiliza `authenticate()`/`liveStreams()` tal cual — este probe no
/// reimplementa nada del protocolo, solo compone y traduce fallos a
/// [ProbeFailureReason] (P6/P7).
final class XtreamClientProbe implements XtreamProbe {
  XtreamClientProbe({required this._transportFactory});

  final XtreamTransport Function() _transportFactory;

  @override
  Future<ProbeResult<XtreamProbeSummary>> probe({
    required Uri host,
    required String username,
    required String password,
  }) async {
    final client = XtreamClient(
      host: host,
      username: username,
      password: password,
      transport: _transportFactory(),
    );

    final authResult = await client.authenticate();
    if (authResult is XtreamErr<XtreamAccount>) {
      return ProbeFailed(_mapFailure(authResult.failure));
    }
    final account = (authResult as XtreamOk<XtreamAccount>).value;

    int? liveCount;
    final streamsResult = await client.liveStreams();
    if (streamsResult is XtreamOk<List<XtreamLiveStream>>) {
      liveCount = streamsResult.value.length;
    }

    return ProbeOk(
      XtreamProbeSummary(account: account, liveStreamCount: liveCount),
    );
  }

  ProbeFailureReason _mapFailure(XtreamFailure failure) => switch (failure) {
    XtreamAuthFailed() => ProbeFailureReason.authFailed,
    XtreamAccountExpired() => ProbeFailureReason.accountExpired,
    XtreamAccountDisabled() => ProbeFailureReason.accountDisabled,
    XtreamRateLimited() => ProbeFailureReason.rateLimited,
    XtreamHttpFailure() => ProbeFailureReason.network,
    XtreamMalformed() => ProbeFailureReason.malformed,
    XtreamNetworkFailure() => ProbeFailureReason.network,
  };
}
