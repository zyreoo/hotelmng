class EmployerModel {
  final String? id;
  final String name;
  final String phone;
  final String email;
  final String role;
  final String department;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  EmployerModel({
    this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.department,
    required this.status,
    DateTime? updatedAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'department': department,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // Create from Firestore document
  factory EmployerModel.fromFirestore(Map<String, dynamic> data, String id) {
    return EmployerModel(
      id: id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? '',
      department: data['department'] ?? '',
      status: data['status'] ?? '',
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'])
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? DateTime.parse(data['updatedAt'])
          : DateTime.now(),
    );
  }

  EmployerModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? role,
    String? department,
    String? status,
    DateTime? updatedAt,
    DateTime? createdAt,
  }) {
    return EmployerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      role: role ?? this.role,
      department: department ?? this.department,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
