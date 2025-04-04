import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:readsms/readsms.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

// Model for SMS Message
class SmsMessage {
  final String body;
  final String sender;
  final DateTime timeReceived;

  SmsMessage({
    required this.body,
    required this.sender,
    required this.timeReceived,
  });

  Map<String, dynamic> toJson() {
    return {
      'body': body,
      'sender': sender,
      'timeReceived': timeReceived.toIso8601String(),
    };
  }

  factory SmsMessage.fromJson(Map<String, dynamic> json) {
    return SmsMessage(
      body: json['body'],
      sender: json['sender'],
      timeReceived: DateTime.parse(json['timeReceived']),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Request permissions
  await Permission.sms.request();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SMS Reader',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const SmsReaderScreen(),
    );
  }
}

class SmsReaderScreen extends StatefulWidget {
  const SmsReaderScreen({Key? key}) : super(key: key);

  @override
  State<SmsReaderScreen> createState() => _SmsReaderScreenState();
}

class _SmsReaderScreenState extends State<SmsReaderScreen> {
  static const platform = MethodChannel('com.example.new_notif/sms_reader');
  final _smsPlugin = Readsms();
  List<SmsMessage> messages = [];
  bool _serviceRunning = false;

  @override
  void initState() {
    super.initState();
    _checkServiceStatus();
    _loadMessages();
    _startSmsListener();
  }
  
  Future<void> _checkServiceStatus() async {
    try {
      final bool running = await platform.invokeMethod('isServiceRunning');
      setState(() {
        _serviceRunning = running;
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to check service status: ${e.message}");
    }
  }
  
  void _startSmsListener() {
    // This will handle SMS when the app is in the foreground
    _smsPlugin.read();
    _smsPlugin.smsStream.listen((event) {
      _handleNewSms(event.body, event.sender, event.timeReceived);
    });
  }
  
  Future<void> _handleNewSms(String body, String sender, DateTime timeReceived) async {
    // Create a message object
    final message = SmsMessage(
      body: body,
      sender: sender,
      timeReceived: timeReceived,
    );
    
    // Save message
    await _saveMessage(message);
    
    // Refresh UI
    setState(() {
      _loadMessages();
    });
  }

  Future<void> _toggleService() async {
    try {
      if (_serviceRunning) {
        await platform.invokeMethod('stopService');
      } else {
        await platform.invokeMethod('startService');
      }
      
      _checkServiceStatus();
    } on PlatformException catch (e) {
      debugPrint("Failed to toggle service: ${e.message}");
    }
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMessages = prefs.getStringList('sms_messages') ?? [];
    
    setState(() {
      messages = savedMessages
          .map((message) => SmsMessage.fromJson(jsonDecode(message)))
          .toList();
      
      // Sort messages by time received (newest first)
      messages.sort((a, b) => b.timeReceived.compareTo(a.timeReceived));
    });
  }
  
  Future<void> _saveMessage(SmsMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    final savedMessagesJson = prefs.getStringList('sms_messages') ?? [];
    
    final allMessages = savedMessagesJson
        .map((msg) => SmsMessage.fromJson(jsonDecode(msg)))
        .toList();
        
    // Add new message
    allMessages.add(message);
    
    // Sort by time (newest first)
    allMessages.sort((a, b) => b.timeReceived.compareTo(a.timeReceived));
    
    // Save back to SharedPreferences
    final updatedMessagesJson = allMessages
        .map((msg) => jsonEncode(msg.toJson()))
        .toList();
        
    await prefs.setStringList('sms_messages', updatedMessagesJson);
  }
  
  Future<void> _clearMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('sms_messages', []);
    
    setState(() {
      messages.clear();
    });
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);

    if (messageDate == today) {
      return DateFormat.jm().format(time); // Today: 3:45 PM
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, ${DateFormat.jm().format(time)}'; // Yesterday, 3:45 PM
    } else {
      return DateFormat('MMM d, y - h:mm a').format(time); // Jan 1, 2023 - 3:45 PM
    }
  }
  
  @override
  void dispose() {
    _smsPlugin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Reader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Messages'),
                  content: const Text('Are you sure you want to delete all saved messages?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL'),
                    ),
                    TextButton(
                      onPressed: () {
                        _clearMessages();
                        Navigator.pop(context);
                      },
                      child: const Text('DELETE'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: messages.isEmpty
          ? const Center(
              child: Text(
                'No messages yet',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            )
          : ListView.separated(
              itemCount: messages.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final message = messages[index];
                return ListTile(
                  title: Text(
                    message.sender,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message.body),
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(message.timeReceived),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleService,
        tooltip: 'Toggle Background Service',
        child: Icon(
          _serviceRunning ? Icons.stop : Icons.play_arrow,
        ),
      ),
    );
  }
}