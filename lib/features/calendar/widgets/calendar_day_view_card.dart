import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/booking_model.dart';
import '../../../utils/stayora_colors.dart';

/// A booking summary card used in the calendar day-view dialog.
/// PMS-style: left accent stripe, clear typography hierarchy, status indicator.
class CalendarDayViewCard extends StatelessWidget {
  final BookingModel booking;
  final VoidCallback onTap;
  final Map<String, String> roomIdToName;

  const CalendarDayViewCard({
    super.key,
    required this.booking,
    required this.onTap,
    this.roomIdToName = const {},
  });

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'Confirmed':
        return StayoraColors.success;
      case 'Pending':
        return StayoraColors.warning;
      case 'Cancelled':
        return StayoraColors.error;
      case 'Paid':
        return StayoraColors.blue;
      case 'Unpaid':
        return StayoraColors.muted;
      case 'Waiting list':
        return StayoraColors.purple;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(context, booking.status);
    final stripeColor = statusColor;
    final cardBg = isDark
        ? scheme.surfaceContainerHighest
        : scheme.surfaceContainerLowest;
    final borderColor = scheme.outline.withValues(alpha:0.25);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha:isDark ? 0.15 : 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: IntrinsicHeight(
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left accent stripe (PMS standard)
                Container(
                  width: 5,
                  color: stripeColor,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Line 1 — Primary: guest name + status dot
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                booking.userName,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            // Status dot (subdued)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColor,
                                border: Border.all(
                                  color: cardBg,
                                  width: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Status chip (subdued)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha:0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                booking.status.toUpperCase(),
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Line 2 — Secondary: nights • dates
                        const SizedBox(height: 6),
                        Text(
                          '${booking.numberOfNights} night${booking.numberOfNights != 1 ? 's' : ''} • '
                          '${DateFormat('MMM d').format(booking.checkIn)} – ${DateFormat('MMM d').format(booking.checkOut)}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        // Optional line 3: phone + rooms
                        const SizedBox(height: 8),
                        _infoRow(context, Icons.phone_rounded, booking.userPhone),
                        Builder(
                          builder: (context) {
                            final rooms =
                                booking.resolvedSelectedRooms(roomIdToName);
                            if (rooms.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.bed_rounded,
                                    size: 14,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      rooms.join(', '),
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
