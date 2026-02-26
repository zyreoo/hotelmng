import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/booking_model.dart';
import '../models/service_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../services/auth_provider.dart';
import '../utils/currency_formatter.dart';
import '../utils/money_input_formatter.dart';
import '../utils/stayora_colors.dart';
import '../widgets/app_notification.dart';
import '../widgets/stayora_logo.dart';

class ServicesPage extends StatelessWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final horizontalPadding =
        MediaQuery.of(context).size.width >= 768 ? 24.0 : 16.0;
    final colorScheme = Theme.of(context).colorScheme;
    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    final firebaseService = FirebaseService();

    if (hotelId == null || userId == null) {
      return Scaffold(
        body: Center(
          child: Text(
            'No hotel selected',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(horizontalPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (Navigator.canPop(context))
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_rounded),
                            onPressed: () => Navigator.pop(context),
                            color: StayoraColors.blue,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        if (Navigator.canPop(context)) const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Services',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 34,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Add-on offerings (breakfast, spa, sauna, etc.)',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  8,
                  horizontalPadding,
                  16,
                ),
                child: StreamBuilder<List<ServiceModel>>(
                  stream: firebaseService.getServicesStream(userId, hotelId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final services = snapshot.data ?? [];
                    if (services.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.room_service_outlined,
                                  size: 48,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No services yet',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap + Add service to create your first one',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        ...services.map(
                          (service) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ServiceCard(
                              service: service,
                              currencyFormatter: CurrencyFormatter.fromHotel(
                                  HotelProvider.of(context).currentHotel),
                              onEdit: () => _showServiceDialog(
                                context,
                                userId,
                                hotelId,
                                firebaseService,
                                existing: service,
                              ),
                              onDelete: () => _confirmDelete(
                                context,
                                userId,
                                hotelId,
                                firebaseService,
                                service,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _ServiceUsageSection(
                          userId: userId,
                          hotelId: hotelId,
                          firebaseService: firebaseService,
                          services: services,
                        ),
                        const SizedBox(height: 24),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'services_fab',
        onPressed: () =>
            _showServiceDialog(context, userId, hotelId, firebaseService),
        backgroundColor: StayoraLogo.stayoraBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add service',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  static Future<void> _showServiceDialog(
    BuildContext context,
    String userId,
    String hotelId,
    FirebaseService firebaseService, {
    ServiceModel? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final priceController = TextEditingController(
      text: existing != null && existing.price > 0
          ? CurrencyFormatter.formatStoredAmountForInput(existing.price)
          : '',
    );
    final categoryController =
        TextEditingController(text: existing?.category ?? '');
    final descriptionController =
        TextEditingController(text: existing?.description ?? '');

    final colorScheme = Theme.of(context).colorScheme;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha:Theme.of(context).brightness == Brightness.dark ? 0.4 : 0.1),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurfaceVariant.withValues(alpha:0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      existing == null ? 'Add service' : 'Edit service',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: nameController,
                          decoration: InputDecoration(
                            labelText: 'Name',
                            hintText: 'e.g. Breakfast, Spa, Sauna',
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colorScheme.outline.withValues(alpha:0.5),
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: priceController,
                          decoration: InputDecoration(
                            labelText: 'Price',
                            hintText: 'e.g. 20.00 or 20,50',
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colorScheme.outline.withValues(alpha:0.5),
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            MoneyInputFormatter(),
                          ],
                          onEditingComplete: () {
                            final cents = CurrencyFormatter.parseMoneyStringToCents(
                                priceController.text.trim());
                            if (cents > 0) {
                              priceController.text =
                                  CurrencyFormatter.formatCentsForInput(cents);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: categoryController,
                          decoration: InputDecoration(
                            labelText: 'Category (optional)',
                            hintText: 'e.g. meal, wellness',
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colorScheme.outline.withValues(alpha:0.5),
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: descriptionController,
                          decoration: InputDecoration(
                            labelText: 'Description (optional)',
                            hintText: 'Short description',
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colorScheme.outline.withValues(alpha:0.5),
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: StayoraColors.blue,
                              fontWeight: FontWeight.w500,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final name = nameController.text.trim();
                              final price = CurrencyFormatter.parseMoneyStringToCents(
                                  priceController.text.trim());
                              if (name.isEmpty) {
                                showAppNotification(context, 'Name is required');
                                return;
                              }
                              if (price < 0) {
                                showAppNotification(context, 'Price must be 0 or more');
                                return;
                              }
                              final category = categoryController.text.trim();
                              final description = descriptionController.text.trim();
                              final service = ServiceModel(
                                id: existing?.id,
                                name: name,
                                price: price,
                                category: category.isEmpty ? null : category,
                                description: description.isEmpty ? null : description,
                              );
                              try {
                                if (existing != null) {
                                  await firebaseService.updateService(userId, hotelId, service);
                                } else {
                                  await firebaseService.addService(userId, hotelId, service);
                                }
                                if (context.mounted) Navigator.pop(context, true);
                              } catch (e) {
                                if (context.mounted) {
                                  showAppNotification(context, 'Error: $e', type: AppNotificationType.error);
                                }
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: StayoraLogo.stayoraBlue,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              existing == null ? 'Add' : 'Save',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 17,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (result == true && context.mounted) {
      showAppNotification(
        context,
        existing == null ? 'Service added' : 'Service updated',
        type: AppNotificationType.success,
      );
    }
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    String userId,
    String hotelId,
    FirebaseService firebaseService,
    ServiceModel service,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete service?'),
        content: Text(
          'Remove "${service.name}"? This will not remove it from existing bookings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true && service.id != null) {
      try {
        await firebaseService.deleteService(userId, hotelId, service.id!);
        if (context.mounted) {
          showAppNotification(context, 'Service deleted', type: AppNotificationType.success);
        }
      } catch (e) {
        if (context.mounted) {
          showAppNotification(context, 'Error: $e', type: AppNotificationType.error);
        }
      }
    }
  }
}

/// Section showing which bookings and rooms have each service.
class _ServiceUsageSection extends StatelessWidget {
  final String userId;
  final String hotelId;
  final FirebaseService firebaseService;
  final List<ServiceModel> services;

  const _ServiceUsageSection({
    required this.userId,
    required this.hotelId,
    required this.firebaseService,
    required this.services,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        firebaseService.getBookings(userId, hotelId),
        firebaseService.getRooms(userId, hotelId),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: StayoraColors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Loading bookings & rooms…',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null || data.length < 2) {
          return const SizedBox.shrink();
        }
        final bookings = (data[0] as List).cast<BookingModel>();
        final rooms = (data[1] as List);
        final roomIdToName = <String, String>{
          for (final r in rooms)
            if ((r as dynamic).id != null)
              (r as dynamic).id as String: (r as dynamic).name as String,
        };

        final activeBookings = bookings
            .where((b) =>
                b.status != 'Cancelled' &&
                b.selectedServices != null &&
                b.selectedServices!.isNotEmpty)
            .toList();

        if (activeBookings.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Where services are used',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No bookings with add-on services yet.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final dateFormat = DateFormat('MMM d');

        // Map serviceId -> ServiceModel for quick lookup.
        final serviceById = <String, ServiceModel>{
          for (final s in services)
            if (s.id != null) s.id!: s,
        };

        // Today section: rooms that have services today.
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        bool overlapsToday(BookingModel b) {
          final ci = DateTime(b.checkIn.year, b.checkIn.month, b.checkIn.day);
          final co = DateTime(b.checkOut.year, b.checkOut.month, b.checkOut.day);
          return !ci.isAfter(today) && co.isAfter(today);
        }

        final todayBookings =
            activeBookings.where((b) => overlapsToday(b)).toList();
        final Map<String, Set<String>> todayRoomsToServices = {};
        for (final b in todayBookings) {
          final roomNames = b.resolvedSelectedRooms(roomIdToName);
          final selected = b.selectedServices ?? const <BookingServiceItem>[];
          for (final item in selected) {
            final svc = serviceById[item.serviceId];
            if (svc == null) continue;
            for (final room in roomNames) {
              todayRoomsToServices
                  .putIfAbsent(room, () => <String>{})
                  .add(svc.name);
            }
          }
        }
        final todayRoomsSorted = todayRoomsToServices.keys.toList()..sort();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.assignment_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Where services are used',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Rooms and bookings that have each service.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (todayRoomsSorted.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        Icons.today_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Today – rooms with services',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: todayRoomsSorted.map((room) {
                      final svcs =
                          (todayRoomsToServices[room] ?? const <String>{})
                              .toList()
                            ..sort();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '$room: ${svcs.join(', ')}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ] else
                  const SizedBox(height: 20),
                ...services.map((service) {
                  final serviceBookings = activeBookings.where((b) {
                    final sel = b.selectedServices;
                    if (sel == null) return false;
                    return sel.any((s) => s.serviceId == service.id);
                  }).toList();

                  if (serviceBookings.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final roomNames = <String>{};
                  for (final b in serviceBookings) {
                    roomNames.addAll(b.resolvedSelectedRooms(roomIdToName));
                  }
                  final roomsList = roomNames.toList()..sort();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            service.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.meeting_room_outlined,
                                size: 16,
                                color: StayoraColors.blue,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      'Rooms: ',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                    ...roomsList.map(
                                      (r) => Chip(
                                        label: Text(
                                          r,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor:
                                            StayoraColors.blue.withValues(
                                          alpha: 0.12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.person_outline_rounded,
                                size: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      'Bookings: ',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                    ...serviceBookings.map(
                                      (b) => Text(
                                        '${b.userName} (${dateFormat.format(b.checkIn)} – ${dateFormat.format(b.checkOut)})',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final ServiceModel service;
  final CurrencyFormatter currencyFormatter;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServiceCard({
    required this.service,
    required this.currencyFormatter,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: StayoraColors.blue.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.room_service_rounded,
                color: StayoraColors.blue,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (service.category != null &&
                      service.category!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      service.category!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Price: ${currencyFormatter.formatCompact(service.price)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: StayoraColors.blue,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
              color: StayoraColors.blue,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: onDelete,
              color: Theme.of(context).colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }
}
