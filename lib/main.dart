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
  
  // Extract the amount from the SMS body
  double? extractAmount() {
    final regExpINR = RegExp(r'INR (\d+(\.\d+)?) debited');
    final matchINR = regExpINR.firstMatch(body);
    if (matchINR != null && matchINR.groupCount >= 1) {
      return double.tryParse(matchINR.group(1) ?? '0');
    }

    // Pattern for Sent Rs messages
    final regExpRs = RegExp(r'Sent Rs\.(\d+(\.\d+)?) from Kotak Bank');
    final matchRs = regExpRs.firstMatch(body);
    if (matchRs != null && matchRs.groupCount >= 1) {
      return double.tryParse(matchRs.group(1) ?? '0');
    }

    return null;
  }
}

// New model for expense entries with category field
class ExpenseEntry {
  final double amount;
  final String description;
  final DateTime date;
  final String category;

  ExpenseEntry({
    required this.amount,
    required this.description,
    required this.date,
    required this.category,
  });

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'description': description,
      'date': date.toIso8601String(),
      'category': category,
    };
  }

  factory ExpenseEntry.fromJson(Map<String, dynamic> json) {
    return ExpenseEntry(
      amount: json['amount'],
      description: json['description'],
      date: DateTime.parse(json['date']),
      category:
          json['category'] ?? 'Other', // Default for backward compatibility
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
      debugShowCheckedModeBanner: false,
      title: 'Money Manager',
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      home: const MoneyManagerScreen(),
    );
  }
}

class MoneyManagerScreen extends StatefulWidget {
  const MoneyManagerScreen({Key? key}) : super(key: key);

  @override
  State<MoneyManagerScreen> createState() => _MoneyManagerScreenState();
}

