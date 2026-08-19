/// Densidad tipográfica/espacial de un form factor.
///
/// La TV recibe un escalón completo más que Desktop en toda la escala de
/// tipografía (ui-spec.md §5.1) — coherente con la distancia de visión.
/// Deliberadamente no importa el `FormFactor` de `apps/app` aquí:
/// `packages/tokens` no depende de `apps/app` (regla de dependencias de la
/// constitution, packages/tokens es una capa compartida por los tres
/// shells). El widget que arma el tema es quien traduce su propio
/// `FormFactor` a este `IptvDensity`.
///
/// `mobile` añadido en S7 · Móvil base. **`ui-spec.md §5.1/§5.2` no define
/// todavía una columna Mobile** (hueco de spec detectado en S7, verificado
/// contra el vault, no asumido) — la escala usada aquí es una propuesta con
/// criterio explícito (un escalón por debajo de Desktop, ver
/// `iptv_typography.dart`/`iptv_spacing.dart`), documentada como enmienda
/// pendiente de validar en el handoff del proyecto, no una decisión de
/// diseño cerrada.
enum IptvDensity { desktop, tv, mobile }
