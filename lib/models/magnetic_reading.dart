class MagneticReading {
  final int? id;
  final double latitude;
  final double longitude;
  final double altitude;
  final double magneticX;
  final double magneticY;
  final double magneticZ;
  final double totalField;
  final DateTime timestamp;
  final String? notes;
  final int projectId;

  MagneticReading({
    this.id,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.magneticX,
    required this.magneticY,
    required this.magneticZ,
    required this.totalField,
    required this.timestamp,
    this.notes,
    required this.projectId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'magneticX': magneticX,
      'magneticY': magneticY,
      'magneticZ': magneticZ,
      'totalField': totalField,
      'timestamp': timestamp.toIso8601String(),
      'notes': notes,
      'projectId': projectId,
    };
  }

  factory MagneticReading.fromMap(Map<String, dynamic> map) {
    return MagneticReading(
      id: map['id'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      altitude: map['altitude'],
      magneticX: map['magneticX'],
      magneticY: map['magneticY'],
      magneticZ: map['magneticZ'],
      totalField: map['totalField'],
      timestamp: DateTime.parse(map['timestamp']),
      notes: map['notes'],
      projectId: map['projectId'],
    );
  }
}