class _MoneyManagerScreenState extends State<MoneyManagerScreen>
    with SingleTickerProviderStateMixin {
  static const platform = MethodChannel('com.example.new_notif/sms_reader');
  final _smsPlugin = Readsms();
  List<SmsMessage> messages = [];
  List<ExpenseEntry> expenses = [];

  // List of available categories
  final List<String> categories = ['Food', 'Travel', 'Rent', 'Cloth', 'Other'];

  // Currently selected category
  String? selectedCategory;

  // Controllers
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // TabController
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMessages();
    _loadExpenses();
    _startSmsListener();
    _startBackgroundService();

    // Check if app was launched from notification with an SMS
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForLatestSms();
    });
  }

  Future<void> _checkForLatestSms() async {
    if (messages.isNotEmpty) {
      final latestMessage = messages.first;
      final amount = latestMessage.extractAmount();
      if (amount != null) {
        _amountController.text = amount.toString();
      }
    }
  }

  Future<void> _startBackgroundService() async {
    try {
      await platform.invokeMethod('startService');
    } on PlatformException catch (e) {
      debugPrint("Failed to start background service: ${e.message}");
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
    // Only process messages that match the template
    if (!_matchesTemplate(body)) {
      return;
    }
    
    // Create a message object
    final message = SmsMessage(
      body: body,
      sender: sender,
      timeReceived: timeReceived,
    );
    
    // Save message
    await _saveMessage(message);
    
    // Extract amount and populate the input field
    final amount = message.extractAmount();
    if (amount != null) {
      _amountController.text = amount.toString();
    }
    
    // Refresh UI
    setState(() {
      _loadMessages();
    });
  }
  
  bool _matchesTemplate(String message) {
    // Regular expression to match the template
    RegExp regex1 = RegExp(
      r'INR \d+(\.\d+)? debited[\s\S]*A/c no\. XX1133[\s\S]*',
    );
    
    // Regular expression to match the second template (Sent Rs from Kotak Bank)
    RegExp regex2 = RegExp(r'Sent Rs\.(\d+(\.\d+)?) from Kotak Bank[\s\S]*');

    return regex1.hasMatch(message) || regex2.hasMatch(message);
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMessages = prefs.getStringList('sms_messages_prefs') ?? [];
    
    setState(() {
      messages = savedMessages
          .map((message) => SmsMessage.fromJson(jsonDecode(message)))
          .toList();
      
      // Sort messages by time received (newest first)
      messages.sort((a, b) => b.timeReceived.compareTo(a.timeReceived));
    });
  }
  
  Future<void> _loadExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final savedExpenses = prefs.getStringList('expenses_data') ?? [];

    setState(() {
      expenses =
          savedExpenses
              .map((expense) => ExpenseEntry.fromJson(jsonDecode(expense)))
              .toList();

      // Sort expenses by date (newest first)
      expenses.sort((a, b) => b.date.compareTo(a.date));
    });
  }
  
  Future<void> _saveMessage(SmsMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    final savedMessagesJson = prefs.getStringList('sms_messages_prefs') ?? [];
    
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
        
    await prefs.setStringList('sms_messages_prefs', updatedMessagesJson);
  }

  Future<void> _saveExpense(ExpenseEntry expense) async {
    final prefs = await SharedPreferences.getInstance();
    final savedExpensesJson = prefs.getStringList('expenses_data') ?? [];

    final allExpenses =
        savedExpensesJson
            .map((exp) => ExpenseEntry.fromJson(jsonDecode(exp)))
            .toList();

    // Add new expense
    allExpenses.add(expense);

    // Sort by date (newest first)
    allExpenses.sort((a, b) => b.date.compareTo(a.date));

    // Save back to SharedPreferences
    final updatedExpensesJson =
        allExpenses.map((exp) => jsonEncode(exp.toJson())).toList();

    await prefs.setStringList('expenses_data', updatedExpensesJson);

    // Refresh the list
    _loadExpenses();
  }

  Future<void> _clearExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('expenses_data', []);

    setState(() {
      expenses.clear();
    });
  }

  Future<void> _submitExpense() async {
    // Validate input
    final amountText = _amountController.text.trim();
    
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter an amount')));
      return;
    }

    if (selectedCategory == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a category')));
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    // Get description based on category
    String description;
    if (selectedCategory == 'Other') {
      description = _descriptionController.text.trim();
      if (description.isEmpty) {
        description = 'Other';
      }
    } else {
      description = selectedCategory!;
    }

    // Create and save expense
    final expense = ExpenseEntry(
      amount: amount,
      description: description,
      date: DateTime.now(),
      category: selectedCategory!,
    );

    await _saveExpense(expense);

    // Clear the fields
    _amountController.clear();
    _descriptionController.clear();
    setState(() {
      selectedCategory = null;
    });

    // Show confirmation
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Expense saved successfully')));
  }
  
  @override
  void dispose() {
    _smsPlugin.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Money Manager'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.money), text: 'Add Expense'),
            Tab(icon: Icon(Icons.history), text: 'History'),
          ],
          labelColor: Colors.white,
          indicatorColor: Colors.white,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Add Expense Tab
          _buildAddExpenseTab(),

          // History Tab
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildAddExpenseTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card with expense input fields
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New Expense',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.green[800],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Amount input
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount (INR)',
                      prefixIcon: const Icon(Icons.currency_rupee),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Category selection
                  Text(
                    'Select Category',
                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 8),

                  // Category buttons
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        categories.map((category) {
                          final isSelected = selectedCategory == category;
                          return ChoiceChip(
                            label: Text(category),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                selectedCategory = selected ? category : null;
                              });
                            },
                            backgroundColor: Colors.grey[200],
                            selectedColor: Colors.green[100],
                            labelStyle: TextStyle(
                              color:
                                  isSelected
                                      ? Colors.green[800]
                                      : Colors.black87,
                              fontWeight:
                                  isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Description input - only visible when "Other" is selected
                  if (selectedCategory == 'Other')
                    TextField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: 'What was it for?',
                        prefixIcon: const Icon(Icons.description),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  if (selectedCategory == 'Other') const SizedBox(height: 16),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _submitExpense,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'SAVE EXPENSE',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Column(
      children: [
        // Header with clear button
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Expense History',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder:
                        (context) => AlertDialog(
                          title: const Text('Clear All Expenses'),
                          content: const Text(
                            'Are you sure you want to delete all expenses?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('CANCEL'),
                            ),
                            TextButton(
                              onPressed: () {
                                _clearExpenses();
                                Navigator.pop(context);
                              },
                              child: const Text('DELETE'),
                            ),
                          ],
                        ),
                  );
                },
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                label: const Text(
                  'Clear All',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ),

        // Expense list
        Expanded(
          child:
              expenses.isEmpty
                  ? const Center(
                    child: Text(
                      'No expenses yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  )
                  : ListView.builder(
                    itemCount: expenses.length,
                    itemBuilder: (context, index) {
                      final expense = expenses[index];

                      // Get icon based on category
                      IconData categoryIcon;
                      switch (expense.category) {
                        case 'Food':
                          categoryIcon = Icons.restaurant;
                          break;
                        case 'Travel':
                          categoryIcon = Icons.directions_car;
                          break;
                        case 'Rent':
                          categoryIcon = Icons.home;
                          break;
                        case 'Cloth':
                          categoryIcon = Icons.shopping_bag;
                          break;
                        default:
                          categoryIcon = Icons.receipt_long;
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(categoryIcon,
                              color: Colors.green,
                            ),
                          ),
                          title: Text(
                            '₹${expense.amount.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(expense.description),
                              Text(
                                DateFormat(
                                  'MMM d, y - h:mm a',
                                ).format(expense.date),
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}