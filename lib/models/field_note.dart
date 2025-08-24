class FieldNote {
  final int? id;
  final double latitude;
  final double longitude;
  final String note;
  final DateTime timestamp;
  final String? audioPath;
  final String? imagePath;
  final int projectId;

  FieldNote({
    this.id,
    required this.latitude,
    required this.longitude,
    required this.note,
    required this.timestamp,
    this.audioPath,
    this.imagePath,
    required this.projectId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'note': note,
      'timestamp': timestamp.toIso8601String(),
      'audioPath': audioPath,
      'imagePath': imagePath,
      'projectId': projectId,
    };
  }

  factory FieldNote.fromMap(Map<String, dynamic> map) {
    return FieldNote(
      id: map['id'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      note: map['note'],
      timestamp: DateTime.parse(map['timestamp']),
      audioPath: map['audioPath'],
      imagePath: map['imagePath'],
      projectId: map['projectId'],
    );
  }
}