import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';

import '../channels/channel_providers.dart';
import 'search_providers.dart';

/// Estado de la búsqueda global (ui-spec §2.11, S5 · Ola 1). `sealed` para
/// que la UI haga `switch` exhaustivo — el analizador señala cualquier
/// estado nuevo que un `switch` olvide cubrir.
sealed class SearchState {
  const SearchState();
}

/// Sin consulta (campo vacío) — no se ha buscado nada todavía.
final class SearchIdle extends SearchState {
  const SearchIdle();
}

/// Debounce en marcha o búsqueda en vuelo para [query].
final class SearchLoading extends SearchState {
  const SearchLoading(this.query);
  final String query;
}

final class SearchResults extends SearchState {
  const SearchResults(this.query, this.results);
  final String query;
  final GroupedSearchResults results;
}

/// Motor de búsqueda global (ui-spec §2.11): debounce de 150 ms (valor
/// literal de la spec, no inventado) + descarte de resultados obsoletos
/// mediante un contador de generación — si el usuario sigue escribiendo,
/// una respuesta que llega tarde para una consulta ya superada no
/// sobrescribe la más reciente.
class SearchController extends Notifier<SearchState> {
  SearchController({this.debounce = const Duration(milliseconds: 150)});

  final Duration debounce;

  Timer? _debounceTimer;
  int _generation = 0;

  @override
  SearchState build() {
    ref.onDispose(() => _debounceTimer?.cancel());
    return const SearchIdle();
  }

  void queryChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _generation++; // invalida cualquier búsqueda en vuelo
      state = const SearchIdle();
      return;
    }

    state = SearchLoading(query);
    _debounceTimer = Timer(debounce, () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final generation = ++_generation;
    final sourceIds = ref.read(activeSourceIdsProvider);
    final results = await ref
        .read(searchChannelsProvider)
        .grouped(query, sourceIds: sourceIds);

    if (generation != _generation) return; // ya hay una consulta más nueva
    state = SearchResults(query, results);
  }
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);
