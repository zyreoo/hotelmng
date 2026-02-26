import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/booking_model.dart';
import '../../../utils/currency_formatter.dart';
import '../../../utils/money_input_formatter.dart';
import '../../../utils/stayora_colors.dart';
import '../../../widgets/common/price_card.dart';
import '../../../widgets/common/section_card.dart';

/// Inline booking details panel shown in the calendar side-sheet.
/// Owns the editable status/payment/notes fields and the save/delete/close
/// actions. Does NOT talk to Firestore directly — all mutations go through
/// the [onSave] / [onDelete] callbacks.
class BookingDetailsForm extends StatefulWidget {
  final BookingModel fullBooking;
  final String room;
  final DateTime date;
  final String bookingId;
  final List<String> statusOptions;
  final Color Function(String) getStatusColor;
  final List<String> paymentMethods;
  final CurrencyFormatter currencyFormatter;
  final Widget Function(IconData, String, String) buildDetailRow;
  final Widget Function(String) buildStatusRowWithStatus;
  final Future<void> Function(BookingModel) onSave;
  final Future<void> Function() onDelete;
  final VoidCallback onEditFull;
  final VoidCallback onClose;

  /// Room id→name map so the form always shows friendly names.
  final Map<String, String> roomIdToName;

  const BookingDetailsForm({
    super.key,
    required this.fullBooking,
    required this.room,
    required this.date,
    required this.bookingId,
    required this.statusOptions,
    required this.getStatusColor,
    required this.paymentMethods,
    required this.currencyFormatter,
    required this.buildDetailRow,
    required this.buildStatusRowWithStatus,
    required this.onSave,
    required this.onDelete,
    required this.onEditFull,
    required this.onClose,
    this.roomIdToName = const {},
  });

  @override
  State<BookingDetailsForm> createState() => _BookingDetailsFormState();
}

class _BookingDetailsFormState extends State<BookingDetailsForm> {
  late String _status;
  late TextEditingController _amountController;
  late TextEditingController _advanceAmountController;
  late String _paymentMethod;
  late String _advancePaymentMethod;
  late String _advanceStatus; // not_required, pending, received
  late TextEditingController _notesController;

  late String _initialStatus;
  late int _initialAmount;
  late int _initialAdvanceAmount;
  late String _initialPaymentMethod;
  late String _initialAdvancePaymentMethod;
  late String _initialAdvanceStatus;
  late String _initialNotes;

  @override
  void initState() {
    super.initState();
    _syncFromBooking(widget.fullBooking);
  }

  void _syncFromBooking(BookingModel b) {
    _status = widget.statusOptions.contains(b.status)
        ? b.status
        : widget.statusOptions.first;
    _amountController = TextEditingController(
      text: CurrencyFormatter.formatStoredAmountForInput(b.amountOfMoneyPaid),
    );
    _advanceAmountController = TextEditingController(
      text: CurrencyFormatter.formatStoredAmountForInput(b.advanceAmountPaid),
    );
    _paymentMethod = widget.paymentMethods.contains(b.paymentMethod)
        ? b.paymentMethod
        : widget.paymentMethods.first;
    _advancePaymentMethod =
        (b.advancePaymentMethod != null && b.advancePaymentMethod!.isNotEmpty)
        ? b.advancePaymentMethod!
        : widget.paymentMethods.first;
    _advanceStatus =
        (b.advanceStatus != null &&
            BookingModel.advanceStatusOptions.contains(b.advanceStatus))
        ? b.advanceStatus!
        : (b.advancePercent != null && b.advancePercent! > 0
              ? (b.advanceAmountPaid >= b.advanceAmountRequired
                    ? 'received'
                    : 'pending')
              : 'not_required');
    _notesController = TextEditingController(text: b.notes ?? '');

    _initialStatus = _status;
    _initialAmount = b.amountOfMoneyPaid;
    _initialAdvanceAmount = b.advanceAmountPaid;
    _initialPaymentMethod = _paymentMethod;
    _initialAdvancePaymentMethod = _advancePaymentMethod;
    _initialAdvanceStatus = _advanceStatus;
    _initialNotes = b.notes ?? '';
  }

