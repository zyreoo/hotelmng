import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';

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
    if (hotelId != null) _loadRooms(hotelId);
  }

  Future<void> _loadRooms(String hotelId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _firebaseService.getRooms(hotelId);
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

  Future<void> _addRoom(String hotelId) async {
    final name = await _showNameDialog(context, name: '');
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await _firebaseService.createRoom(hotelId, name);
      if (mounted) _loadRooms(hotelId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add room: $e')),
        );
      }
    }
  }

  Future<void> _editRoom(String hotelId, RoomModel room) async {
    final name = await _showNameDialog(context, name: room.name);
    if (name == null || name == room.name || room.id == null || !mounted) return;
    try {
      await _firebaseService.updateRoom(hotelId, room.id!, name);
      if (mounted) _loadRooms(hotelId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update room: $e')),
        );
      }
    }
  }

  Future<void> _deleteRoom(String hotelId, RoomModel room) async {
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
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF3B30)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || room.id == null || !mounted) return;
    try {
      await _firebaseService.deleteRoom(hotelId, room.id!);
      if (mounted) _loadRooms(hotelId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete room: $e')),
        );
      }
    }
  }

  static Future<String?> _showNameDialog(BuildContext context, {required String name}) async {
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

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Manage rooms'),
        backgroundColor: const Color(0xFFF5F5F7),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFFF3B30)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _rooms.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.meeting_room_rounded,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No rooms yet',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add rooms to use them in the calendar and when creating bookings.',
                              style: TextStyle(color: Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      itemCount: _rooms.length,
                      itemBuilder: (context, index) {
                        final room = _rooms[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF007AFF).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.meeting_room_rounded,
                                color: Color(0xFF007AFF),
                                size: 22,
                              ),
                            ),
                            title: Text(
                              room.name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit_outlined, color: Colors.grey.shade600),
                                  onPressed: hotelId == null
                                      ? null
                                      : () => _editRoom(hotelId, room),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30)),
                                  onPressed: hotelId == null
                                      ? null
                                      : () => _deleteRoom(hotelId, room),
                                ),
                              ],
                            ),
                            onTap: hotelId == null ? null : () => _editRoom(hotelId, room),
                          ),
                        );
                      },
                    ),
      floatingActionButton: hotelId == null
          ? null
          : FloatingActionButton(
              onPressed: () => _addRoom(hotelId),
              backgroundColor: const Color(0xFF007AFF),
              child: const Icon(Icons.add),
            ),
    );
  }
}
