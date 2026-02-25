import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_employee_page.dart';
import '../models/employer_model.dart';
import '../models/hotel_model.dart';
import '../models/room_model.dart';
import '../services/auth_provider.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../utils/stayora_colors.dart';
import '../widgets/app_notification.dart';
import '../widgets/stayora_logo.dart';

enum _SetupPhase { selectCreate, setupRooms, setupEmployees }

/// Shown when no hotel is selected. User can create a hotel (then add rooms & employees) or select one.
class HotelSetupPage extends StatefulWidget {
  const HotelSetupPage({super.key});

  @override
  State<HotelSetupPage> createState() => _HotelSetupPageState();
}

class _HotelSetupPageState extends State<HotelSetupPage> {
  final _nameController = TextEditingController();
  final FirebaseService _firebaseService = FirebaseService();

  bool _loading = false;
  String? _error;
  List<HotelModel> _myHotels = [];
  bool _listLoaded = false;
  bool _loadStarted = false;

  // Setup wizard (after creating a new hotel)
  _SetupPhase _phase = _SetupPhase.selectCreate;
  HotelModel? _pendingHotel;
  List<RoomModel> _setupRooms = [];
  List<EmployerModel> _setupEmployees = [];
  bool _roomsLoaded = false;
  bool _employeesLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadStarted) {
      _loadStarted = true;
      _loadMyHotels();
    }
    if (_phase == _SetupPhase.setupRooms &&
        _pendingHotel != null &&
        !_roomsLoaded) {
      _loadSetupRooms();
    }
    if (_phase == _SetupPhase.setupEmployees &&
        _pendingHotel != null &&
        !_employeesLoaded) {
      _loadSetupEmployees();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadMyHotels() async {
    final scope = HotelProvider.of(context);
    final list = await scope.getHotelsForOwner();
    if (mounted) {
      setState(() {
        _myHotels = list;
        _listLoaded = true;
      });
    }
  }

  /// True when we're in setup wizard but hotel not yet created in DB (only on Finish).
  bool get _isDraftSetup => _pendingHotel != null && (_pendingHotel!.id == null || _pendingHotel!.id!.isEmpty);

  Future<void> _createHotel() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a hotel name');
      return;
    }
    setState(() {
      _error = null;
      final uid = AuthScopeData.of(context).uid ?? defaultOwnerId;
      _pendingHotel = HotelModel(
        id: null,
        name: name,
        ownerId: uid,
        totalRooms: 0,
      );
      _phase = _SetupPhase.setupRooms;
      _roomsLoaded = false;
      _setupRooms = [];
      _setupEmployees = [];
      _employeesLoaded = false;
    });
    _loadSetupRooms();
  }

  String get _setupUserId =>
      _pendingHotel?.ownerId ?? AuthScopeData.of(context).uid ?? '';
  String get _setupHotelId => _pendingHotel?.id ?? '';

  Future<void> _loadSetupRooms() async {
    final hotelId = _setupHotelId;
    if (hotelId.isEmpty) {
      if (mounted) setState(() {
        _setupRooms = [];
        _roomsLoaded = true;
      });
      return;
    }
    final userId = _setupUserId;
    try {
      final list = await _firebaseService.getRooms(userId, hotelId);
      if (mounted) {
        setState(() {
          _setupRooms = list;
          _roomsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _roomsLoaded = true);
    }
  }

  Future<void> _loadSetupEmployees() async {
    final hotelId = _setupHotelId;
    if (hotelId.isEmpty) {
      if (mounted) setState(() {
        _setupEmployees = [];
        _employeesLoaded = true;
      });
      return;
    }
    final userId = _setupUserId;
    try {
      final list = await _firebaseService.getEmployers(userId, hotelId);
      if (mounted) {
        setState(() {
          _setupEmployees = list;
          _employeesLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _employeesLoaded = true);
    }
  }

  Future<void> _addRoomInSetup() async {
    final name = await _showRoomNameDialog('');
    if (name == null || name.isEmpty || !mounted) return;
    final hotelId = _setupHotelId;
    if (hotelId.isEmpty) {
      setState(() {
        _setupRooms = [
          ..._setupRooms,
          RoomModel(id: 'draft_${DateTime.now().millisecondsSinceEpoch}', name: name),
        ];
      });
      if (mounted) {
        showAppNotification(
          context,
          'Room "$name" added',
          type: AppNotificationType.success,
        );
      }
      return;
    }
    final userId = _setupUserId;
    if (userId.isEmpty) return;
    setState(() => _loading = true);
    try {
      await _firebaseService.createRoom(userId, hotelId, name);
      if (mounted) {
        await _loadSetupRooms();
        setState(() => _loading = false);
        showAppNotification(
          context,
          'Room "$name" added',
          type: AppNotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showAppNotification(
          context,
          'Failed to add room: $e',
          type: AppNotificationType.error,
        );
      }
    }
  }

  Future<void> _editRoomInSetup(RoomModel room) async {
    final currentName = room.name;
    final name = await _showRoomNameDialog(
      currentName,
      title: 'Edit room',
    );
    if (name == null || name.isEmpty || !mounted) return;
    final hotelId = _setupHotelId;
    if (hotelId.isEmpty) {
      setState(() {
        _setupRooms = _setupRooms
            .map((r) => r.id == room.id ? r.copyWith(name: name) : r)
            .toList();
      });
      if (mounted) {
        showAppNotification(
          context,
          'Room updated',
          type: AppNotificationType.success,
        );
      }
      return;
    }
    if (room.id == null) return;
    final userId = _setupUserId;
    if (userId.isEmpty) return;
    setState(() => _loading = true);
    try {
      await _firebaseService.updateRoom(userId, hotelId, room.id!, name);
      if (mounted) {
        await _loadSetupRooms();
        setState(() => _loading = false);
        showAppNotification(
          context,
          'Room updated',
          type: AppNotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showAppNotification(
          context,
          'Failed to update room: $e',
          type: AppNotificationType.error,
        );
      }
    }
  }

  Future<void> _deleteRoomInSetup(RoomModel room) async {
    final hotelId = _setupHotelId;
    final colorScheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Delete room',
            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Are you sure you want to delete "${room.name}"? This cannot be undone.',
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: StayoraColors.error,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirm != true || !mounted) return;
    if (hotelId.isEmpty) {
      setState(() {
        _setupRooms = _setupRooms.where((r) => r.id != room.id).toList();
      });
      if (mounted) {
        showAppNotification(
          context,
          'Room deleted',
          type: AppNotificationType.success,
        );
      }
      return;
    }
    final userId = _setupUserId;
    if (userId.isEmpty || room.id == null) return;
    setState(() => _loading = true);
    try {
      await _firebaseService.deleteRoom(userId, hotelId, room.id!);
      if (mounted) {
        await _loadSetupRooms();
        setState(() => _loading = false);
        showAppNotification(
          context,
          'Room deleted',
          type: AppNotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showAppNotification(
          context,
          'Failed to delete room: $e',
          type: AppNotificationType.error,
        );
      }
    }
  }

  Future<void> _quickAddRooms(
    List<int> roomsPerFloorByFloor,
    int startFloor,
  ) async {
    final hotelId = _setupHotelId;
    if (roomsPerFloorByFloor.isEmpty) return;
    if (hotelId.isEmpty) {
      final existingNames = _setupRooms.map((r) => r.name).toSet();
      final toAdd = <RoomModel>[];
      int skipped = 0;
      for (int f = 0; f < roomsPerFloorByFloor.length; f++) {
        final floorNumber = startFloor + f;
        final roomsOnFloor = roomsPerFloorByFloor[f];
        if (roomsOnFloor <= 0) continue;
        for (int i = 1; i <= roomsOnFloor; i++) {
          final roomNumber = '$floorNumber${i.toString().padLeft(2, '0')}';
          final roomName = 'Room $roomNumber';
          if (existingNames.contains(roomName)) {
            skipped++;
            continue;
          }
          toAdd.add(RoomModel(
            id: 'draft_${DateTime.now().millisecondsSinceEpoch}_${toAdd.length}',
            name: roomName,
          ));
          existingNames.add(roomName);
        }
      }
      setState(() => _setupRooms = [..._setupRooms, ...toAdd]);
      if (mounted) {
        final message = skipped > 0
            ? 'Added ${toAdd.length} rooms ($skipped already existed)'
            : 'Added ${toAdd.length} rooms';
        showAppNotification(
          context,
          message,
          type: AppNotificationType.success,
        );
      }
      return;
    }
    final userId = _setupUserId;
    if (userId.isEmpty) return;
    setState(() => _loading = true);
    try {
      final existingNames = _setupRooms.map((r) => r.name).toSet();
      int created = 0;
      int skipped = 0;
      for (int f = 0; f < roomsPerFloorByFloor.length; f++) {
        final floorNumber = startFloor + f;
        final roomsOnFloor = roomsPerFloorByFloor[f];
        if (roomsOnFloor <= 0) continue;
        for (int i = 1; i <= roomsOnFloor; i++) {
          final roomNumber = '$floorNumber${i.toString().padLeft(2, '0')}';
          final roomName = 'Room $roomNumber';
          if (existingNames.contains(roomName)) {
            skipped++;
            continue;
          }
          await _firebaseService.createRoom(userId, hotelId, roomName);
          created++;
          existingNames.add(roomName);
        }
      }
      if (mounted) {
        await _loadSetupRooms();
        setState(() => _loading = false);
        final message = skipped > 0
            ? 'Added $created rooms ($skipped already existed)'
            : 'Added $created rooms';
        showAppNotification(
          context,
          message,
          type: AppNotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showAppNotification(
          context,
          'Failed to add rooms: $e',
          type: AppNotificationType.error,
        );
      }
    }
  }

  Future<void> _showQuickAddRoomsSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _QuickAddRoomsSheetContent(
        onResult: (roomsPerFloor, startFloor) {
          Navigator.pop<Map<String, dynamic>>(context, {
            'roomsPerFloor': roomsPerFloor,
            'startFloor': startFloor,
          });
        },
        onCancel: () => Navigator.pop(context),
      ),
    );

    if (result == null) return;
    final roomsPerFloor = result['roomsPerFloor'] as List<int>? ?? [];
    final startFloor = result['startFloor'] as int? ?? 1;
    if (roomsPerFloor.isEmpty) return;
    await _quickAddRooms(roomsPerFloor, startFloor);
  }

  Future<String?> _showRoomNameDialog(
    String initial, {
    String title = 'New room',
  }) async {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            title,
            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'e.g. 101, Suite A',
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.outline.withOpacity(0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: StayoraLogo.stayoraBlue,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              style: FilledButton.styleFrom(
                backgroundColor: StayoraLogo.stayoraBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addEmployeeInSetup() async {
    final userId = _setupUserId;
    if (userId.isEmpty) return;
    final result = await _showAddEmployeeSheet();
    if (!mounted) return;
    if (result is EmployerModel) {
      setState(() => _setupEmployees = [..._setupEmployees, result]);
      showAppNotification(
        context,
        '${result.name} added',
        type: AppNotificationType.success,
      );
    } else if (result == true) {
      _loadSetupEmployees();
    }
  }

  Future<void> _editEmployeeInSetup(EmployerModel employee) async {
    final userId = _setupUserId;
    final hotelId = _setupHotelId;
    if (userId.isEmpty) return;
    if (hotelId.isEmpty) {
      final updated = await _showEditEmployeeSheet(employee);
      if (mounted && updated != null) {
        setState(() {
          _setupEmployees = _setupEmployees
              .map((e) => e.id == employee.id ? updated : e)
              .toList();
        });
        showAppNotification(
          context,
          'Updated',
          type: AppNotificationType.success,
        );
      }
      return;
    }
    final updated = await Navigator.push<EmployerModel>(
      context,
      MaterialPageRoute<EmployerModel>(
        builder: (context) => AddEmployeePage(
          employee: employee,
          overrideHotelId: hotelId,
          overrideUserId: userId,
        ),
      ),
    );
    if (mounted && updated != null) _loadSetupEmployees();
  }

  Future<void> _deleteEmployeeInSetup(EmployerModel employee) async {
    final userId = _setupUserId;
    final hotelId = _setupHotelId;
    if (userId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove team member'),
        content: Text(
          'Remove ${employee.name} from the team? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: StayoraColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (hotelId.isEmpty) {
      setState(() {
        _setupEmployees = _setupEmployees.where((e) => e.id != employee.id).toList();
      });
      if (mounted) {
        showAppNotification(context, '${employee.name} removed', type: AppNotificationType.success);
      }
      return;
    }
    if (employee.id == null) return;
    try {
      await _firebaseService.deleteEmployer(userId, hotelId, employee.id!);
      if (mounted) {
        showAppNotification(context, '${employee.name} removed', type: AppNotificationType.success);
        _loadSetupEmployees();
      }
    } catch (e) {
      if (mounted) {
        showAppNotification(context, 'Could not remove: $e', type: AppNotificationType.error);
      }
    }
  }

  static const List<String> _defaultRoleOptions = [
    'Receptionist',
    'Front Desk Manager',
    'Housekeeper',
    'Manager',
    'Supervisor',
    'Other',
  ];

  static const List<String> _defaultDepartmentOptions = [
    'Reception',
    'Housekeeping',
    'Management',
    'Other',
  ];

  static List<String> _mergeRoleDepartmentOptions(
    List<String> defaults,
    List<String> fromDb,
  ) {
    final Set<String> set = {};
    for (final d in defaults) {
      if (d.trim().toLowerCase() != 'other') set.add(d.trim());
    }
    for (final name in fromDb) {
      final clean = name.trim();
      if (clean.isEmpty) continue;
      if (clean.toLowerCase() != 'other') set.add(clean);
    }
    final list = set.toList()..sort();
    list.add('Other');
    return list;
  }

  /// Apple-style rectangular form sheet: name, phone, email, role, department (same as Add employee page).
  /// When draft (no hotel in DB yet): returns [EmployerModel]. Otherwise creates in DB and returns true.
  Future<Object?> _showAddEmployeeSheet() async {
    final colorScheme = Theme.of(context).colorScheme;
    final userId = _setupUserId;
    final hotelId = _setupHotelId;
    if (userId.isEmpty) return null;

    List<String> roleOptions = List<String>.from(_defaultRoleOptions);
    List<String> departmentOptions = List<String>.from(_defaultDepartmentOptions);
    final isDraft = hotelId.isEmpty;
    if (!isDraft) {
      try {
        final roles = await _firebaseService.getRoles(userId, hotelId);
        final departments = await _firebaseService.getDepartments(userId, hotelId);
        if (mounted) {
          roleOptions = _mergeRoleDepartmentOptions(_defaultRoleOptions, roles);
          departmentOptions = _mergeRoleDepartmentOptions(_defaultDepartmentOptions, departments);
        }
      } catch (_) {
        // use defaults
      }
    }
    if (!mounted) return null;

    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final otherRoleController = TextEditingController();
    final otherDepartmentController = TextEditingController();

    String selectedRole = 'Receptionist';
    String selectedDepartment = 'Reception';

    final inputDecoration = (String label, String hint) => InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: colorScheme.outline.withOpacity(0.3),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: StayoraLogo.stayoraBlue,
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        );

    InputDecoration dropdownDecoration(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.6),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: StayoraLogo.stayoraBlue, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        );

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String? localError;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              return Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 16,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(
                  24,
                  10,
                  24,
                  24 + MediaQuery.of(ctx).padding.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colorScheme.onSurface.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Add employee',
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Enter their details. You can edit later from the Team page.',
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: inputDecoration('Name', 'e.g. Maria'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: inputDecoration('Phone', 'e.g. +1 234 567 8900'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: inputDecoration('Email', 'e.g. maria@hotel.com'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        decoration: dropdownDecoration('Role'),
                        items: roleOptions
                            .map(
                              (e) => DropdownMenuItem<String>(
                                value: e,
                                child: Text(e, style: TextStyle(color: colorScheme.onSurface)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setModalState(() => selectedRole = v ?? selectedRole),
                        style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
                      ),
                      if (selectedRole == 'Other') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: otherRoleController,
                          textCapitalization: TextCapitalization.words,
                          decoration: inputDecoration('Other role', 'e.g. Concierge'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedDepartment,
                        decoration: dropdownDecoration('Department'),
                        items: departmentOptions
                            .map(
                              (e) => DropdownMenuItem<String>(
                                value: e,
                                child: Text(e, style: TextStyle(color: colorScheme.onSurface)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setModalState(() => selectedDepartment = v ?? selectedDepartment),
                        style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
                      ),
                      if (selectedDepartment == 'Other') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: otherDepartmentController,
                          textCapitalization: TextCapitalization.words,
                          decoration: inputDecoration('Other department', 'e.g. Maintenance'),
                        ),
                      ],
                      if (localError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          localError!,
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: StayoraColors.error,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () async {
                            final name = nameController.text.trim();
                            if (name.isEmpty) {
                              setModalState(() {
                                localError = 'Enter a name.';
                              });
                              return;
                            }
                            final roleValue = selectedRole == 'Other'
                                ? otherRoleController.text.trim()
                                : selectedRole;
                            final departmentValue = selectedDepartment == 'Other'
                                ? otherDepartmentController.text.trim()
                                : selectedDepartment;
                            if (selectedRole == 'Other' && roleValue.isEmpty) {
                              setModalState(() => localError = 'Enter a role.');
                              return;
                            }
                            if (selectedDepartment == 'Other' && departmentValue.isEmpty) {
                              setModalState(() => localError = 'Enter a department.');
                              return;
                            }
                            setModalState(() => localError = null);
                            final roleFinal = roleValue.isEmpty ? selectedRole : roleValue;
                            final departmentFinal = departmentValue.isEmpty ? selectedDepartment : departmentValue;
                            final model = EmployerModel(
                              id: isDraft ? 'draft_${DateTime.now().millisecondsSinceEpoch}' : null,
                              name: name,
                              phone: phoneController.text.trim(),
                              email: emailController.text.trim(),
                              role: roleFinal,
                              department: departmentFinal,
                              status: 'Active',
                            );
                            if (isDraft) {
                              if (ctx.mounted) Navigator.pop(ctx, model);
                              return;
                            }
                            try {
                              await _firebaseService.createEmployer(
                                userId,
                                hotelId,
                                model,
                              );
                              if (selectedRole == 'Other' && roleValue.isNotEmpty) {
                                await _firebaseService.addRole(userId, hotelId, roleValue);
                              }
                              if (selectedDepartment == 'Other' && departmentValue.isNotEmpty) {
                                await _firebaseService.addDepartment(userId, hotelId, departmentValue);
                              }
                              if (ctx.mounted) {
                                Navigator.pop(ctx, true);
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                setModalState(() {
                                  localError = 'Could not add: ${e.toString()}';
                                });
                              }
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: StayoraLogo.stayoraBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Add'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// In-memory edit for draft setup. Returns updated [EmployerModel] or null if cancelled.
  Future<EmployerModel?> _showEditEmployeeSheet(EmployerModel employee) async {
    final colorScheme = Theme.of(context).colorScheme;
    final nameController = TextEditingController(text: employee.name);
    final phoneController = TextEditingController(text: employee.phone);
    final emailController = TextEditingController(text: employee.email);
    String selectedRole = _defaultRoleOptions.contains(employee.role) ? employee.role : 'Other';
    String selectedDepartment = _defaultDepartmentOptions.contains(employee.department) ? employee.department : 'Other';
    final otherRoleController = TextEditingController(text: _defaultRoleOptions.contains(employee.role) ? '' : employee.role);
    final otherDepartmentController = TextEditingController(text: _defaultDepartmentOptions.contains(employee.department) ? '' : employee.department);

    final inputDecoration = (String label, String hint) => InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.6),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        );
    InputDecoration dropdownDecoration(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.6),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        );

    return showModalBottomSheet<EmployerModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String? localError;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              return Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 16,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(24, 10, 24, 24 + MediaQuery.of(ctx).padding.bottom),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colorScheme.onSurface.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Edit employee',
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: inputDecoration('Name', 'e.g. Maria'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: inputDecoration('Phone', 'e.g. +1 234 567 8900'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: inputDecoration('Email', 'e.g. maria@hotel.com'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        decoration: dropdownDecoration('Role'),
                        items: _defaultRoleOptions
                            .map((e) => DropdownMenuItem<String>(value: e, child: Text(e, style: TextStyle(color: colorScheme.onSurface))))
                            .toList(),
                        onChanged: (v) => setModalState(() => selectedRole = v ?? selectedRole),
                        style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
                      ),
                      if (selectedRole == 'Other') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: otherRoleController,
                          textCapitalization: TextCapitalization.words,
                          decoration: inputDecoration('Other role', 'e.g. Concierge'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedDepartment,
                        decoration: dropdownDecoration('Department'),
                        items: _defaultDepartmentOptions
                            .map((e) => DropdownMenuItem<String>(value: e, child: Text(e, style: TextStyle(color: colorScheme.onSurface))))
                            .toList(),
                        onChanged: (v) => setModalState(() => selectedDepartment = v ?? selectedDepartment),
                        style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
                      ),
                      if (selectedDepartment == 'Other') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: otherDepartmentController,
                          textCapitalization: TextCapitalization.words,
                          decoration: inputDecoration('Other department', 'e.g. Maintenance'),
                        ),
                      ],
                      if (localError != null) ...[
                        const SizedBox(height: 12),
                        Text(localError!, style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: StayoraColors.error, fontWeight: FontWeight.w500)),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            final name = nameController.text.trim();
                            if (name.isEmpty) {
                              setModalState(() => localError = 'Enter a name.');
                              return;
                            }
                            final roleFinal = selectedRole == 'Other' ? otherRoleController.text.trim() : selectedRole;
                            final departmentFinal = selectedDepartment == 'Other' ? otherDepartmentController.text.trim() : selectedDepartment;
                            if (selectedRole == 'Other' && roleFinal.isEmpty) {
                              setModalState(() => localError = 'Enter a role.');
                              return;
                            }
                            if (selectedDepartment == 'Other' && departmentFinal.isEmpty) {
                              setModalState(() => localError = 'Enter a department.');
                              return;
                            }
                            final updated = employee.copyWith(
                              name: name,
                              phone: phoneController.text.trim(),
                              email: emailController.text.trim(),
                              role: roleFinal.isEmpty ? selectedRole : roleFinal,
                              department: departmentFinal.isEmpty ? selectedDepartment : departmentFinal,
                            );
                            Navigator.pop(ctx, updated);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: StayoraLogo.stayoraBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Save'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _nextFromRooms() {
    setState(() {
      _phase = _SetupPhase.setupEmployees;
      _employeesLoaded = false;
    });
    _loadSetupEmployees();
  }

  Future<void> _finishSetup() async {
    final hotel = _pendingHotel;
    if (hotel == null) return;
    setState(() => _loading = true);
    try {
      final userId = _setupUserId;
      final scope = HotelProvider.of(context);
      HotelModel createdHotel;

      if (_isDraftSetup) {
        // Create hotel in DB only when user presses Finish.
        createdHotel = await scope.createHotel(hotel.name, setAsCurrent: false);
        final hotelId = createdHotel.id!;
        for (final room in _setupRooms) {
          await _firebaseService.createRoom(userId, hotelId, room.name);
        }
        final customRoles = <String>{};
        final customDepartments = <String>{};
        for (final emp in _setupEmployees) {
          await _firebaseService.createEmployer(userId, hotelId, emp);
          if (!_defaultRoleOptions.contains(emp.role)) customRoles.add(emp.role);
          if (!_defaultDepartmentOptions.contains(emp.department)) customDepartments.add(emp.department);
        }
        for (final r in customRoles) {
          await _firebaseService.addRole(userId, hotelId, r);
        }
        for (final d in customDepartments) {
          await _firebaseService.addDepartment(userId, hotelId, d);
        }
        final roomCount = _setupRooms.length;
        createdHotel = createdHotel.copyWith(totalRooms: roomCount);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('hotels')
            .doc(hotelId)
            .update(createdHotel.toFirestore());
      } else {
        createdHotel = hotel;
        final hotelId = _setupHotelId;
        final roomCount = _setupRooms.length;
        if (userId.isNotEmpty && hotelId.isNotEmpty && roomCount > 0) {
          createdHotel = hotel.copyWith(totalRooms: roomCount);
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('hotels')
              .doc(hotelId)
              .update(createdHotel.toFirestore());
        }
      }

      await scope.setCurrentHotel(createdHotel);
      if (mounted) {
        setState(() {
          _loading = false;
          _pendingHotel = null;
          _phase = _SetupPhase.selectCreate;
          _setupRooms = [];
          _setupEmployees = [];
          _roomsLoaded = false;
          _employeesLoaded = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _selectHotel(HotelModel hotel) async {
    setState(() => _loading = true);
    try {
      await HotelProvider.of(context).setCurrentHotel(hotel);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _deleteHotel(HotelModel hotel) async {
    if (hotel.id == null || hotel.id!.isEmpty) return;
    final colorScheme = Theme.of(context).colorScheme;
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.of(ctx).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Delete hotel',
                style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Delete "${hotel.name}"? This cannot be undone. Rooms, bookings, and team data for this hotel will no longer be accessible.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: StayoraColors.error,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Delete'),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.onSurfaceVariant,
                  ),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (confirm != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await HotelProvider.of(context).deleteHotel(hotel.id!, ownerId: hotel.ownerId);
      if (mounted) {
        await _loadMyHotels();
        setState(() => _loading = false);
        showAppNotification(context, 'Hotel deleted', type: AppNotificationType.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showAppNotification(context, 'Failed to delete: $e', type: AppNotificationType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _SetupPhase.setupRooms) {
      return _buildSetupRooms();
    }
    if (_phase == _SetupPhase.setupEmployees) {
      return _buildSetupEmployees();
    }
    return _buildSelectOrCreate();
  }

  Widget _buildSetupRooms() {
    final colorScheme = Theme.of(context).colorScheme;
    final hotelName = _pendingHotel?.name ?? 'Your hotel';
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const StayoraLogo(fontSize: 32, textAlign: TextAlign.center),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _loading
            ? null
            : () {
                setState(() {
                  _phase = _SetupPhase.selectCreate;
                  _pendingHotel = null;
                  _roomsLoaded = false;
                  _employeesLoaded = false;
                });
                _loadMyHotels();
              },
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Breathing room under app bar; step and title sit lower so top isn't busy
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Step 1 of 2 · Rooms',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    hotelName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add rooms to your hotel. You can add more later from the Calendar.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _roomsLoaded
                  ? (_setupRooms.isEmpty
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.meeting_room_rounded,
                                  size: 52,
                                  color: colorScheme.onSurfaceVariant
                                      .withOpacity(0.6),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No rooms yet',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                FilledButton(
                                  onPressed: _loading ? null : _addRoomInSetup,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: StayoraLogo.stayoraBlue,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('Add room'),
                                ),
                                const SizedBox(height: 10),
                                TextButton(
                                  onPressed: _loading
                                      ? null
                                      : _showQuickAddRoomsSheet,
                                  style: TextButton.styleFrom(
                                    foregroundColor: colorScheme.onSurfaceVariant,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                  ),
                                  child: const Text('Quick add multiple rooms'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _setupRooms.length,
                            itemBuilder: (context, index) {
                              final room = _setupRooms[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: Icon(
                                    Icons.door_front_door_rounded,
                                    color: StayoraLogo.stayoraBlue,
                                  ),
                                  title: Text(room.name),
                                  onTap: () => _editRoomInSetup(room),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Edit room',
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 20,
                                        ),
                                        onPressed: _loading
                                            ? null
                                            : () => _editRoomInSetup(room),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete room',
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 20,
                                          color: StayoraColors.error,
                                        ),
                                        onPressed: _loading
                                            ? null
                                            : () => _deleteRoomInSetup(room),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ))
                  : const Center(
                      child: CircularProgressIndicator(
                        color: StayoraLogo.stayoraBlue,
                      ),
                    ),
            ),
            if (_setupRooms.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _nextFromRooms,
                        style: FilledButton.styleFrom(
                          backgroundColor: StayoraLogo.stayoraBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Next'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _loading ? null : _addRoomInSetup,
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Add a room',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Text(
                          '·',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                        TextButton(
                          onPressed: _loading ? null : _showQuickAddRoomsSheet,
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Quick add rooms',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (_setupRooms.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: TextButton(
                  onPressed: _loading ? null : _nextFromRooms,
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Skip — add rooms later'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupEmployees() {
    final colorScheme = Theme.of(context).colorScheme;
    final hotelName = _pendingHotel?.name ?? 'Your hotel';
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const StayoraLogo(fontSize: 32, textAlign: TextAlign.center),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _loading
              ? null
              : () => setState(() => _phase = _SetupPhase.setupRooms),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Step 2 of 2 · Team',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    hotelName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add team members (reception, housekeeping, etc.). You can add more later from the Team page.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _employeesLoaded
                  ? (_setupEmployees.isEmpty
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.people_rounded,
                                size: 52,
                                color: colorScheme.onSurfaceVariant
                                    .withOpacity(0.6),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No team members yet',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed:
                                    _loading ? null : _addEmployeeInSetup,
                                style: FilledButton.styleFrom(
                                  backgroundColor: StayoraLogo.stayoraBlue,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Add employee'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _setupEmployees.length,
                          itemBuilder: (context, index) {
                            final emp = _setupEmployees[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: StayoraLogo.stayoraBlue
                                      .withOpacity(0.2),
                                  child: Text(
                                    emp.name.isNotEmpty
                                        ? emp.name
                                            .substring(0, 1)
                                            .toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: StayoraLogo.stayoraBlue,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                title: Text(emp.name),
                                subtitle: Text(
                                  emp.role.isNotEmpty
                                      ? emp.role
                                      : emp.department,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        size: 22,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      onPressed: _loading
                                          ? null
                                          : () => _editEmployeeInSetup(emp),
                                      tooltip: 'Edit',
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 22,
                                        color: StayoraColors.error,
                                      ),
                                      onPressed: _loading
                                          ? null
                                          : () => _deleteEmployeeInSetup(emp),
                                      tooltip: 'Remove',
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ))
                  : const Center(
                      child: CircularProgressIndicator(
                        color: StayoraLogo.stayoraBlue,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(
                children: [
                  if (_setupEmployees.isNotEmpty) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _loading ? null : _addEmployeeInSetup,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: StayoraLogo.stayoraBlue,
                          side: BorderSide(color: StayoraLogo.stayoraBlue),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Add another'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: _loading ? null : _finishSetup,
                      style: FilledButton.styleFrom(
                        backgroundColor: StayoraLogo.stayoraBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            )
                          : const Text('Finish setup'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectOrCreate() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasExistingHotels = _myHotels.isNotEmpty;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const SizedBox.shrink(),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero: logo + page title (Apple-style hierarchy)
                  const StayoraLogo(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    hasExistingHotels ? 'Choose hotel' : 'Set up your hotel',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                      letterSpacing: -0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    hasExistingHotels
                        ? 'Create a new one or switch to an existing hotel.'
                        : 'Create your first hotel to get started.',
                    style: textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  // Create hotel form — clean, no heavy card
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Hotel name',
                      hintText: 'e.g. Sunset Resort',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: colorScheme.outline.withOpacity(0.4),
                        ),
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest
                          .withOpacity(0.6),
                      prefixIcon: Icon(
                        Icons.business_rounded,
                        color: colorScheme.onSurfaceVariant,
                        size: 22,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) => _createHotel(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: textTheme.bodySmall?.copyWith(
                        color: StayoraColors.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _createHotel,
                      style: FilledButton.styleFrom(
                        backgroundColor: StayoraLogo.stayoraBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _loading
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            )
                          : const Text('Create hotel'),
                    ),
                  ),
                  if (hasExistingHotels) ...[
                    const SizedBox(height: 40),
                    Text(
                      'Your hotels',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!_listLoaded)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: StayoraLogo.stayoraBlue,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    else
                      ..._myHotels.map((hotel) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: colorScheme.surfaceContainerHighest
                                .withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: _loading
                                  ? null
                                  : () => _selectHotel(hotel),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.hotel_rounded,
                                      color: colorScheme.onSurfaceVariant,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        hotel.name,
                                        style: textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.w500,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete hotel',
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 20,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      onPressed: _loading
                                          ? null
                                          : () => _deleteHotel(hotel),
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size(36, 36),
                                      ),
                                    ),
                                    Text(
                                      'Select',
                                      style: textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: StayoraLogo.stayoraBlue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                  const SizedBox(height: 40),
                  Center(
                    child: TextButton(
                      onPressed: () async {
                        await AuthScopeData.of(context).signOut();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Sign out'),
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
  }
}

/// Sheet content for quick add rooms: ask number of floors, then for each floor
/// how many rooms. Returns list of room counts per floor and starting floor number.
class _QuickAddRoomsSheetContent extends StatefulWidget {
  const _QuickAddRoomsSheetContent({
    required this.onResult,
    required this.onCancel,
  });

  final void Function(List<int> roomsPerFloor, int startFloor) onResult;
  final VoidCallback onCancel;

  @override
  State<_QuickAddRoomsSheetContent> createState() =>
      _QuickAddRoomsSheetContentState();
}

class _QuickAddRoomsSheetContentState extends State<_QuickAddRoomsSheetContent> {
  final _floorsController = TextEditingController(text: '1');
  final _startFloorController = TextEditingController(text: '1');
  final List<TextEditingController> _roomControllers = [];
  String? _error;

  int get _numFloors {
    final n = int.tryParse(_floorsController.text.trim()) ?? 0;
    return n.clamp(1, 20);
  }

  int get _startFloor {
    return int.tryParse(_startFloorController.text.trim()) ?? 1;
  }

  @override
  void initState() {
    super.initState();
    _syncRoomControllers();
    _floorsController.addListener(_onFloorsChanged);
  }

  void _onFloorsChanged() {
    _syncRoomControllers();
  }

  void _syncRoomControllers() {
    final n = _numFloors;
    while (_roomControllers.length < n) {
      _roomControllers.add(TextEditingController(text: '10'));
    }
    while (_roomControllers.length > n) {
      _roomControllers.removeLast().dispose();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _floorsController.removeListener(_onFloorsChanged);
    _floorsController.dispose();
    _startFloorController.dispose();
    for (final c in _roomControllers) {
      c.dispose();
    }
    super.dispose();
  }

  InputDecoration _inputDecoration(String hint) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.6),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: StayoraLogo.stayoraBlue,
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  void _submit() {
    final startFloor = _startFloor;
    final list = <int>[];
    for (final c in _roomControllers) {
      list.add(int.tryParse(c.text.trim()) ?? 0);
    }
    final hasAny = list.any((n) => n > 0);
    if (!hasAny) {
      setState(() => _error = 'Enter at least 1 room on any floor.');
      return;
    }
    setState(() => _error = null);
    widget.onResult(list, startFloor);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Keep controllers in sync when floors field changes
    if (_roomControllers.length != _numFloors) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncRoomControllers());
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          10,
          24,
          24 + MediaQuery.of(context).padding.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Quick add rooms',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Set how many rooms on each floor. You can edit or add more later.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Number of floors',
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _floorsController,
                keyboardType: TextInputType.number,
                style: textTheme.titleMedium,
                decoration: _inputDecoration('e.g. 3'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Text(
                'Starting floor number',
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _startFloorController,
                keyboardType: TextInputType.number,
                style: textTheme.titleMedium,
                decoration: _inputDecoration('e.g. 1'),
              ),
              const SizedBox(height: 20),
              Text(
                'Rooms on each floor',
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              ...List.generate(_roomControllers.length, (i) {
                final floorNum = _startFloor + i;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          'Floor $floorNum',
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _roomControllers[i],
                          keyboardType: TextInputType.number,
                          style: textTheme.titleMedium,
                          decoration: _inputDecoration('Rooms'),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: textTheme.bodySmall?.copyWith(
                    color: StayoraColors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: StayoraLogo.stayoraBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Add rooms'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: widget.onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
