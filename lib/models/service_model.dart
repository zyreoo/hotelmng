/// A service offered by the hotel (breakfast, spa, sauna, etc.).
/// Stored in Firestore so staff can add/edit/delete any service.
class ServiceModel {
  final String? id;
  final String name;
  /// Price in smallest currency unit (e.g. cents). Stored as int.
  final int price;
  final String? category; // optional, e.g. "meal", "wellness"
  final String? description;

  ServiceModel({
    this.id,
    required this.name,
    required this.price,
    this.category,
    this.description,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'name': name.trim(),
      'price': price,
      if (category != null && category!.trim().isNotEmpty) 'category': category!.trim(),
      if (description != null && description!.trim().isNotEmpty) 'description': description!.trim(),
    };
  }

  factory ServiceModel.fromFirestore(Map<String, dynamic> data, String id) {
    return ServiceModel(
      id: id,
      name: data['name']?.toString() ?? '',
      price: (data['price'] is int)
          ? data['price'] as int
          : int.tryParse(data['price']?.toString() ?? '0') ?? 0,
      category: data['category']?.toString(),
      description: data['description']?.toString(),
    );
  }

  ServiceModel copyWith({
    String? id,
    String? name,
    int? price,
    String? category,
    String? description,
  }) {
    return ServiceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      category: category ?? this.category,
      description: description ?? this.description,
    );
  }
}

/// One line item: a selected service on a booking (with quantity and snapshot price).
class BookingServiceItem {
  final String serviceId;
  final String name;
  final int unitPrice;
  final int quantity;

  BookingServiceItem({
    required this.serviceId,
    required this.name,
    required this.unitPrice,
    this.quantity = 1,
  });

  int get lineTotal => unitPrice * quantity;

  Map<String, dynamic> toMap() {
    return {
      'serviceId': serviceId,
      'name': name,
      'unitPrice': unitPrice,
      'quantity': quantity,
    };
  }

  static BookingServiceItem fromMap(Map<String, dynamic> data) {
    return BookingServiceItem(
      serviceId: data['serviceId']?.toString() ?? '',
      name: data['name']?.toString() ?? '',
      unitPrice: (data['unitPrice'] is int)
          ? data['unitPrice'] as int
          : int.tryParse(data['unitPrice']?.toString() ?? '0') ?? 0,
      quantity: (data['quantity'] is int)
          ? data['quantity'] as int
          : int.tryParse(data['quantity']?.toString() ?? '1') ?? 1,
    );
  }
}
