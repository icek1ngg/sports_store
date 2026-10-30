/// Search and page parameters for catalogue reads.
class CatalogQuery {
  const CatalogQuery({
    this.search = '',
    this.categoryId,
    this.page = 0,
    this.pageSize = 20,
  });

  final String search;
  final String? categoryId;
  final int page;
  final int pageSize;

  CatalogQuery copyWith({
    String? search,
    Object? categoryId = _unset,
    int? page,
    int? pageSize,
  }) {
    return CatalogQuery(
      search: search ?? this.search,
      categoryId: identical(categoryId, _unset)
          ? this.categoryId
          : categoryId as String?,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CatalogQuery &&
        search == other.search &&
        categoryId == other.categoryId &&
        page == other.page &&
        pageSize == other.pageSize;
  }

  @override
  int get hashCode => Object.hash(search, categoryId, page, pageSize);
}

const _unset = Object();
