// lib/models/field_note.dart
class FieldNote {
  final int? id;
  final double latitude;
  final double longitude;
  final String note;
  final String? imagePath;
  final String? audioPath;
  final DateTime timestamp;
  final int projectId;

  FieldNote({
    this.id,
    required this.latitude,
    required this.longitude,
    required this.note,
    this.imagePath,
    this.audioPath,
    required this.timestamp,
    required this.projectId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'note': note,
      'imagePath': imagePath,
      'audioPath': audioPath,
      'timestamp': timestamp.toIso8601String(),
      'projectId': projectId,
    };
  }

  factory FieldNote.fromMap(Map<String, dynamic> map) {
    return FieldNote(
      id: map['id'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      note: map['note'],
      imagePath: map['imagePath'],
      audioPath: map['audioPath'],
      timestamp: DateTime.parse(map['timestamp']),
      projectId: map['projectId'],
    );
  }
}