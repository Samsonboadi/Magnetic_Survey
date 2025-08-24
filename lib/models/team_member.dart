// lib/models/team_member.dart
import 'package:flutter/material.dart';  // This import was missing!
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;  // For Random class

class TeamMember {
  final String id;
  final String name;
  final String deviceId;
  LatLng? currentPosition;
  double? heading;
  DateTime lastUpdate;
  bool isOnline;
  Color markerColor;
  List<String> assignedCells;

  TeamMember({
    required this.id,
    required this.name,
    required this.deviceId,
    this.currentPosition,
    this.heading,
    DateTime? lastUpdate,
    this.isOnline = false,
    required this.markerColor,
    this.assignedCells = const [],
  }) : lastUpdate = lastUpdate ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'deviceId': deviceId,
      'currentPosition': currentPosition != null 
          ? {'lat': currentPosition!.latitude, 'lon': currentPosition!.longitude}
          : null,
      'heading': heading,
      'lastUpdate': lastUpdate.toIso8601String(),
      'isOnline': isOnline,
      'markerColor': markerColor.value,
      'assignedCells': assignedCells,
    };
  }

  factory TeamMember.fromMap(Map<String, dynamic> map) {
    return TeamMember(
      id: map['id'],
      name: map['name'],
      deviceId: map['deviceId'],
      currentPosition: map['currentPosition'] != null 
          ? LatLng(map['currentPosition']['lat'], map['currentPosition']['lon'])
          : null,
      heading: map['heading'],
      lastUpdate: DateTime.parse(map['lastUpdate']),
      isOnline: map['isOnline'] ?? false,
      markerColor: Color(map['markerColor']),
      assignedCells: List<String>.from(map['assignedCells'] ?? []),
    );
  }
}