  bool get _hasChanges {
    final currentAmount = CurrencyFormatter.parseMoneyStringToCents(
      _amountController.text.trim(),
    );
    final currentAdvance = CurrencyFormatter.parseMoneyStringToCents(
      _advanceAmountController.text.trim(),
    );
    final currentNotes = _notesController.text.trim();
    return _status != _initialStatus ||
        currentAmount != _initialAmount ||
        currentAdvance != _initialAdvanceAmount ||
        _paymentMethod != _initialPaymentMethod ||
        _advancePaymentMethod != _initialAdvancePaymentMethod ||
        _advanceStatus != _initialAdvanceStatus ||
        currentNotes != _initialNotes;
  }

  Future<void> _handleClose() async {
    if (!_hasChanges) {
      widget.onClose();
      return;
    }
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.shadow.withValues(alpha:0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Unsaved Changes',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'You have unsaved changes. Do you want to save before closing?',
                  style: TextStyle(
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _actionButton(
                      context,
                      label: 'Save and Close',
                      color: StayoraColors.success,
                      textColor: Colors.white,
                      onTap: () => Navigator.pop(context, 'save'),
                    ),
                    const SizedBox(height: 10),
                    _actionButton(
                      context,
                      label: 'Discard Changes',
                      color: Theme.of(context).colorScheme.surface,
                      textColor: StayoraColors.error,
                      bordered: true,
                      onTap: () => Navigator.pop(context, 'discard'),
                    ),
                    const SizedBox(height: 10),
                    _actionButton(
                      context,
                      label: 'Cancel',
                      color: Colors.transparent,
                      textColor: StayoraColors.blue,
                      onTap: () => Navigator.pop(context, 'cancel'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (result) {
      case 'save':
        final amount = CurrencyFormatter.parseMoneyStringToCents(
          _amountController.text.trim(),
        );
        final advanceAmount = CurrencyFormatter.parseMoneyStringToCents(
          _advanceAmountController.text.trim(),
        );
        final updated = widget.fullBooking.copyWith(
          status: _status,
          amountOfMoneyPaid: amount,
          paymentMethod: _paymentMethod,
          advanceAmountPaid: advanceAmount,
          advancePaymentMethod: _advancePaymentMethod,
          advanceStatus: _advanceStatus,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          checkedInAt: widget.fullBooking.checkedInAt,
          checkedOutAt: widget.fullBooking.checkedOutAt,
        );
        await widget.onSave(updated);
        if (!mounted) return;
        widget.onClose();
      case 'discard':
        widget.onClose();
      default:
        break;
    }
  }

  Widget _actionButton(
    BuildContext context, {
    required String label,
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
    bool bordered = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: bordered
                  ? Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha:0.5),
                    )
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant BookingDetailsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullBooking.id != widget.fullBooking.id ||
        oldWidget.fullBooking.status != widget.fullBooking.status ||
        oldWidget.fullBooking.amountOfMoneyPaid !=
            widget.fullBooking.amountOfMoneyPaid ||
        oldWidget.fullBooking.paymentMethod !=
            widget.fullBooking.paymentMethod ||
        oldWidget.fullBooking.advanceAmountPaid !=
            widget.fullBooking.advanceAmountPaid ||
        oldWidget.fullBooking.advancePaymentMethod !=
            widget.fullBooking.advancePaymentMethod ||
        oldWidget.fullBooking.advanceStatus !=
            widget.fullBooking.advanceStatus ||
        oldWidget.fullBooking.notes != widget.fullBooking.notes) {
      _amountController.dispose();
      _advanceAmountController.dispose();
      _notesController.dispose();
      _syncFromBooking(widget.fullBooking);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _advanceAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.fullBooking;
    final totalNights = b.numberOfNights;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          Text(
            'Booking Details',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 17,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                widget.buildDetailRow(
                  Icons.person_rounded,
                  'Guest',
                  b.userName,
                ),
                const SizedBox(height: 12),
                widget.buildDetailRow(
                  Icons.phone_rounded,
                  'Phone',
                  b.userPhone.isNotEmpty ? b.userPhone : '—',
                ),
                const SizedBox(height: 12),
                widget.buildDetailRow(
                  Icons.hotel_rounded,
                  () {
                    final resolved = b.resolvedSelectedRooms(
                      widget.roomIdToName,
                    );
                    return resolved.length > 1 ? 'Rooms' : 'Room';
                  }(),
                  () {
                    final resolved = b.resolvedSelectedRooms(
                      widget.roomIdToName,
                    );
                    return resolved.isNotEmpty
                        ? resolved.join(', ')
                        : widget.room;
                  }(),
                ),
                const SizedBox(height: 12),
                widget.buildDetailRow(
                  Icons.calendar_today_rounded,
                  'Date',
                  DateFormat('MMM d, yyyy').format(widget.date),
                ),
                const SizedBox(height: 12),
                widget.buildDetailRow(
                  Icons.nightlight_round,
                  'Duration',
                  '$totalNights ${totalNights == 1 ? 'night' : 'nights'}',
                ),
                const SizedBox(height: 16),
                Text(
                  'Check-in / Check-out',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _checkInButton(context, b)),
                    const SizedBox(width: 8),
                    Expanded(child: _checkOutButton(context, b)),
                  ],
                ),
                const SizedBox(height: 16),
                PriceCard(
                  booking: b,
                  currencyFormatter: widget.currencyFormatter,
                ),
                const SizedBox(height: 16),
                ..._advanceSection(context, b),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Payment & notes',
                  child: _paymentNotesFields(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _saveButton(context, b),
                const SizedBox(height: 12),
                _editFullButton(context),
                const SizedBox(height: 12),
                _deleteButton(context),
                const SizedBox(height: 12),
                _closeButton(context),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _checkInButton(BuildContext context, BookingModel b) {
    if (b.checkedInAt == null) {
      return OutlinedButton.icon(
        onPressed: () async {
          await widget.onSave(b.copyWith(checkedInAt: DateTime.now()));
        },
        icon: const Icon(Icons.login_rounded, size: 16),
        label: const Text('Check In'),
        style: OutlinedButton.styleFrom(
          foregroundColor: StayoraColors.teal,
          side: const BorderSide(color: StayoraColors.teal),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      );
    }
    return _timestampBadge(
      context,
      icon: Icons.check_circle_rounded,
      color: StayoraColors.teal,
      text: 'In: ${DateFormat('MMM d, HH:mm').format(b.checkedInAt!)}',
    );
  }

  Widget _checkOutButton(BuildContext context, BookingModel b) {
    if (b.checkedOutAt == null) {
      return OutlinedButton.icon(
        onPressed: b.checkedInAt == null
            ? null
            : () async {
                await widget.onSave(b.copyWith(checkedOutAt: DateTime.now()));
              },
        icon: const Icon(Icons.logout_rounded, size: 16),
        label: const Text('Check Out'),
        style: OutlinedButton.styleFrom(
          foregroundColor: StayoraColors.warning,
          side: BorderSide(
            color: b.checkedInAt == null
                ? Theme.of(context).colorScheme.outline.withValues(alpha:0.4)
                : StayoraColors.warning,
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      );
    }
    return _timestampBadge(
      context,
      icon: Icons.check_circle_rounded,
      color: StayoraColors.warning,
      text: 'Out: ${DateFormat('MMM d, HH:mm').format(b.checkedOutAt!)}',
    );
  }

  Widget _timestampBadge(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha:0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _advanceSection(BuildContext context, BookingModel b) {
    final cf = widget.currencyFormatter;
    return [
      SectionCard(
        title: 'Advance payment',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (b.advancePercent != null && b.advancePercent! > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${b.advancePercent}% of total — required ${cf.format(b.advanceAmountRequired)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            TextFormField(
              controller: _advanceAmountController,
              inputFormatters: [MoneyInputFormatter()],
              decoration: _fieldDecoration(
                context,
                'Advance paid',
                '0.00',
                icon: widget.currencyFormatter.currencyIcon,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: widget.paymentMethods.contains(_advancePaymentMethod)
                  ? _advancePaymentMethod
                  : widget.paymentMethods.first,
              decoration: _fieldDecoration(
                context,
                'Advance payment method',
                null,
              ),
              items: widget.paymentMethods
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) {
                setState(
                  () => _advancePaymentMethod = v ?? widget.paymentMethods.first,
                );
                _persistFormFields(widget.fullBooking);
              },
            ),
            const SizedBox(height: 10),
            Text(
              'Advance status',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('Not required'),
                  selected: _advanceStatus == 'not_required',
                  onSelected: (_) {
                    setState(() => _advanceStatus = 'not_required');
                    _persistFormFields(widget.fullBooking);
                  },
                  selectedColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha:0.8),
                ),
                ChoiceChip(
                  label: const Text('Pending'),
                  selected: _advanceStatus == 'pending',
                  onSelected: (_) {
                    setState(() => _advanceStatus = 'pending');
                    _persistFormFields(widget.fullBooking);
                  },
                  selectedColor: StayoraColors.warning.withValues(alpha:0.3),
                ),
                ChoiceChip(
                  label: const Text('Received'),
                  selected: _advanceStatus == 'received',
                  onSelected: (_) {
                    setState(() => _advanceStatus = 'received');
                    _persistFormFields(widget.fullBooking);
                  },
                  selectedColor: StayoraColors.success.withValues(alpha:0.3),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final advancePaid = CurrencyFormatter.parseMoneyStringToCents(
                  _advanceAmountController.text.trim(),
                );
                final remaining = (b.calculatedTotal - advancePaid).clamp(
                  0,
                  b.calculatedTotal,
                );
                return Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Remaining: ${cf.format(remaining)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: remaining > 0
                              ? StayoraColors.warning
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _paymentNotesFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: _fieldDecoration(context, 'Status', null),
          items: widget.statusOptions
              .map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(
                    s,
                    style: TextStyle(
                      color: widget.getStatusColor(s),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            setState(() => _status = v ?? _status);
            _persistFormFields(widget.fullBooking);
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _amountController,
          inputFormatters: [MoneyInputFormatter()],
          decoration: _fieldDecoration(
            context,
            'Amount paid',
            '0.00',
            icon: widget.currencyFormatter.currencyIcon,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: widget.paymentMethods.contains(_paymentMethod)
              ? _paymentMethod
              : widget.paymentMethods.first,
          decoration: _fieldDecoration(context, 'Payment method', null),
          items: widget.paymentMethods
              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
              .toList(),
          onChanged: (v) {
            setState(() => _paymentMethod = v ?? widget.paymentMethods.first);
            _persistFormFields(widget.fullBooking);
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notesController,
          decoration: InputDecoration(
            labelText: 'Notes',
            hintText: 'Optional notes…',
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          maxLines: 2,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(
    BuildContext context,
    String label,
    String? hint, {
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      prefixIcon: icon != null ? Icon(icon, size: 18) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  /// Save button: applies only money/notes fields so users must confirm
  /// amount changes explicitly. Status and advance controls save instantly.
  Widget _saveButton(BuildContext context, BookingModel b) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () async {
          final amount = CurrencyFormatter.parseMoneyStringToCents(
            _amountController.text.trim(),
          );
          final advanceAmount = CurrencyFormatter.parseMoneyStringToCents(
            _advanceAmountController.text.trim(),
          );
          final updated = b.copyWith(
            amountOfMoneyPaid: amount,
            advanceAmountPaid: advanceAmount,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
          await widget.onSave(updated);
        },
        icon: const Icon(Icons.save_rounded, size: 18),
        label: const Text('Save amounts'),
        style: FilledButton.styleFrom(
          backgroundColor: StayoraColors.success,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  /// Persists current form state (status, payment, advance, notes) to the backend.
  void _persistFormFields(BookingModel b) {
    final amount = CurrencyFormatter.parseMoneyStringToCents(
      _amountController.text.trim(),
    );
    final advanceAmount = CurrencyFormatter.parseMoneyStringToCents(
      _advanceAmountController.text.trim(),
    );
    final updated = b.copyWith(
      status: _status,
      amountOfMoneyPaid: amount,
      paymentMethod: _paymentMethod,
      advanceAmountPaid: advanceAmount,
      advancePaymentMethod: _advancePaymentMethod,
      advanceStatus: _advanceStatus,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      checkedInAt: b.checkedInAt,
      checkedOutAt: b.checkedOutAt,
    );
    widget.onSave(updated);
  }

  Widget _editFullButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: widget.onEditFull,
        style: FilledButton.styleFrom(
          backgroundColor: StayoraColors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: const Text(
          'Edit full booking (dates, rooms, guest)',
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _deleteButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () async => widget.onDelete(),
        icon: const Icon(Icons.delete_outline_rounded, size: 18),
        label: const Text('Delete Booking'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _closeButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _handleClose,
        style: FilledButton.styleFrom(
          backgroundColor: scheme.inverseSurface,
          foregroundColor: scheme.onInverseSurface,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: const Text('Close'),
      ),
    );
  }
}
