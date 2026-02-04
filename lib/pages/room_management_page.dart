import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../services/auth_provider.dart';

/// Manage rooms: add, edit name, delete. Shown from the calendar.
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
    final name = await _showNameDialog(context, name: '');
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await _firebaseService.createRoom(userId, hotelId, name);
      if (mounted) _loadRooms(userId, hotelId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add room: $e')));
      }
    }
  }

  Future<void> _editRoom(String userId, String hotelId, RoomModel room) async {
    final name = await _showNameDialog(context, name: room.name);
    if (name == null || name == room.name || room.id == null || !mounted)
      return;
    try {
      await _firebaseService.updateRoom(userId, hotelId, room.id!, name);
      if (mounted) _loadRooms(userId, hotelId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update room: $e')));
      }
    }
  }

  Future<void> _deleteRoom(String userId, String hotelId, RoomModel room) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete room?'),
        content: Text(
          'Delete room "${room.name}"? Bookings that use this room will still exist but the room will no longer appear in the calendar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF3B30),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || room.id == null || !mounted) return;
    try {
      await _firebaseService.deleteRoom(userId, hotelId, room.id!);
      if (mounted) _loadRooms(userId, hotelId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete room: $e')));
      }
    }
  }

  static Future<String?> _showNameDialog(
    BuildContext context, {
    required String name,
  }) async {
    final controller = TextEditingController(text: name);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(name.isEmpty ? 'Add room' : 'Edit room name'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Room name',
              hintText: 'e.g. 101, Suite A',
            ),
            autofocus: true,
            onSubmitted: (_) => Navigator.of(ctx).pop(controller.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hotelId = HotelProvider.of(context).hotelId;
    final userId = AuthScopeData.of(context).uid;
    final canEdit = hotelId != null && userId != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text(
          'Rooms',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF000000),
          ),
        ),
        backgroundColor: const Color(0xFFF2F2F7),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        actions: [
          if (canEdit)
            TextButton(
              onPressed: () => _addRoom(userId!, hotelId!),
              child: const Text(
                'Add',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF007AFF),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF007AFF),
                strokeWidth: 2,
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFFF3B30),
                        fontSize: 15,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _rooms.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.door_front_door_rounded,
                              size: 56,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Rooms',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 22,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add rooms to use them in the calendar\nand when creating bookings.',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 15,
                                height: 1.35,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      children: [
                        Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 1),
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
                                      color: Colors.grey.shade200,
                                    );
                                  }
                                  final index = i ~/ 2;
                                  final room = _rooms[index];
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: canEdit
                                          ? () => _editRoom(userId!, hotelId!, room)
                                          : null,
                                      onLongPress: canEdit
                                          ? () => _showRoomActions(
                                                userId!,
                                                hotelId!,
                                                room,
                                              )
                                          : null,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.door_front_door_rounded,
                                              size: 22,
                                              color: Colors.grey.shade500,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                room.name,
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w400,
                                                  color: Color(0xFF000000),
                                                ),
                                              ),
                                            ),
                                            if (canEdit)
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                size: 22,
                                                color: Colors.grey.shade400,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                            }),
                          ),
                        ),
                      ],
                    ),
    );
  }

  void _showRoomActions(String userId, String hotelId, RoomModel room) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF2F2F7),
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.edit_outlined, size: 22),
                title: const Text('Edit room name'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editRoom(userId, hotelId, room);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  size: 22,
                  color: Color(0xFFFF3B30),
                ),
                title: const Text(
                  'Delete room',
                  style: TextStyle(
                    color: Color(0xFFFF3B30),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteRoom(userId, hotelId, room);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
