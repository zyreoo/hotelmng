import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/hotel_model.dart';
import 'auth_provider.dart';

const String _keyCurrentHotelId = 'current_hotel_id';
/// Fallback if auth context is missing (should not happen when logged in).
const String defaultOwnerId = 'default_owner';

class HotelProvider extends StatefulWidget {
  final Widget child;

  const HotelProvider({super.key, required this.child});

  static HotelScopeData of(BuildContext context) {
    final data = context.dependOnInheritedWidgetOfExactType<HotelScopeData>();
    assert(data != null, 'HotelProvider not found. Wrap app with HotelProvider.');
    return data!;
  }

  @override
  State<HotelProvider> createState() => _HotelProviderState();
}

class _HotelProviderState extends State<HotelProvider> {
  HotelModel? _currentHotel;
  bool _loaded = false;

  Future<void> _loadCurrentHotel() async {
    if (!_loaded) {
      _loaded = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        final id = prefs.getString(_keyCurrentHotelId);
        if (id != null && id.isNotEmpty) {
          final doc = await FirebaseFirestore.instance
              .collection('hotels')
              .doc(id)
              .get();
          if (doc.exists && mounted) {
            setState(() {
              _currentHotel = HotelModel.fromFirestore(
                doc.data() as Map<String, dynamic>,
                doc.id,
              );
            });
          }
        }
      } catch (_) {
        // SharedPreferences can fail on macOS (channel not ready). Continue with no hotel.
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> setCurrentHotel(HotelModel? hotel) async {
    setState(() => _currentHotel = hotel);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (hotel?.id != null) {
        await prefs.setString(_keyCurrentHotelId, hotel!.id!);
      } else {
        await prefs.remove(_keyCurrentHotelId);
      }
    } catch (_) {
      // Persistence failed; hotel is still set in memory for this session.
    }
  }

  Future<HotelModel> createHotel(String name, {String? ownerId}) async {
    final uid = ownerId ?? AuthScopeData.of(context).uid ?? defaultOwnerId;
    final ref = await FirebaseFirestore.instance.collection('hotels').add({
      'name': name,
      'ownerId': uid,
      'createdAt': DateTime.now().toIso8601String(),
    });
    final doc = await ref.get();
    final hotel = HotelModel.fromFirestore(
      doc.data() as Map<String, dynamic>,
      doc.id,
    );
    await setCurrentHotel(hotel);
    return hotel;
  }

  Future<List<HotelModel>> getHotelsForOwner({String? ownerId}) async {
    final uid = ownerId ?? AuthScopeData.of(context).uid ?? defaultOwnerId;
    final snapshot = await FirebaseFirestore.instance
        .collection('hotels')
        .where('ownerId', isEqualTo: uid)
        .get();
    final list = snapshot.docs
        .map((d) => HotelModel.fromFirestore(d.data(), d.id))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentHotel();
  }

  @override
  Widget build(BuildContext context) {
    return HotelScopeData(
      currentHotel: _currentHotel,
      setCurrentHotel: setCurrentHotel,
      createHotel: createHotel,
      getHotelsForOwner: getHotelsForOwner,
      child: widget.child,
    );
  }
}

class HotelScopeData extends InheritedWidget {
  final HotelModel? currentHotel;
  final Future<void> Function(HotelModel?) setCurrentHotel;
  final Future<HotelModel> Function(String name, {String? ownerId}) createHotel;
  final Future<List<HotelModel>> Function({String? ownerId}) getHotelsForOwner;

  const HotelScopeData({
    super.key,
    required this.currentHotel,
    required this.setCurrentHotel,
    required this.createHotel,
    required this.getHotelsForOwner,
    required super.child,
  });

  String? get hotelId => currentHotel?.id;

  @override
  bool updateShouldNotify(HotelScopeData oldWidget) {
    return currentHotel?.id != oldWidget.currentHotel?.id;
  }
}
