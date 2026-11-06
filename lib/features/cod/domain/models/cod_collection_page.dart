import 'cod_collection.dart';

final class CodCollectionCounts {
  const CodCollectionCounts({
    required this.all,
    required this.uncollected,
    required this.collected,
    required this.received,
  });

  final int all;
  final int uncollected;
  final int collected;
  final int received;

  int operator [](CodStatus status) => switch (status) {
    CodStatus.uncollected => uncollected,
    CodStatus.collected => collected,
    CodStatus.received => received,
  };
}

/// One authoritative snapshot returned by `list_cod_collections`.
final class CodCollectionPage {
  const CodCollectionPage({
    required this.items,
    required this.nextCursor,
    required this.filteredTotal,
    required this.counts,
    required this.outstandingVnd,
    required this.asOf,
  });

  final List<CodCollection> items;
  final String? nextCursor;
  final int filteredTotal;
  final CodCollectionCounts counts;
  final int outstandingVnd;
  final DateTime asOf;
}
