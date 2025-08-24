// lib/services/sensor_service.dart
import 'dart:math';

class SensorService {
  static double calculateTotalField(double x, double y, double z) {
    return sqrt(x * x + y * y + z * z);
  }

  static bool isDataQualityGood(double totalField) {
    // Basic quality check - typical Earth field is 25,000-65,000 nT
    // For smartphone magnetometers, values are in microTesla (μT)
    // Typical range: 20-70 μT
    return totalField > 20.0 && totalField < 70.0;
  }

  static double calculateInclination(double x, double y, double z) {
    double horizontal = sqrt(x * x + y * y);
    return atan2(z, horizontal) * 180 / pi;
  }

  static double calculateDeclination(double x, double y) {
    return atan2(y, x) * 180 / pi;
  }
}