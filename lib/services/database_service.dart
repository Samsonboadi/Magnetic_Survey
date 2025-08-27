// lib/services/database_service.dart
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/survey_project.dart';
import '../models/magnetic_reading.dart';
import '../models/field_note.dart';

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

  return await openDatabase(
    path,
    version: 3, // UPDATED: Increment version to trigger migration
    onCreate: _createDB,
    onUpgrade: _upgradeDB,
  );
}


Future<void> _createDB(Database db, int version) async {
  // Projects table
  await db.execute('''
    CREATE TABLE projects (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      description TEXT,
      createdAt TEXT NOT NULL,
      gridSpacing REAL DEFAULT 10.0,
      boundaryPoints TEXT
    )
  ''');

    // Magnetic readings table
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
      accuracy REAL DEFAULT 5.0,
      heading REAL,
      FOREIGN KEY (projectId) REFERENCES projects (id) ON DELETE CASCADE
    )
  ''');

    // Field notes table
  await db.execute('''
    CREATE TABLE field_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      note TEXT NOT NULL,
      imagePath TEXT,
      audioPath TEXT,
      timestamp TEXT NOT NULL,
      projectId INTEGER NOT NULL,
      FOREIGN KEY (projectId) REFERENCES projects (id) ON DELETE CASCADE
    )
  ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_magnetic_project ON magnetic_readings(projectId)');
    await db.execute('CREATE INDEX idx_magnetic_timestamp ON magnetic_readings(timestamp)');
    await db.execute('CREATE INDEX idx_field_notes_project ON field_notes(projectId)');
  }

Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    // Add field notes table if upgrading from version 1
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        note TEXT NOT NULL,
        imagePath TEXT,
        audioPath TEXT,
        timestamp TEXT NOT NULL,
        projectId INTEGER NOT NULL,
        FOREIGN KEY (projectId) REFERENCES projects (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_field_notes_project ON field_notes(projectId)');
  }
  
  if (oldVersion < 3) {
    // UPDATED: Add missing columns to existing magnetic_readings table
    try {
      await db.execute('ALTER TABLE magnetic_readings ADD COLUMN accuracy REAL DEFAULT 5.0');
    } catch (e) {
      print('Column accuracy might already exist: $e');
    }
    
    try {
      await db.execute('ALTER TABLE magnetic_readings ADD COLUMN heading REAL');
    } catch (e) {
      print('Column heading might already exist: $e');
    }
  }
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

  // Field notes operations
  Future<int> insertFieldNote(FieldNote fieldNote) async {
    final db = await instance.database;
    return await db.insert('field_notes', fieldNote.toMap());
  }

  Future<List<FieldNote>> getFieldNotesForProject(int projectId) async {
    final db = await instance.database;
    final result = await db.query(
      'field_notes',
      where: 'projectId = ?',
      whereArgs: [projectId],
      orderBy: 'timestamp ASC',
    );
    return result.map((map) => FieldNote.fromMap(map)).toList();
  }

  Future<void> deleteFieldNote(int id) async {
    final db = await instance.database;
    await db.delete('field_notes', where: 'id = ?', whereArgs: [id]);
  }

  // Export functions
  Future<String> exportProjectToCSV(int projectId) async {
    final readings = await getReadingsForProject(projectId);
    final project = await getProject(projectId);
    final fieldNotes = await getFieldNotesForProject(projectId);
    
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
    await database;
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
    }
  }
}