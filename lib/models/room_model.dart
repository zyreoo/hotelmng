/// A room in the hotel (e.g. "101", "Suite A"). Stored per hotel.
class RoomModel {
  final String? id;
  final String name;

  RoomModel({this.id, required this.name});

  Map<String, dynamic> toFirestore() => {'name': name};

  factory RoomModel.fromFirestore(Map<String, dynamic> data, String id) {
    return RoomModel(
      id: id,
      name: data['name']?.toString() ?? '',
    );
  }

  RoomModel copyWith({String? id, String? name}) {
    return RoomModel(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }
}
