import 'package:flutter_test/flutter_test.dart';
import 'package:hotelmng/utils/audit_log_models.dart';
import 'package:hotelmng/utils/audit_log_writer.dart';
import 'package:hotelmng/utils/audit_logger.dart';

/// Writer that throws on every write. Used to ensure logBookingAction never throws.
class ThrowingAuditLogWriter implements AuditLogWriter {
  @override
  Future<void> write(AuditLogData data) async {
    throw Exception('Intentional failure for test');
  }
}

void main() {
  group('logBookingAction', () {
    test('does NOT throw when writer throws', () async {
      final writer = ThrowingAuditLogWriter();
      final data = AuditLogData(
        action: AuditAction.bookingCreated,
        bookingId: 'b1',
        roomId: '101',
        userId: 'u1',
      );
      await expectLater(
        logBookingAction(AuditAction.bookingCreated, data, writer),
        completes,
      );
    });

    test('does NOT throw when writer throws synchronously', () async {
      final writer = _SyncThrowingWriter();
      final data = AuditLogData(
        action: AuditAction.bookingCreated,
        bookingId: 'b1',
        roomId: '101',
        userId: 'u1',
      );
      await expectLater(
        logBookingAction(AuditAction.bookingCreated, data, writer),
        completes,
      );
    });
  });
}

class _SyncThrowingWriter implements AuditLogWriter {
  @override
  Future<void> write(AuditLogData data) {
    throw StateError('sync throw');
  }
}
