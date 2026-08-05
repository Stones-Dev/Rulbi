import 'package:iptv_protocols/src/xtream/xtream_host.dart';
import 'package:test/test.dart';

/// S4 · Ola 2 (Formulario Xtream, ADR-006): normaliza la "URL del
/// servidor" tal como la teclea el usuario (ui-spec §2.9) a la forma que
/// espera `XtreamClient.host`/`XtreamSourceConfig.host` — sin
/// `player_api.php`, sin query/fragment, sin barra final. Rechaza
/// credenciales embebidas: su sitio son los campos Usuario/Contraseña del
/// formulario + el almacén seguro (P5), no la URL del panel.
void main() {
  group('normalizeXtreamPanelHost — casos válidos', () {
    test('sin esquema: añade http://', () {
      final result = normalizeXtreamPanelHost('host:8080') as XtreamHostOk;
      expect(result.host.toString(), 'http://host:8080');
    });

    test('http:// explícito, sin puerto ni barra final: se conserva tal cual', () {
      final result = normalizeXtreamPanelHost('http://host') as XtreamHostOk;
      expect(result.host.toString(), 'http://host');
    });

    test('https:// con barra final: la barra se elimina', () {
      final result = normalizeXtreamPanelHost('https://host/') as XtreamHostOk;
      expect(result.host.toString(), 'https://host');
    });

    test('con player_api.php: se elimina el sufijo', () {
      final result =
          normalizeXtreamPanelHost('http://host:8080/player_api.php')
              as XtreamHostOk;
      expect(result.host.toString(), 'http://host:8080');
    });

    test('con player_api.php en mayúsculas: se elimina igual (case-insensitive)', () {
      final result =
          normalizeXtreamPanelHost('http://host/Player_Api.php') as XtreamHostOk;
      expect(result.host.toString(), 'http://host');
    });

    test('con query/fragment: se descartan', () {
      final result =
          normalizeXtreamPanelHost('http://host/player_api.php?username=a&password=b')
              as XtreamHostOk;
      expect(result.host.toString(), 'http://host');
    });

    test('IPv6 entre corchetes: se conserva', () {
      final result = normalizeXtreamPanelHost('[::1]:8080') as XtreamHostOk;
      expect(result.host.toString(), 'http://[::1]:8080');
    });

    test('path base no vacío (proxy tras /xtream/): se conserva sin barra final', () {
      final result = normalizeXtreamPanelHost('http://host/xtream/') as XtreamHostOk;
      expect(result.host.toString(), 'http://host/xtream');
    });

    test('path base + player_api.php: se conserva el base, se elimina el sufijo', () {
      final result =
          normalizeXtreamPanelHost('http://host/xtream/player_api.php') as XtreamHostOk;
      expect(result.host.toString(), 'http://host/xtream');
    });
  });

  group('normalizeXtreamPanelHost — casos inválidos', () {
    test('cadena vacía: motivo empty', () {
      final result = normalizeXtreamPanelHost('') as XtreamHostInvalid;
      expect(result.reason, XtreamHostInvalidReason.empty);
    });

    test('solo espacios en blanco: motivo empty', () {
      final result = normalizeXtreamPanelHost('   ') as XtreamHostInvalid;
      expect(result.reason, XtreamHostInvalidReason.empty);
    });

    test('esquema sin host: motivo malformed', () {
      final result = normalizeXtreamPanelHost('http://') as XtreamHostInvalid;
      expect(result.reason, XtreamHostInvalidReason.malformed);
    });

    test('esquema no http(s): motivo malformed', () {
      final result = normalizeXtreamPanelHost('ftp://host') as XtreamHostInvalid;
      expect(result.reason, XtreamHostInvalidReason.malformed);
    });

    test('credenciales embebidas sin esquema: motivo embeddedCredentials', () {
      final result = normalizeXtreamPanelHost('user:pass@host') as XtreamHostInvalid;
      expect(result.reason, XtreamHostInvalidReason.embeddedCredentials);
    });

    test('credenciales embebidas con esquema: motivo embeddedCredentials', () {
      final result =
          normalizeXtreamPanelHost('http://user:pass@host:8080') as XtreamHostInvalid;
      expect(result.reason, XtreamHostInvalidReason.embeddedCredentials);
    });
  });
}
