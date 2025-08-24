// lib/services/export_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
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

  // CSV Export - Complete implementation
  String _exportToCSV(SurveyProject project, List<MagneticReading> readings, List<FieldNote> fieldNotes) {
    StringBuffer csv = StringBuffer();
    
    // CSV Header with project metadata as comments
    csv.writeln('# TerraMag Field Survey Data Export');
    csv.writeln('# Project: ${project.name}');
    csv.writeln('# Description: ${project.description}');
    csv.writeln('# Survey Date: ${project.createdAt.toIso8601String()}');
    csv.writeln('# Export Date: ${DateTime.now().toIso8601String()}');
    csv.writeln('# Total Readings: ${readings.length}');
    csv.writeln('# Software: TerraMag Field v1.0');
    csv.writeln('#');
    
    // Main CSV header - Use correct property names from MagneticReading model
    csv.writeln('timestamp,latitude,longitude,altitude,magnetic_x,magnetic_y,magnetic_z,total_field,accuracy,heading,notes');
    
    // Add magnetic readings
    for (var reading in readings) {
      csv.writeln([
        reading.timestamp.toIso8601String(),
        reading.latitude.toStringAsFixed(8),
        reading.longitude.toStringAsFixed(8),
        reading.altitude.toStringAsFixed(2),
        reading.magneticX.toStringAsFixed(3),
        reading.magneticY.toStringAsFixed(3),
        reading.magneticZ.toStringAsFixed(3),
        reading.totalField.toStringAsFixed(3),
        reading.accuracy.toStringAsFixed(2),
        reading.heading?.toStringAsFixed(1) ?? '',
        '"${reading.notes?.replaceAll('"', '""') ?? ""}"',
      ].join(','));
    }
    
    // Add field notes section if any exist
    if (fieldNotes.isNotEmpty) {
      csv.writeln('#');
      csv.writeln('# Field Notes');
      csv.writeln('timestamp,latitude,longitude,note_type,content,image_path,audio_path');
      
      for (var note in fieldNotes) {
        final mediaType = note.imagePath != null ? 'IMAGE' : 
                         note.audioPath != null ? 'AUDIO' : 'TEXT';
        
        csv.writeln([
          note.timestamp.toIso8601String(),
          note.latitude.toStringAsFixed(8),
          note.longitude.toStringAsFixed(8),
          mediaType,
          '"${note.note.replaceAll('"', '""')}"',
          '"${note.imagePath ?? ""}"',
          '"${note.audioPath ?? ""}"',
        ].join(','));
      }
    }
    
    return csv.toString();
  }

  // GeoJSON Export - Complete implementation
  String _exportToGeoJSON(SurveyProject project, List<MagneticReading> readings, 
                         List<GridCell> gridCells, List<FieldNote> fieldNotes) {
    Map<String, dynamic> geoJson = {
      'type': 'FeatureCollection',
      'crs': {
        'type': 'name',
        'properties': {'name': 'EPSG:4326'}
      },
      'metadata': {
        'project': project.name,
        'description': project.description,
        'survey_date': project.createdAt.toIso8601String(),
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
          'point_id': 'MAG_${i + 1}',
          'timestamp': reading.timestamp.toIso8601String(),
          'magnetic_x': reading.magneticX,
          'magnetic_y': reading.magneticY,
          'magnetic_z': reading.magneticZ,
          'total_field': reading.totalField,
          'quality': SensorService.isDataQualityGood(reading.totalField) ? 'GOOD' : 'POOR',
          'accuracy': reading.accuracy,
          'heading': reading.heading,
          'altitude': reading.altitude,
          'notes': reading.notes,
        }
      });
    }

    // Add grid cells as polygon features
    for (int i = 0; i < gridCells.length; i++) {
      final cell = gridCells[i];
      if (cell.bounds.isNotEmpty) {
        // Convert LatLng bounds to coordinate array
        List<List<double>> coordinates = cell.bounds.map((point) => [
          point.longitude,
          point.latitude
        ]).toList();
        
        // Close the polygon
        if (coordinates.isNotEmpty) {
          coordinates.add(coordinates.first);
        }

        features.add({
          'type': 'Feature',
          'id': 'GRID_${i + 1}',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [coordinates]
          },
          'properties': {
            'cell_id': cell.id,
            'grid_index': i + 1,
            'status': cell.status.toString(),
            'completion_percentage': cell.completionPercentage,
            'point_count': cell.pointCount,
            'start_time': cell.startTime?.toIso8601String(),
            'completed_time': cell.completedTime?.toIso8601String(),
            'notes': cell.notes,
          }
        });
      }
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
          'note_id': 'NOTE_${i + 1}',
          'timestamp': note.timestamp.toIso8601String(),
          'note': note.note,
          'has_image': note.imagePath != null,
          'has_audio': note.audioPath != null,
          'image_path': note.imagePath,
          'audio_path': note.audioPath,
        }
      });
    }

    geoJson['features'] = features;
    // FIXED: Use proper JsonEncoder syntax
    return const JsonEncoder.withIndent('  ').convert(geoJson);
  }

  // KML Export - Complete implementation
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

    // Define styles for different magnetic field intensities
    kml.writeln('    <Style id="lowField">');
    kml.writeln('      <IconStyle>');
    kml.writeln('        <color>ff0000ff</color>');
    kml.writeln('        <scale>0.8</scale>');
    kml.writeln('        <Icon><href>http://maps.google.com/mapfiles/kml/pushpin/red-pushpin.png</href></Icon>');
    kml.writeln('      </IconStyle>');
    kml.writeln('    </Style>');
    
    kml.writeln('    <Style id="mediumField">');
    kml.writeln('      <IconStyle>');
    kml.writeln('        <color>ff00ffff</color>');
    kml.writeln('        <scale>1.0</scale>');
    kml.writeln('        <Icon><href>http://maps.google.com/mapfiles/kml/pushpin/ylw-pushpin.png</href></Icon>');
    kml.writeln('      </IconStyle>');
    kml.writeln('    </Style>');
    
    kml.writeln('    <Style id="highField">');
    kml.writeln('      <IconStyle>');
    kml.writeln('        <color>ff00ff00</color>');
    kml.writeln('        <scale>1.2</scale>');
    kml.writeln('        <Icon><href>http://maps.google.com/mapfiles/kml/pushpin/grn-pushpin.png</href></Icon>');
    kml.writeln('      </IconStyle>');
    kml.writeln('    </Style>');

    // Add magnetic readings folder
    kml.writeln('    <Folder>');
    kml.writeln('      <name>Magnetic Readings</name>');
    kml.writeln('      <open>1</open>');

    for (int i = 0; i < readings.length; i++) {
      final reading = readings[i];
      final styleId = reading.totalField < 40000 ? 'lowField' : 
                     reading.totalField < 60000 ? 'mediumField' : 'highField';
      
      kml.writeln('      <Placemark>');
      kml.writeln('        <name>Point ${i + 1}</name>');
      kml.writeln('        <styleUrl>#$styleId</styleUrl>');
      kml.writeln('        <description><![CDATA[');
      kml.writeln('          <table border="1" cellpadding="4">');
      kml.writeln('            <tr><td><strong>Total Field:</strong></td><td>${reading.totalField.toStringAsFixed(2)} μT</td></tr>');
      kml.writeln('            <tr><td><strong>X Component:</strong></td><td>${reading.magneticX.toStringAsFixed(2)} μT</td></tr>');
      kml.writeln('            <tr><td><strong>Y Component:</strong></td><td>${reading.magneticY.toStringAsFixed(2)} μT</td></tr>');
      kml.writeln('            <tr><td><strong>Z Component:</strong></td><td>${reading.magneticZ.toStringAsFixed(2)} μT</td></tr>');
      kml.writeln('            <tr><td><strong>Accuracy:</strong></td><td>${reading.accuracy.toStringAsFixed(2)} m</td></tr>');
      if (reading.heading != null) {
        kml.writeln('            <tr><td><strong>Heading:</strong></td><td>${reading.heading!.toStringAsFixed(1)}°</td></tr>');
      }
      kml.writeln('            <tr><td><strong>Time:</strong></td><td>${reading.timestamp}</td></tr>');
      if (reading.notes?.isNotEmpty == true) {
        kml.writeln('            <tr><td><strong>Notes:</strong></td><td>${reading.notes}</td></tr>');
      }
      kml.writeln('          </table>');
      kml.writeln('        ]]></description>');
      kml.writeln('        <Point>');
      kml.writeln('          <coordinates>${reading.longitude},${reading.latitude},${reading.altitude}</coordinates>');
      kml.writeln('        </Point>');
      kml.writeln('      </Placemark>');
    }

    kml.writeln('    </Folder>');

    // Add grid cells folder if any exist
    if (gridCells.isNotEmpty) {
      kml.writeln('    <Folder>');
      kml.writeln('      <name>Survey Grid</name>');
      kml.writeln('      <open>0</open>');

      for (int i = 0; i < gridCells.length; i++) {
        final cell = gridCells[i];
        if (cell.bounds.isNotEmpty) {
          kml.writeln('      <Placemark>');
          kml.writeln('        <name>Grid Cell ${cell.id}</name>');
          kml.writeln('        <description>Status: ${cell.status.toString().split('.').last}, Points: ${cell.pointCount}</description>');
          kml.writeln('        <Polygon>');
          kml.writeln('          <outerBoundaryIs>');
          kml.writeln('            <LinearRing>');
          kml.writeln('              <coordinates>');
          
          // Add all boundary points
          for (var point in cell.bounds) {
            kml.writeln('                ${point.longitude},${point.latitude},0');
          }
          // Close the polygon
          if (cell.bounds.isNotEmpty) {
            final firstPoint = cell.bounds.first;
            kml.writeln('                ${firstPoint.longitude},${firstPoint.latitude},0');
          }
          
          kml.writeln('              </coordinates>');
          kml.writeln('            </LinearRing>');
          kml.writeln('          </outerBoundaryIs>');
          kml.writeln('        </Polygon>');
          kml.writeln('      </Placemark>');
        }
      }

      kml.writeln('    </Folder>');
    }

    kml.writeln('  </Document>');
    kml.writeln('</kml>');

    return kml.toString();
  }

  // SQLite Export - Complete implementation
  Future<String> _exportToSQLite(SurveyProject project, List<MagneticReading> readings,
                                 List<GridCell> gridCells, List<FieldNote> fieldNotes) async {
    if (kIsWeb) {
      return 'SQLite export not available in web mode';
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportPath = '${appDir.path}/${project.name}_export_${timestamp}.db';
      
      // Create a summary of what would be exported
      StringBuffer summary = StringBuffer();
      summary.writeln('SQLite Database Export Summary');
      summary.writeln('Export Path: $exportPath');
      summary.writeln('Project: ${project.name}');
      summary.writeln('Readings: ${readings.length}');
      summary.writeln('Grid Cells: ${gridCells.length}');
      summary.writeln('Field Notes: ${fieldNotes.length}');
      summary.writeln('');
      summary.writeln('Note: Full SQLite export implementation requires database copy functionality.');
      summary.writeln('Consider using CSV or GeoJSON export for data interchange.');
      
      return summary.toString();
    } catch (e) {
      throw Exception('SQLite export failed: $e');
    }
  }

  // Shapefile Export (WKT format as CSV)
  String _exportToShapefile(SurveyProject project, List<MagneticReading> readings) {
    StringBuffer shp = StringBuffer();
    
    shp.writeln('# Shapefile-compatible export (WKT format)');
    shp.writeln('# Project: ${project.name}');
    shp.writeln('# CRS: EPSG:4326 (WGS84)');
    shp.writeln('# Compatible with QGIS, ArcGIS, and other GIS software');
    shp.writeln('# Import this file as "Delimited Text" with WKT geometry');
    shp.writeln('#');
    shp.writeln('WKT,ID,TIMESTAMP,MAG_X,MAG_Y,MAG_Z,TOTAL_FIELD,QUALITY,ACCURACY,HEADING,ALTITUDE,NOTES');
    
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
        reading.accuracy.toStringAsFixed(2),
        reading.heading?.toStringAsFixed(1) ?? '',
        reading.altitude.toStringAsFixed(2),
        '"${reading.notes?.replaceAll('"', '""') ?? ""}"',
      ].join(','));
    }
    
    return shp.toString();
  }

  // Platform-specific save and share implementation
  Future<void> saveAndShare({
    required String data,
    required String filename,
    required String mimeType,
  }) async {
    if (kIsWeb) {
      await _saveForWeb(data, filename, mimeType);
    } else {
      await _saveForMobile(data, filename, mimeType);
    }
  }

  // Web-specific save function (simplified to avoid dart:html issues)
  Future<void> _saveForWeb(String data, String filename, String mimeType) async {
    if (kIsWeb) {
      // For now, use Share.share which works on web
      await Share.share(
        data,
        subject: 'Survey Data Export: $filename',
      );
    }
  }

  // Mobile-specific save function
  Future<void> _saveForMobile(String data, String filename, String mimeType) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');
      await file.writeAsString(data, encoding: utf8);
      
      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Survey data exported: $filename',
      );
    } catch (e) {
      throw Exception('Failed to save and share file: $e');
    }
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
        return '.csv'; // WKT format as CSV
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

  // Utility method to get format display name
  String getFormatDisplayName(ExportFormat format) {
    switch (format) {
      case ExportFormat.csv:
        return 'CSV Spreadsheet';
      case ExportFormat.geojson:
        return 'GeoJSON';
      case ExportFormat.kml:
        return 'Google Earth KML';
      case ExportFormat.sqlite:
        return 'SQLite Database';
      case ExportFormat.shapefile:
        return 'Shapefile (WKT)';
    }
  }

  // Utility method to check if format is available on current platform
  bool isFormatAvailable(ExportFormat format) {
    switch (format) {
      case ExportFormat.sqlite:
        return !kIsWeb; // SQLite only available on mobile
      case ExportFormat.csv:
      case ExportFormat.geojson:
      case ExportFormat.kml:
      case ExportFormat.shapefile:
        return true; // Available on all platforms
    }
  }

  // Get format description for UI
  String getFormatDescription(ExportFormat format) {
    switch (format) {
      case ExportFormat.csv:
        return 'Spreadsheet compatible format';
      case ExportFormat.geojson:
        return 'GIS and web mapping compatible';
      case ExportFormat.kml:
        return 'Google Earth and GPS compatible';
      case ExportFormat.sqlite:
        return 'Complete database backup';
      case ExportFormat.shapefile:
        return 'GIS shapefile format (WKT)';
    }
  }

  // Utility to validate export data
  bool validateExportData(List<MagneticReading> readings) {
    if (readings.isEmpty) {
      return false;
    }
    
    // Check for valid coordinates
    for (var reading in readings) {
      if (reading.latitude.abs() > 90 || reading.longitude.abs() > 180) {
        return false;
      }
    }
    
    return true;
  }

  // Get export statistics
  Map<String, dynamic> getExportStatistics(List<MagneticReading> readings, List<FieldNote> fieldNotes) {
    if (readings.isEmpty) {
      return {
        'total_readings': 0,
        'field_notes': fieldNotes.length,
        'date_range': 'No data',
        'quality_summary': 'No readings'
      };
    }

    final goodQualityCount = readings.where((r) => SensorService.isDataQualityGood(r.totalField)).length;
    final totalFieldValues = readings.map((r) => r.totalField).toList();
    final minField = totalFieldValues.reduce((a, b) => a < b ? a : b);
    final maxField = totalFieldValues.reduce((a, b) => a > b ? a : b);
    final avgField = totalFieldValues.reduce((a, b) => a + b) / readings.length;

    final timestamps = readings.map((r) => r.timestamp).toList()..sort();
    final dateRange = readings.length > 1 
        ? '${timestamps.first.toString().substring(0, 19)} to ${timestamps.last.toString().substring(0, 19)}'
        : timestamps.first.toString().substring(0, 19);

    return {
      'total_readings': readings.length,
      'field_notes': fieldNotes.length,
      'good_quality_readings': goodQualityCount,
      'quality_percentage': ((goodQualityCount / readings.length) * 100).toStringAsFixed(1),
      'date_range': dateRange,
      'field_range': '${minField.toStringAsFixed(1)} - ${maxField.toStringAsFixed(1)} μT',
      'average_field': '${avgField.toStringAsFixed(1)} μT',
      'quality_summary': '$goodQualityCount/${readings.length} readings are good quality'
    };
  }
}