/// A catalogue category visible to the current account.
class Category {
  const Category({required this.id, required this.code, required this.name});

  final String id;
  final String code;
  final String name;

  @override
  bool operator ==(Object other) {
    return other is Category &&
        id == other.id &&
        code == other.code &&
        name == other.name;
  }

  @override
  int get hashCode => Object.hash(id, code, name);
}
