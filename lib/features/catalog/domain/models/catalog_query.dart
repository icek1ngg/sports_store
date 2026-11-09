enum CatalogSort { nameAscending, nameDescending, newest }

/// Search and page parameters for catalogue reads.
class CatalogQuery {
  const CatalogQuery({
    this.search = '',
    this.categoryId,
    this.page = 0,
    this.pageSize = 20,
    this.sort = CatalogSort.nameAscending,
    this.inStockOnly = false,
  });

  final String search;
  final String? categoryId;
  final int page;
  final int pageSize;
  final CatalogSort sort;
  final bool inStockOnly;

  CatalogQuery copyWith({
    String? search,
    Object? categoryId = _unset,
    int? page,
    int? pageSize,
    CatalogSort? sort,
    bool? inStockOnly,
  }) {
    return CatalogQuery(
      search: search ?? this.search,
      categoryId: identical(categoryId, _unset)
          ? this.categoryId
          : categoryId as String?,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      sort: sort ?? this.sort,
      inStockOnly: inStockOnly ?? this.inStockOnly,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CatalogQuery &&
        search == other.search &&
        categoryId == other.categoryId &&
        page == other.page &&
        pageSize == other.pageSize &&
        sort == other.sort &&
        inStockOnly == other.inStockOnly;
  }

  @override
  int get hashCode =>
      Object.hash(search, categoryId, page, pageSize, sort, inStockOnly);
}

const _unset = Object();
