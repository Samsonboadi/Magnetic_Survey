// lib/widgets/field_notes_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FieldNotesDialog extends StatefulWidget {
  final Function(String) onNoteSaved;
  
  FieldNotesDialog({required this.onNoteSaved});

  @override
  _FieldNotesDialogState createState() => _FieldNotesDialogState();
}

class _FieldNotesDialogState extends State<FieldNotesDialog> {
  final _noteController = TextEditingController();
  bool _isRecording = false;
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.note_add, color: Colors.blue),
          SizedBox(width: 8),
          Text('Field Notes'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _noteController,
            decoration: InputDecoration(
              labelText: 'Add field observation...',
              border: OutlineInputBorder(),
              hintText: 'Describe geological features, anomalies, or conditions',
            ),
            maxLines: 4,
            maxLength: 500,
          ),
          SizedBox(height: 16),
          
          // Media options
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _takePhoto,
                icon: Icon(Icons.camera_alt),
                label: Text('Photo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _toggleRecording,
                icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                label: Text(_isRecording ? 'Stop' : 'Voice'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording ? Colors.red : Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveNote,
          child: Text('Save Note'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  void _takePhoto() {
    // TODO: Implement camera functionality
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Photo capture will be implemented')),
    );
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });
    
    if (_isRecording) {
      // TODO: Start audio recording
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recording started...')),
      );
    } else {
      // TODO: Stop audio recording
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recording stopped')),
      );
    }
  }

  void _saveNote() {
    if (_noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a note')),
      );
      return;
    }

    widget.onNoteSaved(_noteController.text.trim());
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }
}