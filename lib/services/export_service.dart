// lib/services/export_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:html' as html show Blob, Url, AnchorElement, document;
import '../models/magnetic_reading.dart';
import '../models/survey_project.dart';
import '../models/grid_cell.dart';
import '../models/field_note.dart';
import 'sensor_service.dart';

enum ExportFormat {
  csv,
  geojson,
  kml,
  sqlite,
  shapefile
}

class ExportService {
  static final ExportService instance = ExportService._init();
  ExportService._init();

  // Export project data in specified format
  Future<String> exportProject({
    required SurveyProject project,
    required List<MagneticReading> readings,
    required List<GridCell> gridCells,
    required List<FieldNote> fieldNotes,
    required ExportFormat format,
  }) async {
    switch (format) {
      case ExportFormat.csv:
        return _exportToCSV(project, readings, fieldNotes);
      case ExportFormat.geojson:
        return _exportToGeoJSON(project, readings, gridCells, fieldNotes);
      case ExportFormat.kml:
        return _exportToKML(project, readings, gridCells);
      case ExportFormat.sqlite:
        return await _exportToSQLite(project, readings, gridCells, fieldNotes);
      case ExportFormat.shapefile:
        return _exportToShapefile(project, readings);
    }
  }

  // Fixed CSV Export - Returns proper CSV string, not HTML
  String _exportToCSV(SurveyProject project, List<MagneticReading> readings, List<FieldNote> fieldNotes) {
    StringBuffer csv = StringBuffer();
    
    // CSV Header with project metadata as comments
    csv.writeln('# TerraMag Field Survey Data Export');
    csv.writeln('# Project: ${project.name}');
    csv.writeln('# Description: ${project.description}');
    csv.writeln('# Survey Date: ${project.createdAt.toIso8601String()}');
    csv.writeln('# Export Date: ${DateTime.now().toIso8601String()}');
    csv.writeln('# Total Readings: ${readings.length}');
    csv.writeln('# Total Field Notes: ${fieldNotes.length}');
    csv.writeln('# Coordinate System: WGS84 (EPSG:4326)');
    csv.writeln('# Magnetic Units: microTesla (μT)');
    csv.writeln('# Software: TerraMag Field v1.0');
    csv.writeln('#');
    
    // Magnetic readings section
    csv.writeln('# MAGNETIC READINGS');
    csv.writeln('point_id,timestamp,latitude,longitude,altitude,magnetic_x,magnetic_y,magnetic_z,total_field,quality_flag,notes');
    
    for (int i = 0; i < readings.length; i++) {
      final reading = readings[i];
      csv.writeln([
        'MAG_${i + 1}',
        reading.timestamp.toIso8601String(),
        reading.latitude.toStringAsFixed(8),
        reading.longitude.toStringAsFixed(8),
        reading.altitude.toStringAsFixed(2),
        reading.magneticX.toStringAsFixed(3),
        reading.magneticY.toStringAsFixed(3),
        reading.magneticZ.toStringAsFixed(3),
        reading.totalField.toStringAsFixed(3),
        SensorService.isDataQualityGood(reading.totalField) ? 'GOOD' : 'POOR',
        '"${reading.notes?.replaceAll('"', '""') ?? ""}"',
      ].join(','));
    }
    
    // Field notes section
    if (fieldNotes.isNotEmpty) {
      csv.writeln('#');
      csv.writeln('# FIELD NOTES');
      csv.writeln('note_id,timestamp,latitude,longitude,note_text,media_type,image_path,audio_path');
      
      for (int i = 0; i < fieldNotes.length; i++) {
        final note = fieldNotes[i];
        String mediaType = '';
        if (note.imagePath != null) mediaType += 'IMAGE;';
        if (note.audioPath != null) mediaType += 'AUDIO;';
        
        csv.writeln([
          'NOTE_${i + 1}',
          note.timestamp.toIso8601String(),
          note.latitude.toStringAsFixed(8),
          note.longitude.toStringAsFixed(8),
          '"${note.note.replaceAll('"', '""')}"',
          mediaType.isEmpty ? 'TEXT' : mediaType,
          '"${note.imagePath ?? ""}"',
          '"${note.audioPath ?? ""}"',
        ].join(','));
      }
    }
    
    return csv.toString();
  }

