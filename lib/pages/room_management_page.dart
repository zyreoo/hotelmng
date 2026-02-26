import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../services/auth_provider.dart';
import '../utils/stayora_colors.dart';
import '../widgets/stayora_logo.dart';
import '../widgets/app_notification.dart';

/// Manage rooms: add, edit name, delete. Shown from the calendar.
/// Room count is capped by Settings > Total Rooms.
class RoomManagementPage extends StatefulWidget {
  const RoomManagementPage({super.key});

  @override
  State<RoomManagementPage> createState() => _RoomManagementPageState();
}

class _RoomManagementPageState extends State<RoomManagementPage> {
  final FirebaseService _firebaseService = FirebaseService();
  List<RoomModel> _rooms = [];
  bool _loading = true;
  String? _error;

  int get _maxRooms {
    final n = HotelProvider.of(context).currentHotel?.totalRooms;
    return (n != null && n > 0) ? n : 999;
  }

  bool get _canAddRoom => _rooms.length < _maxRooms;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    if (hotelId != null && userId != null) _loadRooms(userId, hotelId);
  }

  Future<void> _loadRooms(String userId, String hotelId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _firebaseService.getRooms(userId, hotelId);
      if (mounted) {
        setState(() {
          _rooms = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _rooms = [];
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _addRoom(String userId, String hotelId) async {
    if (!_canAddRoom) {
      showAppNotification(
        context,
        'Maximum of $_maxRooms rooms reached. Change Total Rooms in Settings to add more.',
      );
      return;
    }
    final name = await _showNameDialog(context, name: '');
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await _firebaseService.createRoom(userId, hotelId, name);
      if (mounted) _loadRooms(userId, hotelId);
      if (mounted) {
        showAppNotification(context, 'Room "$name" added', type: AppNotificationType.success);
      }
    } catch (e) {
      if (mounted) {
        showAppNotification(context, 'Failed to add room: $e', type: AppNotificationType.error);
      }
    }
  }

  Future<void> _editRoom(String userId, String hotelId, RoomModel room) async {
    final name = await _showNameDialog(context, name: room.name);
    if (name == null || name == room.name || room.id == null || !mounted) {
      return;
    }
    try {
      await _firebaseService.updateRoom(userId, hotelId, room.id!, name);
      if (mounted) _loadRooms(userId, hotelId);
      if (mounted) {
        showAppNotification(context, 'Room updated', type: AppNotificationType.success);
      }
    } catch (e) {
      if (mounted) {
        showAppNotification(context, 'Failed to update room: $e', type: AppNotificationType.error);
      }
    }
  }

  Future<void> _cycleHousekeepingStatus(
      String userId, String hotelId, RoomModel room) async {
    if (room.id == null) return;
    final statuses = RoomModel.housekeepingStatuses;
    final currentIdx = statuses.indexOf(room.housekeepingStatus);
    final nextStatus = statuses[(currentIdx + 1) % statuses.length];
    try {
      await _firebaseService.updateRoomHousekeeping(
          userId, hotelId, room.id!, nextStatus);
      if (mounted) _loadRooms(userId, hotelId);
    } catch (e) {
      if (mounted) {
        showAppNotification(context, 'Failed to update: $e', type: AppNotificationType.error);
      }
    }
  }

  Future<void> _editTags(
      String userId, String hotelId, RoomModel room) async {
    if (room.id == null) return;
    final tags = await _showTagsDialog(context, tags: room.tags);
    if (tags == null || !mounted) return;
    try {
      await _firebaseService.updateRoomTags(userId, hotelId, room.id!, tags);
      if (mounted) _loadRooms(userId, hotelId);
    } catch (e) {
      if (mounted) {
        showAppNotification(context, 'Failed to update tags: $e', type: AppNotificationType.error);
      }
    }
  }

  static Future<List<String>?> _showTagsDialog(
    BuildContext context, {
    required List<String> tags,
  }) async {
    final controller = TextEditingController();
    List<String> current = List<String>.from(tags);
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setS) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Text(
              'Room Tags',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'e.g. Sea view, Ground floor, Accessible',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (current.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: current.map((tag) {
                        return Chip(
                          label: Text(tag,
                              style: const TextStyle(fontSize: 13)),
                          deleteIcon:
                              const Icon(Icons.close_rounded, size: 16),
                          onDeleted: () {
                            setS(() => current.remove(tag));
                          },
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          textCapitalization:
                              TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Add tag…',
                            filled: true,
                            fillColor: Theme.of(ctx)
                                .colorScheme
                                .surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            isDense: true,
                          ),
                          onSubmitted: (v) {
                            final t = v.trim();
                            if (t.isNotEmpty && !current.contains(t)) {
                              setS(() => current.add(t));
                              controller.clear();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          final t = controller.text.trim();
                          if (t.isNotEmpty && !current.contains(t)) {
                            setS(() => current.add(t));
                            controller.clear();
                          }
                        },
                        icon: const Icon(Icons.add_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: StayoraLogo.stayoraBlue
                              .withValues(alpha:0.1),
                          foregroundColor: StayoraLogo.stayoraBlue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: StayoraLogo.stayoraBlue,
                ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(current),
                style: FilledButton.styleFrom(
                  backgroundColor: StayoraLogo.stayoraBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _deleteRoom(String userId, String hotelId, RoomModel room) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Delete room?'),
          content: Text(
            'Delete room "${room.name}"? Bookings that use this room will still exist but the room will no longer appear in the calendar.',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: StayoraColors.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirm != true || room.id == null || !mounted) return;
    try {
      await _firebaseService.deleteRoom(userId, hotelId, room.id!);
      if (mounted) _loadRooms(userId, hotelId);
      if (mounted) {
        showAppNotification(context, 'Room deleted', type: AppNotificationType.success);
      }
    } catch (e) {
      if (mounted) {
        showAppNotification(context, 'Failed to delete room: $e', type: AppNotificationType.error);
      }
    }
  }

  /// Apple-style dialog: stays on same screen, navbar visible. Title, field, Cancel + Add/Save.
  static Future<String?> _showNameDialog(
    BuildContext context, {
    required String name,
  }) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isNew = name.isEmpty;
    final controller = TextEditingController(text: name);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            isNew ? 'New Room' : 'Room Name',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'e.g. 101, Suite A',
              hintStyle: TextStyle(
                color: colorScheme.onSurfaceVariant.withValues(alpha:0.7),
                fontSize: 17,
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            style: TextStyle(
              fontSize: 17,
              color: colorScheme.onSurface,
            ),
            onSubmitted: (value) {
              final trimmed = value.trim();
              if (trimmed.isNotEmpty) {
                Navigator.of(ctx).pop(trimmed);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(
                foregroundColor: StayoraLogo.stayoraBlue,
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty) {
                  Navigator.of(ctx).pop(trimmed);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: StayoraLogo.stayoraBlue,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: Text(isNew ? 'Add' : 'Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    final canEdit = hotelId != null && userId != null;
    final horizontalPadding = MediaQuery.of(context).size.width >= 768 ? 24.0 : 16.0;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(horizontalPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (Navigator.canPop(context)) ...[
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_rounded),
                        onPressed: () => Navigator.pop(context),
                        color: StayoraLogo.stayoraBlue,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      'Rooms',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 34,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _maxRooms >= 999
                          ? 'Manage rooms for the calendar and bookings.'
                          : '${_rooms.length} / $_maxRooms rooms. Max set in Settings.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_loading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                    color: StayoraLogo.stayoraBlue,
                    strokeWidth: 2,
                  ),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(horizontalPadding * 2),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: colorScheme.error,
                            fontSize: 15,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_rooms.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(horizontalPadding * 2),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.door_front_door_rounded,
                          size: 64,
                          color: colorScheme.onSurfaceVariant.withValues(alpha:0.6),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'No rooms yet',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _canAddRoom
                              ? 'Add rooms to use them in the calendar\nand when creating bookings.'
                              : 'Maximum rooms reached. Change Total Rooms in Settings to add more.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (canEdit && _canAddRoom) ...[
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () => _addRoom(userId, hotelId),
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: const Text('Add first room'),
                            style: FilledButton.styleFrom(
                              backgroundColor: StayoraLogo.stayoraBlue,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_rooms.length} / $_maxRooms rooms',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Room list card
                      Container(
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withValues(alpha:
                                theme.brightness == Brightness.dark ? 0.3 : 0.06,
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(_rooms.length * 2 - 1, (i) {
                            if (i.isOdd) {
                              return Divider(
                                height: 1,
                                thickness: 1,
                                indent: 56,
                                endIndent: 16,
                                color: colorScheme.outline.withValues(alpha:0.2),
                              );
                            }
                            final index = i ~/ 2;
                            final room = _rooms[index];
                            final hkColor = StayoraColors.housekeepingColor(
                              room.housekeepingStatus,
                            );
                            final hkLabel = RoomModel.housekeepingLabels[
                                room.housekeepingStatus] ??
                                'Clean';
                            return Material(
                              color: Colors.transparent,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: StayoraLogo.stayoraBlue
                                                .withValues(alpha:0.12),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            Icons.door_front_door_rounded,
                                            size: 22,
                                            color: StayoraLogo.stayoraBlue,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: InkWell(
                                            onTap: canEdit
                                                ? () => _editRoom(
                                                    userId, hotelId, room)
                                                : null,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            child: Text(
                                              room.name,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w500,
                                                color: colorScheme.onSurface,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (canEdit) ...[
                                          // Housekeeping status chip
                                          GestureDetector(
                                            onTap: () => _cycleHousekeepingStatus(
                                                userId, hotelId, room),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: hkColor.withValues(alpha:0.1),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color:
                                                      hkColor.withValues(alpha:0.5),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: 7,
                                                    height: 7,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: hkColor,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Text(
                                                    hkLabel,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: hkColor,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            onPressed: () => _deleteRoom(
                                                userId, hotelId, room),
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 20,
                                              color: StayoraColors.error,
                                            ),
                                            tooltip: 'Delete room',
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                const BoxConstraints(),
                                          ),
                                        ],
                                      ],
                                    ),
                                    // Tags row
                                    if (canEdit) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          ...room.tags.map((tag) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: colorScheme
                                                      .surfaceContainerHighest,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          20),
                                                  border: Border.all(
                                                    color: colorScheme.outline
                                                        .withValues(alpha:0.3),
                                                  ),
                                                ),
                                                child: Text(
                                                  tag,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              )),
                                          GestureDetector(
                                            onTap: () => _editTags(
                                                userId, hotelId, room),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: StayoraLogo.stayoraBlue
                                                    .withValues(alpha:0.06),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: StayoraLogo.stayoraBlue
                                                      .withValues(alpha:0.3),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.edit_rounded,
                                                    size: 11,
                                                    color:
                                                        StayoraLogo.stayoraBlue,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    room.tags.isEmpty
                                                        ? 'Add tags'
                                                        : 'Edit tags',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: StayoraLogo
                                                          .stayoraBlue,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      if (!_canAddRoom && canEdit) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            'Maximum of $_maxRooms rooms. Change Total Rooms in Settings to add more.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      if (canEdit && _canAddRoom) ...[
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _addRoom(userId, hotelId),
                            icon: const Icon(Icons.add_rounded, size: 20),
                            label: const Text('Add room'),
                            style: FilledButton.styleFrom(
                              backgroundColor: StayoraLogo.stayoraBlue,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

}
