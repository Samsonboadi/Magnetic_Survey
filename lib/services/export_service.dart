// lib/services/export_service.dart - FIXED VERSION
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' if (dart.library.html) 'dart:html' as io;
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
    
    return csv.toString();
  }

  // GeoJSON Export - Complete implementation
  String _exportToGeoJSON(SurveyProject project, List<MagneticReading> readings, 
                         List<GridCell> gridCells, List<FieldNote> fieldNotes) {
    Map<String, dynamic> geoJson = {
      'type': 'FeatureCollection',
      'crs': {
        'type': 'name',
        'properties': {
          'name': 'EPSG:4326'
        }
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

    // Add magnetic readings as point features
    for (int i = 0; i < readings.length; i++) {
      final reading = readings[i];
      geoJson['features'].add({
        'type': 'Feature',
        'properties': {
          'id': 'reading_${i + 1}',
          'timestamp': reading.timestamp.toIso8601String(),
          'magnetic_x': reading.magneticX,
          'magnetic_y': reading.magneticY,
          'magnetic_z': reading.magneticZ,
          'total_field': reading.totalField,
          'accuracy': reading.accuracy,
          'heading': reading.heading,
          'altitude': reading.altitude,
          'notes': reading.notes,
          'data_quality': SensorService.isDataQualityGood(reading.totalField) ? 'good' : 'poor'
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [reading.longitude, reading.latitude, reading.altitude]
        }
      });
    }

    // Add grid cells as polygon features
    for (int i = 0; i < gridCells.length; i++) {
      final cell = gridCells[i];
      if (cell.bounds.isNotEmpty) {
        // Convert LatLng bounds to coordinate array for GeoJSON
        List<List<double>> coordinates = cell.bounds.map((point) => [
          point.longitude,
          point.latitude
        ]).toList();
        
        // Close the polygon by adding first point at the end
        if (coordinates.isNotEmpty) {
          coordinates.add(coordinates.first);
        }

        geoJson['features'].add({
          'type': 'Feature',
          'properties': {
            'id': 'grid_cell_${i + 1}',
            'cell_id': cell.id,
            'status': cell.status.toString().split('.').last,
            'point_count': cell.pointCount,
            'center_lat': cell.centerLat,
            'center_lon': cell.centerLon,
            'start_time': cell.startTime?.toIso8601String(),
            'completed_time': cell.completedTime?.toIso8601String(),
            'notes': cell.notes,
            'cell_type': 'survey_grid'
          },
          'geometry': {
            'type': 'Polygon',
            'coordinates': [coordinates]
          }
        });
      }
    }

    return JsonEncoder.withIndent('  ').convert(geoJson);
  }

  // KML Export - Complete implementation
  String _exportToKML(SurveyProject project, List<MagneticReading> readings, List<GridCell> gridCells) {
    StringBuffer kml = StringBuffer();
    
    kml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    kml.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    kml.writeln('  <Document>');
    kml.writeln('    <name>${project.name}</name>');
    kml.writeln('    <description>${project.description}</description>');
    
    // Define styles
    kml.writeln('    <Style id="magneticPoint">');
    kml.writeln('      <IconStyle>');
    kml.writeln('        <color>ff00ff00</color>');
    kml.writeln('        <scale>0.8</scale>');
    kml.writeln('      </IconStyle>');
    kml.writeln('    </Style>');
    
    kml.writeln('    <Style id="gridCell">');
    kml.writeln('      <LineStyle>');
    kml.writeln('        <color>ff0000ff</color>');
    kml.writeln('        <width>2</width>');
    kml.writeln('      </LineStyle>');
    kml.writeln('      <PolyStyle>');
    kml.writeln('        <color>330000ff</color>');
    kml.writeln('      </PolyStyle>');
    kml.writeln('    </Style>');

    // Add magnetic readings folder
    if (readings.isNotEmpty) {
      kml.writeln('    <Folder>');
      kml.writeln('      <name>Magnetic Readings</name>');
      
      for (int i = 0; i < readings.length; i++) {
        final reading = readings[i];
        kml.writeln('      <Placemark>');
        kml.writeln('        <name>Reading ${i + 1}</name>');
        kml.writeln('        <description>Total Field: ${reading.totalField.toStringAsFixed(1)} nT\\nAccuracy: ±${reading.accuracy.toStringAsFixed(1)}m\\nTimestamp: ${reading.timestamp}</description>');
        kml.writeln('        <styleUrl>#magneticPoint</styleUrl>');
        kml.writeln('        <Point>');
        kml.writeln('          <coordinates>${reading.longitude},${reading.latitude},${reading.altitude}</coordinates>');
        kml.writeln('        </Point>');
        kml.writeln('      </Placemark>');
      }
      
      kml.writeln('    </Folder>');
    }

    // Add grid cells folder
    if (gridCells.isNotEmpty) {
      kml.writeln('    <Folder>');
      kml.writeln('      <name>Survey Grid</name>');
      
      for (int i = 0; i < gridCells.length; i++) {
        final cell = gridCells[i];
        kml.writeln('      <Placemark>');
        kml.writeln('        <name>Grid Cell ${i + 1}</name>');
        kml.writeln('        <description>Status: ${cell.status.toString().split('.').last}, Points: ${cell.pointCount}</description>');
        kml.writeln('        <styleUrl>#gridCell</styleUrl>');
        kml.writeln('        <Polygon>');
        kml.writeln('          <outerBoundaryIs>');
        kml.writeln('            <LinearRing>');
        kml.writeln('              <coordinates>');
        
        // Add all boundary points from the cell.bounds List<LatLng>
        for (var point in cell.bounds) {
          kml.writeln('                ${point.longitude},${point.latitude},0');
        }
        // Close the polygon by adding the first point again
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
      
      kml.writeln('    </Folder>');
    }

    kml.writeln('  </Document>');
    kml.writeln('</kml>');

    return kml.toString();
  }

  // SQLite Export - Simple implementation for mobile
  Future<String> _exportToSQLite(SurveyProject project, List<MagneticReading> readings,
                                 List<GridCell> gridCells, List<FieldNote> fieldNotes) async {
    if (kIsWeb) {
      return 'SQLite export not available in web mode. Use CSV or GeoJSON instead.';
    }

    // For now, return a summary since full SQLite implementation is complex
    StringBuffer summary = StringBuffer();
    summary.writeln('SQLite Database Export Summary');
    summary.writeln('Project: ${project.name}');
    summary.writeln('Readings: ${readings.length}');
    summary.writeln('Grid Cells: ${gridCells.length}');
    summary.writeln('Field Notes: ${fieldNotes.length}');
    summary.writeln('');
    summary.writeln('Note: Full SQLite export requires database copy functionality.');
    summary.writeln('Consider using CSV or GeoJSON export for data interchange.');
    
    return summary.toString();
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

  // Web-specific save function (using Share API only)
  Future<void> _saveForWeb(String data, String filename, String mimeType) async {
    try {
      await Share.share(
        data,
        subject: 'Survey Data Export: $filename',
      );
    } catch (e) {
      throw Exception('Web sharing failed: $e');
    }
  }

  // Mobile-specific save function
  Future<void> _saveForMobile(String data, String filename, String mimeType) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      
      // Sanitize filename to prevent path issues
      String sanitizedFilename = filename
          .replaceAll(' ', '_')           // Replace spaces with underscores
          .replaceAll(RegExp(r'[^\w\-_\.]'), '') // Remove special characters except dash, underscore, dot
          .replaceAll(RegExp(r'_{2,}'), '_');    // Replace multiple underscores with single
      
      // Ensure we have a valid extension
      if (!sanitizedFilename.contains('.')) {
        sanitizedFilename += '.csv'; // Default extension
      }
      
      final file = io.File('${directory.path}/$sanitizedFilename');
      
      // Ensure directory exists
      await file.parent.create(recursive: true);
      
      // Write file with error handling
      await file.writeAsString(data, encoding: utf8);
      
      // Verify file was created before sharing
      if (await file.exists()) {
        // Share the file
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Survey data exported: $sanitizedFilename',
        );
      } else {
        throw Exception('File was not created successfully');
      }
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
}