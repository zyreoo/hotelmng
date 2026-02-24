import 'package:flutter/material.dart';
import '../models/employer_model.dart';
import '../models/hotel_model.dart';
import '../models/room_model.dart';
import '../services/auth_provider.dart';
import '../services/firebase_service.dart';
import '../services/hotel_provider.dart';
import '../utils/stayora_colors.dart';
import '../widgets/app_notification.dart';
import '../widgets/stayora_logo.dart';
import 'add_employee_page.dart';

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
    if (_phase == _SetupPhase.setupRooms && _pendingHotel != null && !_roomsLoaded) {
      _loadSetupRooms();
    }
    if (_phase == _SetupPhase.setupEmployees && _pendingHotel != null && !_employeesLoaded) {
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

  Future<void> _createHotel() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a hotel name');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final scope = HotelProvider.of(context);
      final hotel = await scope.createHotel(name, setAsCurrent: false);
      if (mounted) {
        setState(() {
          _loading = false;
          _pendingHotel = hotel;
          _phase = _SetupPhase.setupRooms;
          _roomsLoaded = false;
          _setupRooms = [];
          _setupEmployees = [];
          _employeesLoaded = false;
        });
        _loadSetupRooms();
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

  String get _setupUserId => _pendingHotel?.ownerId ?? AuthScopeData.of(context).uid ?? '';
  String get _setupHotelId => _pendingHotel?.id ?? '';

  Future<void> _loadSetupRooms() async {
    final userId = _setupUserId;
    final hotelId = _setupHotelId;
    if (userId.isEmpty || hotelId.isEmpty) return;
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
    final userId = _setupUserId;
    final hotelId = _setupHotelId;
    if (userId.isEmpty || hotelId.isEmpty) return;
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
    final userId = _setupUserId;
    final hotelId = _setupHotelId;
    if (userId.isEmpty || hotelId.isEmpty) return;
    setState(() => _loading = true);
    try {
      await _firebaseService.createRoom(userId, hotelId, name);
      if (mounted) {
        await _loadSetupRooms();
        setState(() => _loading = false);
        showAppNotification(context, 'Room "$name" added', type: AppNotificationType.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showAppNotification(context, 'Failed to add room: $e', type: AppNotificationType.error);
      }
    }
  }

  Future<String?> _showRoomNameDialog(String initial) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('New room'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. 101, Suite A',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addEmployeeInSetup() async {
    final userId = _setupUserId;
    final hotelId = _setupHotelId;
    if (userId.isEmpty || hotelId.isEmpty) return;
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => AddEmployeePage(
          overrideHotelId: hotelId,
          overrideUserId: userId,
        ),
      ),
    );
    if (mounted && added == true) _loadSetupEmployees();
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
      await HotelProvider.of(context).setCurrentHotel(hotel);
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
        title: const Text('Set up hotel'),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: [
                  Text(
                    hotelName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
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
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.meeting_room_rounded,
                                size: 64,
                                color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No rooms yet',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: _loading ? null : _addRoomInSetup,
                                icon: const Icon(Icons.add_rounded, size: 20),
                                label: const Text('Add room'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: StayoraLogo.stayoraBlue,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
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
                              ),
                            );
                          },
                        ))
                  : const Center(child: CircularProgressIndicator(color: StayoraLogo.stayoraBlue)),
            ),
            if (_setupRooms.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _addRoomInSetup,
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Add another room'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _loading ? null : _nextFromRooms,
                        style: FilledButton.styleFrom(
                          backgroundColor: StayoraLogo.stayoraBlue,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Next'),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: TextButton(
                onPressed: _loading ? null : _nextFromRooms,
                child: Text(
                  'Skip — add rooms later',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
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
        title: const Text('Set up hotel'),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: [
                  Text(
                    hotelName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
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
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.people_rounded,
                                size: 64,
                                color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No team members yet',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: _loading ? null : _addEmployeeInSetup,
                                icon: const Icon(Icons.person_add_rounded, size: 20),
                                label: const Text('Add employee'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: StayoraLogo.stayoraBlue,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _setupEmployees.length,
                          itemBuilder: (context, index) {
                            final emp = _setupEmployees[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: StayoraLogo.stayoraBlue.withOpacity(0.2),
                                  child: Text(
                                    emp.name.isNotEmpty
                                        ? emp.name.substring(0, 1).toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: StayoraLogo.stayoraBlue,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                title: Text(emp.name),
                                subtitle: Text(
                                  emp.role.isNotEmpty ? emp.role : emp.department,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            );
                          },
                        ))
                  : const Center(
                      child: CircularProgressIndicator(color: StayoraLogo.stayoraBlue),
                    ),
            ),
            if (_setupEmployees.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _addEmployeeInSetup,
                  icon: const Icon(Icons.person_add_rounded, size: 20),
                  label: const Text('Add another employee'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: FilledButton(
                onPressed: _loading ? null : _finishSetup,
                style: FilledButton.styleFrom(
                  backgroundColor: StayoraLogo.stayoraBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Finish setup'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: TextButton(
                onPressed: _loading ? null : _finishSetup,
                child: Text(
                  'Skip — add team later',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectOrCreate() {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const StayoraLogo(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your Hotel',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a hotel or select one to get started. You can add rooms and team members during setup.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Hotel name',
                      hintText: 'e.g. Sunset Resort',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      prefixIcon: const Icon(Icons.business_rounded),
                    ),
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) => _createHotel(),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: StayoraColors.error,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _createHotel,
                      icon: _loading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_rounded),
                      label: Text(_loading ? 'Creating…' : 'Create hotel'),
                      style: FilledButton.styleFrom(
                        backgroundColor: StayoraLogo.stayoraBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'Or select an existing hotel',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (!_listLoaded)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: const CircularProgressIndicator(
                          color: StayoraLogo.stayoraBlue,
                        ),
                      ),
                    )
                  else if (_myHotels.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No hotels yet. Create one above.',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ..._myHotels.map((hotel) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: _loading ? null : () => _selectHotel(hotel),
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
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      hotel.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  if (_loading)
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: const CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: StayoraLogo.stayoraBlue,
                                      ),
                                    )
                                  else
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 14,
                                      color: StayoraLogo.stayoraBlue,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 32),
                  TextButton(
                    onPressed: () async {
                      await AuthScopeData.of(context).signOut();
                    },
                    child: Text(
                      'Sign out',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
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
}
