import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../services/auth_provider.dart';
import '../utils/stayora_colors.dart';
import '../widgets/app_notification.dart';
import '../widgets/loading_empty_states.dart';

class HousekeepingPage extends StatefulWidget {
  const HousekeepingPage({super.key});

  @override
  State<HousekeepingPage> createState() => _HousekeepingPageState();
}

class _HousekeepingPageState extends State<HousekeepingPage> {
  final FirebaseService _firebaseService = FirebaseService();
  List<RoomModel> _rooms = [];
  bool _loading = true;
  String? _error;
  String? _subscribedUserId;
  String? _subscribedHotelId;
  dynamic _roomsSubscription;

  // null = show all
  String? _filterStatus;
  String? _filterTag;

  static const _statusIcons = {
    'clean': Icons.check_circle_rounded,
    'occupied': Icons.bed_rounded,
    'cleaning': Icons.cleaning_services_rounded,
    'dirty': Icons.warning_amber_rounded,
    'out_of_order': Icons.block_rounded,
  };

  /// Cycle order for housekeeping staff when tapping a room.
  /// We only rotate between the operational states; 'occupied' is driven by
  /// bookings and 'out_of_order' is managed from the Rooms screen.
  static const List<String> _cycleStatuses = [
    'dirty',
    'cleaning',
    'clean',
  ];

  /// Statuses that can be explicitly set from the picker in this screen.
  static const List<String> _pickerStatuses = [
    'clean',
    'dirty',
    'cleaning',
  ];

  /// Section order: dirty first (most visible), then cleaning, then available (clean), then occupied, out_of_order.
  static const List<String> _statusDisplayOrder = [
    'dirty',
    'cleaning',
    'clean',
    'occupied',
    'out_of_order',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = AuthScopeData.of(context).uid;
    final hotelId = HotelProvider.of(context).hotelId;
    if (userId == null || hotelId == null) return;
    if (userId == _subscribedUserId && hotelId == _subscribedHotelId) return;
    _subscribedUserId = userId;
    _subscribedHotelId = hotelId;
    _roomsSubscription?.cancel();
    setState(() { _loading = true; _error = null; });
    _roomsSubscription = _firebaseService
        .roomsSnapshot(userId, hotelId)
        .listen(
      (rooms) {
        if (mounted) setState(() { _rooms = rooms; _loading = false; _error = null; });
      },
      onError: (e) {
        if (mounted) setState(() { _loading = false; _error = e.toString(); });
      },
    );
  }

