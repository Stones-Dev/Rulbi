/// Densidad tipográfica/espacial de un form factor.
///
/// La TV recibe un escalón completo más que Desktop en toda la escala de
/// tipografía (ui-spec.md §5.1) — coherente con la distancia de visión.
/// Deliberadamente no importa el `FormFactor` de `apps/app` aquí:
/// `packages/tokens` no depende de `apps/app` (regla de dependencias de la
/// constitution, packages/tokens es una capa compartida por los tres
/// shells). El widget que arma el tema es quien traduce su propio
/// `FormFactor` a este `IptvDensity`.
enum IptvDensity { desktop, tv }