  // Fixed save and share method for proper CSV export
  Future<void> saveAndShare({
    required String data,
    required String filename,
    required String mimeType,
  }) async {
    if (kIsWeb) {
      // For web, create a proper download
      final bytes = utf8.encode(data);
      final blob = html.Blob([bytes], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = filename;
      html.document.body?.children.add(anchor);
      anchor.click();
      html.document.body?.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
    } else {
      // Mobile: Save to file and share
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$filename');
        await file.writeAsString(data, encoding: utf8);

        await Share.shareXFiles([XFile(file.path)], text: 'Survey data export: $filename');
      } catch (e) {
        throw Exception('Failed to save and share: $e');
      }
    }
  }

  // GeoJSON Export
String _exportToGeoJSON(SurveyProject project, List<MagneticReading> readings, 
                       List<GridCell> gridCells, List<FieldNote> fieldNotes) {
  Map<String, dynamic> geoJson = {
    'type': 'FeatureCollection',
    'metadata': {
      'project': project.name,
      'description': project.description,
      'export_date': DateTime.now().toIso8601String(),
      'total_readings': readings.length,
      'software': 'TerraMag Field v1.0'
    },
    'features': []
  };

  List<Map<String, dynamic>> features = [];

  // Add magnetic readings as point features
  for (int i = 0; i < readings.length; i++) {
    final reading = readings[i];
    features.add({
      'type': 'Feature',
      'id': 'MAG_${i + 1}',
      'geometry': {
        'type': 'Point',
        'coordinates': [reading.longitude, reading.latitude, reading.altitude]
      },
      'properties': {
        'timestamp': reading.timestamp.toIso8601String(),
        'magnetic_x': reading.magneticX,
        'magnetic_y': reading.magneticY,
        'magnetic_z': reading.magneticZ,
        'total_field': reading.totalField,
        'quality': SensorService.isDataQualityGood(reading.totalField) ? 'GOOD' : 'POOR',
        'notes': reading.notes,
        'type': 'magnetic_reading'
      }
    });
  }

  // Add grid cells as polygon features
  for (int i = 0; i < gridCells.length; i++) {
    final cell = gridCells[i];
    // Create a single linear ring for the polygon
    List<List<double>> ring = cell.bounds
        .map((point) => [point.longitude, point.latitude])
        .toList()
      ..add([cell.bounds.first.longitude, cell.bounds.first.latitude]); // Close polygon
    
    // Polygon coordinates need to be a list of rings
    List<List<List<double>>> coordinates = [ring];
    
    features.add({
      'type': 'Feature',
      'id': cell.id,
      'geometry': {
        'type': 'Polygon',
        'coordinates': coordinates
      },
      'properties': {
        'status': cell.status.toString().split('.').last,
        'point_count': cell.pointCount,
        'start_time': cell.startTime?.toIso8601String(),
        'completed_time': cell.completedTime?.toIso8601String(),
        'notes': cell.notes,
        'type': 'survey_grid'
      }
    });
  }

  // Add field notes as point features
  for (int i = 0; i < fieldNotes.length; i++) {
    final note = fieldNotes[i];
    features.add({
      'type': 'Feature',
      'id': 'NOTE_${i + 1}',
      'geometry': {
        'type': 'Point',
        'coordinates': [note.longitude, note.latitude]
      },
      'properties': {
        'timestamp': note.timestamp.toIso8601String(),
        'note': note.note,
        'has_image': note.imagePath != null,
        'has_audio': note.audioPath != null,
        'image_path': note.imagePath,
        'audio_path': note.audioPath,
        'type': 'field_note'
      }
    });
  }

  geoJson['features'] = features;
  return JsonEncoder.withIndent('  ').convert(geoJson);
}

