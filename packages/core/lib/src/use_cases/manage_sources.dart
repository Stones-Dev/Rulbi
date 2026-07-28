import '../entities/channel.dart';
import '../entities/source.dart';

/// Añadir y refrescar una fuente (upsert diferencial que preserva
/// favoritos y progreso, plan §4.2).
///
/// **Sin implementar todavía** — deliberadamente. La firma toma un
/// `Stream<Channel>` porque quien lo produce es el parser de
/// `packages/protocols` (T1.2/T1.3/T1.4), bloqueado en T1.1 (golden
/// files reales del usuario). `core` no conoce el parser (P6): cuando
/// exista, la implementación concreta simplemente empieza a recorrer el
/// stream que le pasen, sin que este contrato cambie.
abstract interface class ManageSources {
  /// Crea la fuente y hace la primera importación completa a partir de
  /// [channels]. Devuelve el [Source] persistido (con `lastRefresh` ya
  /// actualizado).
  Future<Source> addSource(Source source, Stream<Channel> channels);

  /// Refresca una fuente existente: upsert diferencial que preserva
  /// favoritos y watch-state indexados por `ChannelRef` (ADR-003), no un
  /// borrado + reinserción completa.
  Future<void> refreshSource(String sourceId, Stream<Channel> channels);
}
