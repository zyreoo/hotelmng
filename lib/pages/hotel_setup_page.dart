import 'package:flutter/material.dart';
import '../models/hotel_model.dart';
import '../services/auth_provider.dart';
import '../services/hotel_provider.dart';

/// Shown when no hotel is selected. User can create a hotel or select one (by owner).
class HotelSetupPage extends StatefulWidget {
  const HotelSetupPage({super.key});

  @override
  State<HotelSetupPage> createState() => _HotelSetupPageState();
}

class _HotelSetupPageState extends State<HotelSetupPage> {
  final _nameController = TextEditingController();
  bool _loading = false;
  String? _error;
  List<HotelModel> _myHotels = [];
  bool _listLoaded = false;
  bool _loadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadStarted) {
      _loadStarted = true;
      _loadMyHotels();
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
      setState(() {
        _error = 'Enter a hotel name';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final scope = HotelProvider.of(context);
      await scope.createHotel(name);
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

  Future<void> _selectHotel(HotelModel hotel) async {
    setState(() => _loading = true);
    try {
      final scope = HotelProvider.of(context);
      await scope.setCurrentHotel(hotel);
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
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
                  Icon(
                    Icons.hotel_rounded,
                    size: 64,
                    color: const Color(0xFF007AFF).withOpacity(0.8),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your Hotel',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a hotel or select one to get started. All data (bookings, clients, services) is stored under your hotel.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  // Create new hotel
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Hotel name',
                      hintText: 'e.g. Sunset Resort',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
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
                        color: Color(0xFFFF3B30),
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
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_rounded),
                      label: Text(_loading ? 'Creating…' : 'Create hotel'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
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
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (!_listLoaded)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_myHotels.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No hotels yet. Create one above.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
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
                          color: Colors.white,
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
                                    color: Colors.grey.shade600,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      hotel.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (_loading)
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else
                                    const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 14,
                                      color: Color(0xFF007AFF),
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
                      style: TextStyle(color: Colors.grey.shade600),
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
