/// A hotel is created by an account (owner). All data (bookings, clients, services, etc.) lives under this hotel.
class HotelModel {
  final String? id;
  final String name;
  /// User account id that created/owns this hotel (e.g. Firebase Auth uid when auth is added).
  final String ownerId;
  final DateTime createdAt;

  HotelModel({
    this.id,
    required this.name,
    required this.ownerId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'ownerId': ownerId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory HotelModel.fromFirestore(Map<String, dynamic> data, String id) {
    return HotelModel(
      id: id,
      name: data['name']?.toString() ?? '',
      ownerId: data['ownerId']?.toString() ?? '',
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'])
          : DateTime.now(),
    );
  }

  HotelModel copyWith({
    String? id,
    String? name,
    String? ownerId,
    DateTime? createdAt,
  }) {
    return HotelModel(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
