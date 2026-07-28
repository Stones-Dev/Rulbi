import '../entities/channel.dart';
import '../ports/channel_search_port.dart';

/// HU-04: búsqueda instantánea. Envuelve el puerto para dejar en un solo
/// sitio la regla de negocio "una consulta vacía no busca nada" — sin
/// esto, cada shell tendría que recordar comprobarlo antes de llamar al
/// puerto.
final class SearchChannels {
  SearchChannels(this._port);

  final ChannelSearchPort _port;

  Future<List<Channel>> call(String query, {int limit = 50}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return Future.value(const []);
    return _port.search(trimmed, limit: limit);
  }
}
