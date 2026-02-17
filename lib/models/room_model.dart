/// A room in the hotel (e.g. "101", "Suite A"). Stored per hotel.
class RoomModel {
  final String? id;
  final String name;

  /// Housekeeping status: clean | cleaning | dirty | out_of_order
  final String housekeepingStatus;

  /// Freeform tags, e.g. ['Sea view', 'Ground floor', 'Accessible']
  final List<String> tags;

  static const List<String> housekeepingStatuses = [
    'clean',
    'cleaning',
    'dirty',
    'out_of_order',
  ];

  static const Map<String, String> housekeepingLabels = {
    'clean': 'Clean',
    'cleaning': 'Cleaning',
    'dirty': 'Dirty',
    'out_of_order': 'Out of order',
  };

  RoomModel({
    this.id,
    required this.name,
    this.housekeepingStatus = 'clean',
    this.tags = const [],
  });

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'housekeepingStatus': housekeepingStatus,
    'tags': tags,
  };

  factory RoomModel.fromFirestore(Map<String, dynamic> data, String id) {
    return RoomModel(
      id: id,
      name: data['name']?.toString() ?? '',
      housekeepingStatus: data['housekeepingStatus']?.toString() ?? 'clean',
      tags: data['tags'] != null
          ? List<String>.from(data['tags'] as List)
          : const [],
    );
  }

  RoomModel copyWith({
    String? id,
    String? name,
    String? housekeepingStatus,
    List<String>? tags,
  }) {
    return RoomModel(
      id: id ?? this.id,
      name: name ?? this.name,
      housekeepingStatus: housekeepingStatus ?? this.housekeepingStatus,
      tags: tags ?? this.tags,
    );
  }
}
