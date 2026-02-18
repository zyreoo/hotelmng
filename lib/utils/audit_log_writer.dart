/// Abstraction for writing audit log entries.
///
/// Implementations may write to Firestore, local file, or test doubles.
/// No UI; framework-agnostic.

import 'audit_log_models.dart';

/// Writes one audit log entry. Implementations must not throw from [write]
/// in production; the logger layer swallows errors.
abstract class AuditLogWriter {
  Future<void> write(AuditLogData data);
}
