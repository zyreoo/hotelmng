import 'package:cloud_firestore/cloud_firestore.dart';

class ShiftModel {
  final String? id;
  final String employeeId;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String role;

  ShiftModel({
    this.id,
    required this.employeeId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.role,
  });

  factory ShiftModel.fromFirestore(Map<String, dynamic> data, String id) {
    return ShiftModel(
      id: id,
      employeeId: data['employeeId'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      startTime: data['startTime'] ?? '',
      endTime: data['endTime'] ?? '',
      role: data['role'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'employeeId': employeeId,
      'date': Timestamp.fromDate(date),
      'startTime': startTime,
      'endTime': endTime,
      'role': role,
    };
  }
}
