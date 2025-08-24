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
import 'package:flutter/material.dart';
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

  // CSV Export with enhanced formatting
  String _exportToCSV(SurveyProject project, List<MagneticReading> readings, List<FieldNote> fieldNotes) {
    StringBuffer csv = StringBuffer();
    
    // Header with metadata
    csv.writeln('# TerraMag Field Survey Data Export');
    csv.writeln('# Export Format: CSV');
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
        '"${reading.notes ?? ""}"',
      ].join(','));
    }
    
    // Field notes section
    if (fieldNotes.isNotEmpty) {
      csv.writeln('#');
      csv.writeln('# FIELD NOTES');
      csv.writeln('note_id,timestamp,latitude,longitude,note_text,media_type');
      
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
          '"${note.note.replaceAll('"', '""')}"',  // Escape quotes
          mediaType.isEmpty ? 'TEXT' : mediaType,
        ].join(','));
      }
    }
    
    return csv.toString();
  }

  // GeoJSON Export with feature collection
  String _exportToGeoJSON(SurveyProject project, List<MagneticReading> readings, 
                         List<GridCell> gridCells, List<FieldNote> fieldNotes) {
    Map<String, dynamic> geoJson = {
      'type': 'FeatureCollection',
      'metadata': {
        'name': project.name,
        'description': project.description,
        'created': project.createdAt.toIso8601String(),
        'exported': DateTime.now().toIso8601String(),
        'software': 'TerraMag Field v1.0',
        'crs': 'EPSG:4326',
        'units': 'microTesla'
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
    for (GridCell cell in gridCells) {
      features.add({
        'type': 'Feature',
        'id': 'CELL_${cell.id}',
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            cell.bounds.map((point) => [point.longitude, point.latitude]).toList()
              ..add([cell.bounds.first.longitude, cell.bounds.first.latitude]) // Close polygon
          ]
        },
        'properties': {
          'cell_id': cell.id,
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
          'type': 'field_note'
        }
      });
    }

    geoJson['features'] = features;
    return JsonEncoder.withIndent('  ').convert(geoJson);
  }

  // KML Export for Google Earth
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

    // Styles for different elements
    kml.writeln(_getKMLStyles());

    // Folder for magnetic readings
    kml.writeln('    <Folder>');
    kml.writeln('      <name>Magnetic Readings</name>');
    kml.writeln('      <description>Survey data points with magnetic field measurements</description>');

    for (int i = 0; i < readings.length; i++) {
      final reading = readings[i];
      bool isGoodQuality = SensorService.isDataQualityGood(reading.totalField);
      
      kml.writeln('      <Placemark>');
      kml.writeln('        <name>Point ${i + 1}</name>');
      kml.writeln('        <description><![CDATA[');
      kml.writeln('          <table>');
      kml.writeln('            <tr><td><b>Timestamp:</b></td><td>${reading.timestamp}</td></tr>');
      kml.writeln('            <tr><td><b>Total Field:</b></td><td>${reading.totalField.toStringAsFixed(3)} μT</td></tr>');
      kml.writeln('            <tr><td><b>Magnetic X:</b></td><td>${reading.magneticX.toStringAsFixed(3)} μT</td></tr>');
      kml.writeln('            <tr><td><b>Magnetic Y:</b></td><td>${reading.magneticY.toStringAsFixed(3)} μT</td></tr>');
      kml.writeln('            <tr><td><b>Magnetic Z:</b></td><td>${reading.magneticZ.toStringAsFixed(3)} μT</td></tr>');
      kml.writeln('            <tr><td><b>Quality:</b></td><td>${isGoodQuality ? "Good" : "Poor"}</td></tr>');
      if (reading.notes != null && reading.notes!.isNotEmpty) {
        kml.writeln('            <tr><td><b>Notes:</b></td><td>${reading.notes}</td></tr>');
      }
      kml.writeln('          </table>');
      kml.writeln('        ]]></description>');
      kml.writeln('        <styleUrl>#${isGoodQuality ? "goodReading" : "poorReading"}</styleUrl>');
      kml.writeln('        <Point>');
      kml.writeln('          <coordinates>${reading.longitude},${reading.latitude},${reading.altitude}</coordinates>');
      kml.writeln('        </Point>');
      kml.writeln('      </Placemark>');
    }
    
    kml.writeln('    </Folder>');

    // Folder for grid cells
    if (gridCells.isNotEmpty) {
      kml.writeln('    <Folder>');
      kml.writeln('      <name>Survey Grid</name>');
      kml.writeln('      <description>Survey grid cells with coverage status</description>');

      for (GridCell cell in gridCells) {
        String styleName = '';
        switch (cell.status) {
          case GridCellStatus.completed:
            styleName = 'completedCell';
            break;
          case GridCellStatus.inProgress:
            styleName = 'inProgressCell';
            break;
          case GridCellStatus.notStarted:
          default:
            styleName = 'notStartedCell';
            break;
        }

        kml.writeln('      <Placemark>');
        kml.writeln('        <name>Cell ${cell.id}</name>');
        kml.writeln('        <description><![CDATA[');
        kml.writeln('          <table>');
        kml.writeln('            <tr><td><b>Status:</b></td><td>${cell.status.toString().split('.').last}</td></tr>');
        kml.writeln('            <tr><td><b>Points Collected:</b></td><td>${cell.pointCount}</td></tr>');
        if (cell.startTime != null) {
          kml.writeln('            <tr><td><b>Started:</b></td><td>${cell.startTime}</td></tr>');
        }
        if (cell.completedTime != null) {
          kml.writeln('            <tr><td><b>Completed:</b></td><td>${cell.completedTime}</td></tr>');
        }
        if (cell.notes != null && cell.notes!.isNotEmpty) {
          kml.writeln('            <tr><td><b>Notes:</b></td><td>${cell.notes}</td></tr>');
        }
        kml.writeln('          </table>');
        kml.writeln('        ]]></description>');
        kml.writeln('        <styleUrl>#$styleName</styleUrl>');
        kml.writeln('        <Polygon>');
        kml.writeln('          <outerBoundaryIs>');
        kml.writeln('            <LinearRing>');
        kml.writeln('              <coordinates>');
        
        // Add polygon coordinates
        for (var point in cell.bounds) {
          kml.writeln('                ${point.longitude},${point.latitude},0');
        }
        // Close the polygon
        var firstPoint = cell.bounds.first;
        kml.writeln('                ${firstPoint.longitude},${firstPoint.latitude},0');
        
        kml.writeln('              </coordinates>');
        kml.writeln('            </LinearRing>');
        kml.writeln('          </outerBoundaryIs>');
        kml.writeln('        </Polygon>');
        kml.writeln('      </Placemark>');
      }
      
      kml.writeln('    </Folder>');
    }

    kml.writeln('  </Document>');
    kml.writeln('</kml>');

    return kml.toString();
  }

  String _getKMLStyles() {
    return '''
    <!-- Styles for magnetic readings -->
    <Style id="goodReading">
      <IconStyle>
        <color>ff00ff00</color>
        <scale>0.8</scale>
        <Icon>
          <href>http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png</href>
        </Icon>
      </IconStyle>
    </Style>
    
    <Style id="poorReading">
      <IconStyle>
        <color>ff0000ff</color>
        <scale>0.8</scale>
        <Icon>
          <href>http://maps.google.com/mapfiles/kml/shapes/placemark_circle.png</href>
        </Icon>
      </IconStyle>
    </Style>

    <!-- Styles for grid cells -->
    <Style id="completedCell">
      <PolyStyle>
        <color>4000ff00</color>
        <outline>1</outline>
      </PolyStyle>
      <LineStyle>
        <color>ff00ff00</color>
        <width>2</width>
      </LineStyle>
    </Style>
    
    <Style id="inProgressCell">
      <PolyStyle>
        <color>4000ffff</color>
        <outline>1</outline>
      </PolyStyle>
      <LineStyle>
        <color>ff00ffff</color>
        <width>2</width>
      </LineStyle>
    </Style>
    
    <Style id="notStartedCell">
      <PolyStyle>
        <color>400000ff</color>
        <outline>1</outline>
      </PolyStyle>
      <LineStyle>
        <color>ff0000ff</color>
        <width>2</width>
      </LineStyle>
    </Style>
''';
  }

  // SQLite Export (copy database file)
  Future<String> _exportToSQLite(SurveyProject project, List<MagneticReading> readings,
                                 List<GridCell> gridCells, List<FieldNote> fieldNotes) async {
    if (kIsWeb) {
      return 'SQLite export not available in web mode';
    }

    try {
      // Get the app's database file
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = '${appDir.path}/magnetic_survey.db';
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        throw Exception('Database file not found');
      }

      // Create export filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportPath = '${appDir.path}/${project.name}_${timestamp}.db';
      
      // Copy database file
      await dbFile.copy(exportPath);
      
      return exportPath;
    } catch (e) {
      throw Exception('SQLite export failed: $e');
    }
  }

  // Simplified Shapefile export (CSV with WKT geometry)
  String _exportToShapefile(SurveyProject project, List<MagneticReading> readings) {
    StringBuffer shp = StringBuffer();
    
    // Header
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
        '"${reading.notes ?? ""}"',
      ].join(','));
    }
    
    return shp.toString();
  }

  // Save and share exported data
  Future<void> saveAndShare({
    required String data,
    required String filename,
    required String mimeType,
  }) async {
    if (kIsWeb) {
      // Web: Use Share API or download
      await Share.share(data, subject: filename);
    } else {
      // Mobile: Save to file and share
      try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$filename');
        await file.writeAsString(data);

        await Share.shareXFiles([XFile(file.path)], text: 'Survey data export');
      } catch (e) {
        throw Exception('Failed to save and share: $e');
      }
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
        return '.csv'; // WKT format in CSV
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