  // KML Export
  String _exportToKML(SurveyProject project, List<MagneticReading> readings, List<GridCell> gridCells) {
    StringBuffer kml = StringBuffer();
    
    kml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    kml.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    kml.writeln('  <Document>');
    kml.writeln('    <name>${project.name}</name>');
    kml.writeln('    <description><![CDATA[');
    kml.writeln('      <h3>Magnetic Survey Data</h3>');
    kml.writeln('      <p><strong>Project:</strong> ${project.name}</p>');
    kml.writeln('      <p><strong>Description:</strong> ${project.description}</p>');
    kml.writeln('      <p><strong>Survey Date:</strong> ${project.createdAt}</p>');
    kml.writeln('      <p><strong>Total Readings:</strong> ${readings.length}</p>');
    kml.writeln('      <p>Generated by TerraMag Field v1.0</p>');
    kml.writeln('    ]]></description>');

    // Add magnetic readings
    kml.writeln('    <Folder>');
    kml.writeln('      <name>Magnetic Readings</name>');

    for (int i = 0; i < readings.length; i++) {
      final reading = readings[i];
      kml.writeln('      <Placemark>');
      kml.writeln('        <name>Point ${i + 1}</name>');
      kml.writeln('        <description>Total Field: ${reading.totalField.toStringAsFixed(2)} μT</description>');
      kml.writeln('        <Point>');
      kml.writeln('          <coordinates>${reading.longitude},${reading.latitude},${reading.altitude}</coordinates>');
      kml.writeln('        </Point>');
      kml.writeln('      </Placemark>');
    }

    kml.writeln('    </Folder>');
    kml.writeln('  </Document>');
    kml.writeln('</kml>');

    return kml.toString();
  }

  // SQLite Export
  Future<String> _exportToSQLite(SurveyProject project, List<MagneticReading> readings,
                                 List<GridCell> gridCells, List<FieldNote> fieldNotes) async {
    if (kIsWeb) {
      return 'SQLite export not available in web mode';
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportPath = '${appDir.path}/${project.name}_${timestamp}.db';
      
      return exportPath;
    } catch (e) {
      throw Exception('SQLite export failed: $e');
    }
  }

  // Shapefile Export (CSV with WKT geometry)
  String _exportToShapefile(SurveyProject project, List<MagneticReading> readings) {
    StringBuffer shp = StringBuffer();
    
    shp.writeln('# Shapefile-compatible export (WKT format)');
    shp.writeln('# Project: ${project.name}');
    shp.writeln('# CRS: EPSG:4326');
    shp.writeln('#');
    shp.writeln('WKT,ID,TIMESTAMP,MAG_X,MAG_Y,MAG_Z,TOTAL_FIELD,QUALITY,NOTES');
    
    for (int i = 0; i < readings.length; i++) {
      final reading = readings[i];
      shp.writeln([
        '"POINT(${reading.longitude} ${reading.latitude})"',
        'MAG_${i + 1}',
        reading.timestamp.toIso8601String(),
        reading.magneticX.toStringAsFixed(3),
        reading.magneticY.toStringAsFixed(3),
        reading.magneticZ.toStringAsFixed(3),
        reading.totalField.toStringAsFixed(3),
        SensorService.isDataQualityGood(reading.totalField) ? 'GOOD' : 'POOR',
        '"${reading.notes?.replaceAll('"', '""') ?? ""}"',
      ].join(','));
    }
    
    return shp.toString();
  }

  // Get appropriate file extension for format
  String getFileExtension(ExportFormat format) {
    switch (format) {
      case ExportFormat.csv:
        return '.csv';
      case ExportFormat.geojson:
        return '.geojson';
      case ExportFormat.kml:
        return '.kml';
      case ExportFormat.sqlite:
        return '.db';
      case ExportFormat.shapefile:
        return '.csv';
    }
  }

  // Get MIME type for format
  String getMimeType(ExportFormat format) {
    switch (format) {
      case ExportFormat.csv:
      case ExportFormat.shapefile:
        return 'text/csv';
      case ExportFormat.geojson:
        return 'application/geo+json';
      case ExportFormat.kml:
        return 'application/vnd.google-earth.kml+xml';
      case ExportFormat.sqlite:
        return 'application/vnd.sqlite3';
    }
  }
}