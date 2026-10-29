import '../models/delivery_reporting.dart';

/// Reads the minimal shipper reporting context and records P07.4 reports.
///
/// Implementations must return only after the server transaction commits,
/// retain [ReportingCommand.requestId] for an uncertain retry, and never
/// optimistically mutate a task or order state in memory.
abstract interface class DeliveryReportingRepository {
  Future<ReportingContext> getContext(String taskId);

  Future<ReportingAck> execute(ReportingCommand command);
}

/// Shorter contract alias used by feature-level dependency wiring.
typedef ReportingRepository = DeliveryReportingRepository;
