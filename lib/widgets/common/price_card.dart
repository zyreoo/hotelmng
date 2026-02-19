import 'package:flutter/material.dart';
import '../../models/booking_model.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/stayora_colors.dart';

/// Compact price breakdown card (room + services + total).
class PriceCard extends StatelessWidget {
  final BookingModel booking;
  final CurrencyFormatter currencyFormatter;

  const PriceCard({
    super.key,
    required this.booking,
    required this.currencyFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final hasRoom = (b.pricePerNight ?? 0) > 0;
    final hasServices =
        b.selectedServices != null && b.selectedServices!.isNotEmpty;
    final theme = Theme.of(context);

    final decoration = BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
    );

    if (!hasRoom && !hasServices) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: decoration,
        child: Text(
          'No price set',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasRoom)
            _row(
              context,
              '${b.numberOfNights} night${b.numberOfNights == 1 ? '' : 's'} × '
              '${b.numberOfRooms} room${b.numberOfRooms == 1 ? '' : 's'} × '
              '${currencyFormatter.formatCompact(b.pricePerNight!)}',
              currencyFormatter.formatCompact(b.roomSubtotal),
              isSub: true,
            ),
          if (hasServices) ...[
            if (hasRoom) const SizedBox(height: 8),
            ...b.selectedServices!.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _row(
                  context,
                  '${s.name} × ${s.quantity}',
                  currencyFormatter.formatCompact(s.lineTotal),
                  isSub: true,
                ),
              ),
            ),
            const SizedBox(height: 6),
            _row(context, 'Services',
                currencyFormatter.formatCompact(b.servicesSubtotal),
                isSub: true),
            const SizedBox(height: 8),
          ],
          const Divider(height: 1),
          const SizedBox(height: 8),
          _row(context, 'Total', currencyFormatter.format(b.calculatedTotal),
              isSub: false),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {required bool isSub}) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isSub ? 13 : 14,
              fontWeight: isSub ? FontWeight.w500 : FontWeight.w600,
              color: isSub
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            fontSize: isSub ? 13 : 15,
            fontWeight: isSub ? FontWeight.w500 : FontWeight.bold,
            color: isSub ? theme.colorScheme.onSurface : StayoraColors.blue,
          ),
        ),
      ],
    );
  }
}
