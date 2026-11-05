import '../domain/models.dart';

/// Role-based access extension point.
///
/// The prototype has NO authentication: the role is just a setting, so this
/// policy only shapes the UI. Before real use, replace it with an
/// implementation backed by verified identity (e.g. OIDC tokens checked by the
/// backend) and enforce the same rules server-side.
abstract class AccessPolicy {
  bool canViewMissionControl(UserRole role);
  bool canViewOtherAstronauts(UserRole role);
}

class PrototypeAccessPolicy implements AccessPolicy {
  const PrototypeAccessPolicy();
  @override
  bool canViewMissionControl(UserRole role) => role != UserRole.astronaut;
  @override
  bool canViewOtherAstronauts(UserRole role) => role != UserRole.astronaut;
}
