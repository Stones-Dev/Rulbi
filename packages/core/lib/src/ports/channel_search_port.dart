import '../entities/channel.dart';

abstract interface class ChannelSearchPort {
  /// Busca por nombre, insensible a acentos/mayúsculas (RNF-01: resultado
  /// percibido < 100 ms sobre 100k canales). La implementación real
  /// (T1.5/`data`) vive sobre el índice FTS5.
  Future<List<Channel>> search(String query, {int limit = 50});
}
