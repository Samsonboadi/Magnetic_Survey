// lib/services/team_sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/team_member.dart';
import '../models/grid_cell.dart';
import "dart:math" as math;
class TeamSyncService {
  static final TeamSyncService instance = TeamSyncService._init();
  TeamSyncService._init();

  final StreamController<List<TeamMember>> _teamMembersController = StreamController.broadcast();
  final StreamController<List<GridCell>> _gridUpdatesController = StreamController.broadcast();
  
  Stream<List<TeamMember>> get teamMembersStream => _teamMembersController.stream;
  Stream<List<GridCell>> get gridUpdatesStream => _gridUpdatesController.stream;

  List<TeamMember> _teamMembers = [];
  String? _currentUserId;
  bool _isTeamMode = false;
  Timer? _syncTimer;

  // Team management
  Future<void> startTeamMode(String userName, String projectId) async {
    _currentUserId = _generateUserId();
    _isTeamMode = true;
    
    // Add current user as team member
    TeamMember currentUser = TeamMember(
      id: _currentUserId!,
      name: userName,
      deviceId: _generateDeviceId(),
      isOnline: true,
      markerColor: Colors.blue,
    );
    
    _teamMembers = [currentUser];
    _teamMembersController.add(_teamMembers);
    
    // Start periodic sync
    _startPeriodicSync();
    
    // Add demo team members for testing
    _addDemoTeamMembers();
  }

  void _addDemoTeamMembers() {
    // Add some demo team members
    List<Color> colors = [Colors.red, Colors.green, Colors.purple, Colors.orange];
    List<String> names = ['Alice', 'Bob', 'Charlie', 'Diana'];
    
    for (int i = 0; i < 2; i++) { // Add 2 demo members
      TeamMember member = TeamMember(
        id: _generateUserId(),
        name: names[i],
        deviceId: _generateDeviceId(),
        isOnline: true,
        markerColor: colors[i],
        currentPosition: LatLng(
          5.6037 + (Random().nextDouble() - 0.5) * 0.002, // Within ~200m
          -0.1870 + (Random().nextDouble() - 0.5) * 0.002,
        ),
        heading: Random().nextDouble() * 360,
      );
      
      _teamMembers.add(member);
    }
    
    _teamMembersController.add(_teamMembers);
  }

  Future<void> stopTeamMode() async {
    _isTeamMode = false;
    _syncTimer?.cancel();
    _currentUserId = null;
    _teamMembers.clear();
    _teamMembersController.add(_teamMembers);
  }

  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      if (_isTeamMode) {
        _simulateTeamUpdates();
        _teamMembersController.add(_teamMembers);
      }
    });
  }

  void _simulateTeamUpdates() {
    // Simulate movement and updates for demo team members
    for (TeamMember member in _teamMembers) {
      if (member.id != _currentUserId && member.currentPosition != null) {
        // Small random movement
        double deltaLat = (Random().nextDouble() - 0.5) * 0.0001;
        double deltaLon = (Random().nextDouble() - 0.5) * 0.0001;
        
        member.currentPosition = LatLng(
          member.currentPosition!.latitude + deltaLat,
          member.currentPosition!.longitude + deltaLon,
        );
        
        member.heading = (member.heading ?? 0) + (Random().nextDouble() - 0.5) * 20;
        member.lastUpdate = DateTime.now();
      }
    }
  }

  // Position updates
  Future<void> updateMyPosition(LatLng position, double? heading) async {
    if (!_isTeamMode || _currentUserId == null) return;
    
    TeamMember? currentUser = _teamMembers.firstWhere(
      (member) => member.id == _currentUserId,
      orElse: () => _teamMembers.first,
    );
    
    currentUser.currentPosition = position;
    currentUser.heading = heading;
    currentUser.lastUpdate = DateTime.now();
    
    // In a real app, this would sync to server/peers
    _teamMembersController.add(_teamMembers);
  }

  // Grid cell updates
  Future<void> updateGridCell(GridCell cell) async {
    if (!_isTeamMode) return;
    
    // Broadcast grid cell update to team
    _gridUpdatesController.add([cell]);
  }

  // Cell assignment
  void assignCellsToMember(String memberId, List<String> cellIds) {
    TeamMember? member = _teamMembers.firstWhere(
      (m) => m.id == memberId,
      orElse: () => _teamMembers.first,
    );
    
    member.assignedCells = cellIds;
    _teamMembersController.add(_teamMembers);
  }

  void autoAssignCells(List<GridCell> allCells) {
    if (_teamMembers.length <= 1) return;
    
    List<GridCell> unassignedCells = allCells
        .where((cell) => cell.status == GridCellStatus.notStarted)
        .toList();
    
    int cellsPerMember = (unassignedCells.length / _teamMembers.length).ceil();
    
    for (int i = 0; i < _teamMembers.length; i++) {
      int startIndex = i * cellsPerMember;
      int endIndex = math.min(startIndex + cellsPerMember, unassignedCells.length);
      
      if (startIndex < unassignedCells.length) {
        List<String> assignedIds = unassignedCells
            .sublist(startIndex, endIndex)
            .map((cell) => cell.id)
            .toList();
        
        _teamMembers[i].assignedCells = assignedIds;
      }
    }
    
    _teamMembersController.add(_teamMembers);
  }

  // Utility methods
  String _generateUserId() {
    return 'user_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
  }

  String _generateDeviceId() {
    return 'device_${Random().nextInt(10000)}';
  }

  List<TeamMember> get teamMembers => _teamMembers;
  bool get isTeamMode => _isTeamMode;
  String? get currentUserId => _currentUserId;

  void dispose() {
    _syncTimer?.cancel();
    _teamMembersController.close();
    _gridUpdatesController.close();
  }
}

