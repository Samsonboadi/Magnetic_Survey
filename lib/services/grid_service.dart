// lib/services/grid_service.dart
import 'package:latlong2/latlong.dart';
import '../models/grid_cell.dart';

class GridService {
  static List<GridCell> createRegularGrid({
    required LatLng center,
    required double spacing, // in degrees
    required int rows,
    required int cols,
  }) {
    List<GridCell> cells = [];
    
    double startLat = center.latitude - (rows - 1) * spacing / 2;
    double startLon = center.longitude - (cols - 1) * spacing / 2;
    
    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        LatLng cellCenter = LatLng(
          startLat + i * spacing,
          startLon + j * spacing,
        );
        
        List<LatLng> bounds = _createCellBounds(cellCenter, spacing);
        
        cells.add(GridCell(
          id: '${i}_${j}',
          centerLat: cellCenter.latitude,
          centerLon: cellCenter.longitude,
          bounds: bounds,
        ));
      }
    }
    
    return cells;
  }

  static List<LatLng> _createCellBounds(LatLng center, double spacing) {
    double halfSpacing = spacing / 2;
    return [
      LatLng(center.latitude - halfSpacing, center.longitude - halfSpacing),
      LatLng(center.latitude - halfSpacing, center.longitude + halfSpacing),
      LatLng(center.latitude + halfSpacing, center.longitude + halfSpacing),
      LatLng(center.latitude + halfSpacing, center.longitude - halfSpacing),
    ];
  }

  static List<GridCell> optimizeSurveyPath(List<GridCell> cells) {
    // Simple optimization: snake pattern
    List<GridCell> optimized = [];
    List<List<GridCell>> rows = [];
    
    // Group cells by row (assuming regular grid)
    Map<String, List<GridCell>> rowMap = {};
    for (GridCell cell in cells) {
      String rowId = cell.id.split('_')[0];
      if (!rowMap.containsKey(rowId)) {
        rowMap[rowId] = [];
      }
      rowMap[rowId]!.add(cell);
    }
    
    // Sort each row by column
    for (String rowId in rowMap.keys) {
      rowMap[rowId]!.sort((a, b) => 
        int.parse(a.id.split('_')[1]).compareTo(int.parse(b.id.split('_')[1]))
      );
      rows.add(rowMap[rowId]!);
    }
    
    // Create snake pattern
    for (int i = 0; i < rows.length; i++) {
      if (i % 2 == 0) {
        optimized.addAll(rows[i]);
      } else {
        optimized.addAll(rows[i].reversed);
      }
    }
    
    return optimized;
  }

  static double calculateGridCoverage(List<GridCell> cells) {
    int completed = cells.where((cell) => cell.status == GridCellStatus.completed).length;
    return cells.isEmpty ? 0.0 : (completed / cells.length) * 100;
  }
}

