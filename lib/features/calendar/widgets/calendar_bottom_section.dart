import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/booking_model.dart';
import '../../../utils/stayora_colors.dart';

/// Payload when dragging a booking from the waiting list (or grid) for drop on grid or section.
class WaitingListDragPayload {
  const WaitingListDragPayload({required this.bookingId});
  final String bookingId;
}

/// Waiting list (expandable downward) + Status legend. Matches calendar grid card style.
class CalendarBottomSection extends StatelessWidget {
  const CalendarBottomSection({
    super.key,
    required this.waitingListBookings,
    required this.onDropOnSection,
    required this.onClearSkeleton,
    required this.onShowDetails,
    required this.statusColor,
    required this.advanceIndicatorColor,
  });

  final List<({String id, BookingModel booking})> waitingListBookings;
  final Future<void> Function(String bookingId) onDropOnSection;
  final VoidCallback onClearSkeleton;
  final void Function(BuildContext context, String bookingId) onShowDetails;
  final Color Function(String status) statusColor;
  final Color Function(String advanceStatus) advanceIndicatorColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _WaitingListCard(
                waitingListBookings: waitingListBookings,
                onDropOnSection: onDropOnSection,
                onClearSkeleton: onClearSkeleton,
                onShowDetails: onShowDetails,
                statusColor: statusColor,
              ),
              _LegendCard(
                statusColor: statusColor,
                advanceIndicatorColor: advanceIndicatorColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaitingListCard extends StatefulWidget {
  const _WaitingListCard({
    required this.waitingListBookings,
    required this.onDropOnSection,
    required this.onClearSkeleton,
    required this.onShowDetails,
    required this.statusColor,
  });

  final List<({String id, BookingModel booking})> waitingListBookings;
  final Future<void> Function(String bookingId) onDropOnSection;
  final VoidCallback onClearSkeleton;
  final void Function(BuildContext context, String bookingId) onShowDetails;
  final Color Function(String status) statusColor;

  @override
  State<_WaitingListCard> createState() => _WaitingListCardState();
}

class _WaitingListCardState extends State<_WaitingListCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = List<({String id, BookingModel booking})>.from(
      widget.waitingListBookings,
    )..sort((a, b) => a.booking.checkIn.compareTo(b.booking.checkIn));
    return DragTarget<WaitingListDragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        widget.onDropOnSection(details.data.bookingId);
        widget.onClearSkeleton();
        if (!_expanded) setState(() => _expanded = true);
      },
      onLeave: (_) => widget.onClearSkeleton(),
      builder: (context, candidateData, _) {
        final isHighlighted = candidateData.isNotEmpty;
        const headerHeight = 48.0;
        return Container(
          decoration: BoxDecoration(
            color: isHighlighted
                ? StayoraColors.purple.withOpacity(0.15)
                : scheme.surfaceContainerHighest.withOpacity(0.6),
            border: Border(
              bottom: BorderSide(
                color: scheme.outline.withOpacity(0.15),
                width: 1,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header row (fixed height so list always opens below)
              SizedBox(
                height: headerHeight,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    borderRadius: BorderRadius.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.list_alt_rounded,
                            size: 20,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Waiting list',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurface,
                                ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${list.length}',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onSurface,
                                  ),
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 24,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // List: directly below header so it opens downward
              if (_expanded && list.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: list.map((e) {
                        final payload = WaitingListDragPayload(bookingId: e.id);
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: LongPressDraggable<WaitingListDragPayload>(
                            data: payload,
                            onDragStarted: () {},
                            onDragEnd: (_) => widget.onClearSkeleton(),
                            feedback: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              child: _CompactBookingChip(
                                booking: e.booking,
                                stripeColor: widget.statusColor(e.booking.status),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.5,
                              child: _CompactBookingChip(
                                booking: e.booking,
                                stripeColor: widget.statusColor(e.booking.status),
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => widget.onShowDetails(context, e.id),
                                borderRadius: BorderRadius.circular(8),
                                child: _CompactBookingChip(
                                  booking: e.booking,
                                  stripeColor: widget.statusColor(e.booking.status),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CompactBookingChip extends StatelessWidget {
  const _CompactBookingChip({
    required this.booking,
    required this.stripeColor,
  });

  final BookingModel booking;
  final Color stripeColor;

  static final _dateFormat = DateFormat('MMM d');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final checkInStr = _dateFormat.format(booking.checkIn);
    final checkOutStr = _dateFormat.format(booking.checkOut);
    final dateRange = '$checkInStr – $checkOutStr';
    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 4, color: stripeColor),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.userName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  dateRange,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (booking.selectedRooms != null && booking.selectedRooms!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Room${booking.selectedRooms!.length > 1 ? 's' : ''}: ${booking.selectedRooms!.join(', ')}',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Text(
                  '${booking.numberOfNights} night${booking.numberOfNights != 1 ? 's' : ''} • ${booking.status}',
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendCard extends StatelessWidget {
  const _LegendCard({
    required this.statusColor,
    required this.advanceIndicatorColor,
  });

  final Color Function(String status) statusColor;
  final Color Function(String advanceStatus) advanceIndicatorColor;

  static const List<String> _statusLabels = [
    'Confirmed',
    'Pending',
    'Paid',
    'Unpaid',
    'Cancelled',
    'Waiting list',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text(
                'Status Legend',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              ..._statusLabels.map(
                (status) => _LegendChip(
                  color: statusColor(status),
                  label: status,
                ),
              ),
              _LegendChip(
                color: advanceIndicatorColor('paid'),
                label: 'Advance paid',
              ),
              _LegendChip(
                color: advanceIndicatorColor('waiting'),
                label: 'Advance pending',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: scheme.outline.withOpacity(0.3),
              width: 1,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
