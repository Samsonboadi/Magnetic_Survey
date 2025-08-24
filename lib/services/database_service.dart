import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/magnetic_reading.dart';
import '../models/survey_project.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('magnetic_survey.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        createdAt TEXT NOT NULL,
        gridSpacing REAL,
        gridBounds TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE magnetic_readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL NOT NULL,
        magneticX REAL NOT NULL,
        magneticY REAL NOT NULL,
        magneticZ REAL NOT NULL,
        totalField REAL NOT NULL,
        timestamp TEXT NOT NULL,
        notes TEXT,
        projectId INTEGER NOT NULL,
        FOREIGN KEY (projectId) REFERENCES projects (id) ON DELETE CASCADE
      )
    ''');

    // Create a default project
    await db.insert('projects', {
      'name': 'Default Survey',
      'description': 'Default magnetic survey project',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  // Project operations
  Future<int> insertProject(SurveyProject project) async {
    final db = await instance.database;
    return await db.insert('projects', project.toMap());
  }

  Future<List<SurveyProject>> getAllProjects() async {
    final db = await instance.database;
    final result = await db.query('projects', orderBy: 'createdAt DESC');
    return result.map((map) => SurveyProject.fromMap(map)).toList();
  }

  Future<SurveyProject?> getProject(int id) async {
    final db = await instance.database;
    final result = await db.query(
      'projects',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isNotEmpty) {
      return SurveyProject.fromMap(result.first);
    }
    return null;
  }

  Future<void> deleteProject(int projectId) async {
    final db = await instance.database;
    await db.delete('projects', where: 'id = ?', whereArgs: [projectId]);
  }

  // Magnetic reading operations
  Future<int> insertMagneticReading(MagneticReading reading) async {
    final db = await instance.database;
    return await db.insert('magnetic_readings', reading.toMap());
  }

  Future<List<MagneticReading>> getReadingsForProject(int projectId) async {
    final db = await instance.database;
    final result = await db.query(
      'magnetic_readings',
      where: 'projectId = ?',
      whereArgs: [projectId],
      orderBy: 'timestamp ASC',
    );
    return result.map((map) => MagneticReading.fromMap(map)).toList();
  }

  Future<int> getReadingCountForProject(int projectId) async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM magnetic_readings WHERE projectId = ?',
      [projectId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Export functions
  Future<String> exportProjectToCSV(int projectId) async {
    final readings = await getReadingsForProject(projectId);
    final project = await getProject(projectId);
    
    StringBuffer csv = StringBuffer();
    csv.writeln('# TerraMag Field - Magnetic Survey Data Export');
    csv.writeln('# Project: ${project?.name ?? "Unknown"}');
    csv.writeln('# Description: ${project?.description ?? ""}');
    csv.writeln('# Export Date: ${DateTime.now().toIso8601String()}');
    csv.writeln('# Total Points: ${readings.length}');
    csv.writeln('# Data Format: WGS84 coordinates, magnetic field in microTesla (μT)');
    csv.writeln('');
    csv.writeln('latitude,longitude,altitude,magneticX,magneticY,magneticZ,totalField,timestamp,notes');
    
    for (final reading in readings) {
      csv.writeln(
        '${reading.latitude},'
        '${reading.longitude},'
        '${reading.altitude},'
        '${reading.magneticX},'
        '${reading.magneticY},'
        '${reading.magneticZ},'
        '${reading.totalField},'
        '${reading.timestamp.toIso8601String()},'
        '"${reading.notes ?? ""}"'
      );
    }
    
    return csv.toString();
  }

  Future<void> initDatabase() async {
    await database; // This will initialize the database
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
    }
  }
}