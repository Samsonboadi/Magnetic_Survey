class SurveyProject {
  final int? id;
  final String name;
  final String description;
  final DateTime createdAt;
  final double? gridSpacing;
  final String? boundaryPoints; // Changed from gridBounds to boundaryPoints

  SurveyProject({
    this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    this.gridSpacing,
    this.boundaryPoints, // Updated parameter name
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'gridSpacing': gridSpacing,
      'boundaryPoints': boundaryPoints, // Updated to match database column
    };
  }

  factory SurveyProject.fromMap(Map<String, dynamic> map) {
    return SurveyProject(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      createdAt: DateTime.parse(map['createdAt']),
      gridSpacing: map['gridSpacing'],
      boundaryPoints: map['boundaryPoints'], // Updated to match database column
    );
  }
}