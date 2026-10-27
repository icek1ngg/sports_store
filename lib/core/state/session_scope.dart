/// Input from the Auth owner (CIN-01), never a source of authorization.
/// Unresolved roles deliberately have no access to private cached content.
class SessionScope {
  const SessionScope({
    required this.userId,
    required this.role,
    required this.generation,
    this.roleResolved = true,
  });

  const SessionScope.unresolved()
    : userId = null,
      role = null,
      generation = 0,
      roleResolved = false;

  final String? userId;
  final String? role;
  final int generation;
  final bool roleResolved;

  bool get canReadPrivateData =>
      userId != null &&
      roleResolved &&
      const {'customer', 'manager', 'shipper'}.contains(role);

  @override
  bool operator ==(Object other) =>
      other is SessionScope &&
      userId == other.userId &&
      role == other.role &&
      generation == other.generation &&
      roleResolved == other.roleResolved;

  @override
  int get hashCode => Object.hash(userId, role, generation, roleResolved);
}