  @override
  void dispose() {
    _roomsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _cycleStatus(RoomModel room) async {
    final userId = _subscribedUserId;
    final hotelId = _subscribedHotelId;
    if (room.id == null || userId == null || hotelId == null) return;
    // Only allow cycling between operational statuses; occupied and
    // out_of_order are controlled from other screens.
    if (!_HousekeepingPageState._cycleStatuses
        .contains(room.housekeepingStatus)) return;
    final currentIdx = _HousekeepingPageState._cycleStatuses
        .indexOf(room.housekeepingStatus);
    final nextStatus =
        _HousekeepingPageState._cycleStatuses[
            (currentIdx + 1) % _HousekeepingPageState._cycleStatuses.length];
    try {
      await _firebaseService.updateRoomHousekeeping(
          userId, hotelId, room.id!, nextStatus);
    } catch (e) {
      if (mounted) {
        showAppNotification(context, 'Failed to update: $e',
            type: AppNotificationType.error);
      }
    }
  }

  Future<void> _setStatus(RoomModel room, String status) async {
    final userId = _subscribedUserId;
    final hotelId = _subscribedHotelId;
    if (room.id == null || userId == null || hotelId == null) return;
    if (room.housekeepingStatus == status) return;
    try {
      await _firebaseService.updateRoomHousekeeping(
          userId, hotelId, room.id!, status);
    } catch (e) {
      if (mounted) {
        showAppNotification(context, 'Failed to update: $e',
            type: AppNotificationType.error);
      }
    }
  }

  List<RoomModel> get _filteredRooms {
    return _rooms.where((r) {
      if (_filterStatus != null && r.housekeepingStatus != _filterStatus) {
        return false;
      }
      if (_filterTag != null && !r.tags.contains(_filterTag)) return false;
      return true;
    }).toList();
  }

  Set<String> get _allTags {
    final tags = <String>{};
    for (final r in _rooms) { tags.addAll(r.tags); }
    return tags;
  }

  Map<String, List<RoomModel>> get _roomsByStatus {
    final map = <String, List<RoomModel>>{};
    for (final status in RoomModel.housekeepingStatuses) {
      final rooms = _filteredRooms
          .where((r) => r.housekeepingStatus == status)
          .toList();
      if (rooms.isNotEmpty) map[status] = rooms;
    }
    return map;
  }

  /// Status keys in display order (dirty → cleaning → clean → occupied → out_of_order).
  List<String> get _statusKeysInOrder {
    final groups = _roomsByStatus;
    return _statusDisplayOrder.where((s) => groups.containsKey(s)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final allTags = _allTags;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            final userId = AuthScopeData.of(context).uid;
            final hotelId = HotelProvider.of(context).hotelId;
            if (userId == null || hotelId == null) return;
            _subscribedUserId = null;
            _subscribedHotelId = null;
            didChangeDependencies();
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'Housekeeping',
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
                        'Room status overview',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 20),
                      // Status filter chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FilterChip(
                              label: 'All',
                              isSelected: _filterStatus == null,
                              onTap: () => setState(() => _filterStatus = null),
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            ...RoomModel.housekeepingStatuses.map((s) {
                              final count =
                                  _rooms.where((r) => r.housekeepingStatus == s).length;
                              if (count == 0) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _FilterChip(
                                  label:
                                      '${RoomModel.housekeepingLabels[s]} ($count)',
                                  isSelected: _filterStatus == s,
                                  onTap: () => setState(() =>
                                      _filterStatus =
                                          _filterStatus == s ? null : s),
                                  color: StayoraColors.housekeepingColor(s),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      if (allTags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: allTags.map((tag) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _FilterChip(
                                  label: tag,
                                  isSelected: _filterTag == tag,
                                  onTap: () => setState(() =>
                                      _filterTag =
                                          _filterTag == tag ? null : tag),
                                  color: colorScheme.secondary,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              if (_loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SkeletonListLoader(
                      itemCount: 5,
                      itemHeight: 80,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                )
              else if (_error != null)
                SliverFillRemaining(
                  child: ErrorStateWidget(
                    message: _error!,
                    onRetry: () {
                      _subscribedUserId = null;
                      _subscribedHotelId = null;
                      didChangeDependencies();
                    },
                  ),
                )
              else if (_rooms.isEmpty)
                SliverFillRemaining(
                  child: EmptyStateWidget(
                    icon: Icons.cleaning_services_rounded,
                    title: 'No rooms yet',
                    subtitle: 'Add rooms in Rooms management to track status.',
                  ),
                )
              else if (_filteredRooms.isEmpty)
                SliverFillRemaining(
                  child: EmptyStateWidget(
                    icon: Icons.filter_list_rounded,
                    title: 'No rooms match filter',
                    subtitle: 'Try removing a filter.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        // Build grouped list: section header + items (order: dirty → cleaning → clean → …)
                        final statusGroups = _roomsByStatus;
                        final statusKeys = _statusKeysInOrder;
                        // Flatten into sections
                        final items = <_HkItem>[];
                        for (final status in statusKeys) {
                          items.add(_HkItem.header(status));
                          for (final room in statusGroups[status]!) {
                            items.add(_HkItem.room(room));
                          }
                        }
                        if (i >= items.length) return null;
                        final item = items[i];
                        if (item.isHeader) {
                          return _StatusSectionHeader(
                            status: item.status!,
                            count: statusGroups[item.status!]!.length,
                            color: StayoraColors.housekeepingColor(
                              item.status!,
                            ),
                            icon: _statusIcons[item.status!] ??
                                Icons.circle_rounded,
                          );
                        }
                        return _RoomHousekeepingCard(
                          room: item.room!,
                          statusIcons: _statusIcons,
                          onCycle: () => _cycleStatus(item.room!),
                          onSetStatus: (s) => _setStatus(item.room!, s),
                        );
                      },
                      childCount: () {
                        final statusGroups = _roomsByStatus;
                        int count = 0;
                        for (final s in statusGroups.keys) {
                          count += 1 + (statusGroups[s]?.length ?? 0);
                        }
                        return count;
                      }(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HkItem {
  final bool isHeader;
  final String? status;
  final RoomModel? room;

  const _HkItem._({required this.isHeader, this.status, this.room});

  factory _HkItem.header(String status) =>
      _HkItem._(isHeader: true, status: status);

  factory _HkItem.room(RoomModel room) =>
      _HkItem._(isHeader: false, room: room);
}

class _StatusSectionHeader extends StatelessWidget {
  const _StatusSectionHeader({
    required this.status,
    required this.count,
    required this.color,
    required this.icon,
  });

  final String status;
  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            RoomModel.housekeepingLabels[status] ?? status,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomHousekeepingCard extends StatelessWidget {
  const _RoomHousekeepingCard({
    required this.room,
    required this.statusIcons,
    required this.onCycle,
    required this.onSetStatus,
  });

  final RoomModel room;
  final Map<String, IconData> statusIcons;
  final VoidCallback onCycle;
  final void Function(String) onSetStatus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor =
        StayoraColors.housekeepingColor(room.housekeepingStatus);
    final statusLabel =
        RoomModel.housekeepingLabels[room.housekeepingStatus] ?? room.housekeepingStatus;
    final statusIcon =
        statusIcons[room.housekeepingStatus] ?? Icons.circle_rounded;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onCycle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Status icon badge
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha:0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(statusIcon, color: statusColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (room.tags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        children: room.tags
                            .map(
                              (t) => Chip(
                                label: Text(t,
                                    style: const TextStyle(fontSize: 11)),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                side: BorderSide.none,
                                backgroundColor:
                                    colorScheme.surfaceContainerHighest,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              // Status badge + dropdown
              GestureDetector(
                onTap: () => _showStatusPicker(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha:0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withValues(alpha:0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down_rounded,
                          size: 16, color: statusColor),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStatusPicker(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha:0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Set status for ${room.name}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ..._HousekeepingPageState._pickerStatuses.map((s) {
                final color =
                    StayoraColors.housekeepingColor(s);
                final icon = statusIcons[s] ?? Icons.circle_rounded;
                final label = RoomModel.housekeepingLabels[s] ?? s;
                final isSelected = room.housekeepingStatus == s;
                return ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha:0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  title: Text(label,
                      style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal)),
                  trailing: isSelected
                      ? Icon(Icons.check_rounded, color: color)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    onSetStatus(s);
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.color,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha:0.15) : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : colorScheme.outline.withValues(alpha:0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? color : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
