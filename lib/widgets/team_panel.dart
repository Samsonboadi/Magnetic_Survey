// lib/widgets/team_panel.dart
import 'package:flutter/material.dart';
import '../models/team_member.dart';
import '../services/team_sync_service.dart';

class TeamPanel extends StatefulWidget {
  final Function(bool) onTeamModeToggle;
  
  TeamPanel({required this.onTeamModeToggle});

  @override
  _TeamPanelState createState() => _TeamPanelState();
}

class _TeamPanelState extends State<TeamPanel> {
  final TeamSyncService _teamService = TeamSyncService.instance;
  List<TeamMember> _teamMembers = [];
  bool _isTeamMode = false;

  @override
  void initState() {
    super.initState();
    _teamService.teamMembersStream.listen((members) {
      setState(() {
        _teamMembers = members;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.group, color: Colors.blue),
              SizedBox(width: 8),
              Text('Team Survey', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Spacer(),
              Switch(
                value: _isTeamMode,
                onChanged: _toggleTeamMode,
                activeColor: Colors.green,
              ),
            ],
          ),
          
          if (_isTeamMode) ...[
            Divider(),
            
            // Team members list
            Container(
              height: 200,
              child: _teamMembers.isEmpty
                  ? Center(child: Text('No team members'))
                  : ListView.builder(
                      itemCount: _teamMembers.length,
                      itemBuilder: (context, index) {
                        TeamMember member = _teamMembers[index];
                        return _buildTeamMemberTile(member);
                      },
                    ),
            ),
            
            // Team actions
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _inviteTeamMember,
                    icon: Icon(Icons.person_add),
                    label: Text('Invite'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _autoAssignCells,
                    icon: Icon(Icons.auto_awesome),
                    label: Text('Auto Assign'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTeamMemberTile(TeamMember member) {
    bool isCurrentUser = member.id == _teamService.currentUserId;
    
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: member.markerColor,
        child: Text(
          member.name.substring(0, 1).toUpperCase(),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      title: Row(
        children: [
          Text(member.name),
          if (isCurrentUser) ...[
            SizedBox(width: 8),
            Chip(
              label: Text('You', style: TextStyle(fontSize: 10)),
              backgroundColor: Colors.blue[100],
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                member.isOnline ? Icons.circle : Icons.circle_outlined,
                color: member.isOnline ? Colors.green : Colors.grey,
                size: 12,
              ),
              SizedBox(width: 4),
              Text(member.isOnline ? 'Online' : 'Offline'),
              Spacer(),
              Text(
                '${member.assignedCells.length} cells',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          if (member.currentPosition != null)
            Text(
              'Last seen: ${_formatTimestamp(member.lastUpdate)}',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
        ],
      ),
      trailing: member.isOnline 
          ? Icon(Icons.location_on, color: member.markerColor)
          : Icon(Icons.location_off, color: Colors.grey),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    DateTime now = DateTime.now();
    Duration difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${difference.inHours}h ago';
    }
  }

  void _toggleTeamMode(bool enabled) {
    setState(() {
      _isTeamMode = enabled;
    });
    
    widget.onTeamModeToggle(enabled);
    
    if (enabled) {
      _showTeamSetupDialog();
    } else {
      _teamService.stopTeamMode();
    }
  }

  void _showTeamSetupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Start Team Survey'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Your Name',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _userName = value,
            ),
            SizedBox(height: 16),
            Text(
              'Team members can join by scanning QR code or entering project ID',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _isTeamMode = false);
              Navigator.pop(context);
            },
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _teamService.startTeamMode(_userName.isEmpty ? 'User' : _userName, 'project_123');
              Navigator.pop(context);
            },
            child: Text('Start Team Mode'),
          ),
        ],
      ),
    );
  }

  String _userName = '';

  void _inviteTeamMember() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Invite Team Member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Icon(Icons.qr_code, size: 80),
                  SizedBox(height: 8),
                  Text('QR Code', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Project ID: TERRA2024', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text('Or share the project code: TERRA2024'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Implement sharing
              Navigator.pop(context);
            },
            child: Text('Share'),
          ),
        ],
      ),
    );
  }

  void _autoAssignCells() {
    // TODO: Implement auto cell assignment
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cells auto-assigned to team members')),
    );
  }
}