// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/transaction.dart' as model;
import '../../widgets/app_scaffold.dart';
import '../../services/firebase_service.dart';
import '../../services/bank_account_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with ChangeNotifier {
  final User? user = FirebaseAuth.instance.currentUser;
  double totalBalance = 0.0;
  double totalIncome = 0.0;
  double totalExpense = 0.0;
  List<model.Transaction> transactions = [];
  List accAccounts = [];
  String? _selectedAccountId;
  bool isLoading = true;

  StreamSubscription? _transactionsSubscription;
  StreamSubscription? _accountSubscription;
  StreamSubscription? _userStatusSubscription;

  @override
  void initState() {
    super.initState();
    _checkIfBlocked();
    _initData();
    // After first frame, ensure phone is present for the user and prompt if missing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptForPhoneIfMissing();
    });
  }

  @override
  void dispose() {
    _transactionsSubscription?.cancel();
    _accountSubscription?.cancel();
    _userStatusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _promptForPhoneIfMissing() async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();
      final data = doc.data();
      final phone = data?['phone']?.toString() ?? '';
      if (phone.trim().isEmpty) {
        // small delay to avoid showing dialog immediately during navigation
        await Future.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;

        final phoneController = TextEditingController();
        final formKey = GlobalKey<FormState>();

        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Enter mobile number'),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Mobile Number',
                    hintText: 'e.g. +919876543210',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter phone number';
                    }
                    final cleaned = v.replaceAll(RegExp(r'[^0-9+]'), '');
                    if (cleaned.length < 7) {
                      return 'Please enter a valid phone number';
                    }
                    return null;
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // allow user to skip if they really want (but we will show again next time)
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Skip'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    final value = phoneController.text.trim();
                    try {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user!.uid)
                          .set({
                            'phone': value,
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Phone number saved')),
                        );
                      }
                      Navigator.of(ctx).pop();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to save phone: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      debugPrint('Error checking phone: $e');
    }
  }

  Future<void> _initData() async {
    await _loadAccounts();
    await loadTransactions();
  }

  Future<void> _loadAccounts() async {
    if (user == null) return;
    try {
      final bankService = BankAccountService();
      _accountSubscription?.cancel();
      _accountSubscription = bankService.getBankAccounts().listen((accounts) {
        if (mounted) {
          setState(() {
            accAccounts = accounts;
            if (accounts.isNotEmpty) {
              final sel = accounts.firstWhere(
                (a) => a.isSelected,
                orElse: () => accounts.first,
              );
              _selectedAccountId = sel.id;
              _setupTransactionListener();
            } else {
              _selectedAccountId = null;
              _setupLegacyTransactionListener();
            }
          });
        }
      });
    } catch (e) {
      debugPrint('Error loading accounts: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  String _shortBankName(String bankName) {
    if (bankName.trim().isEmpty) return 'ACC';
    final words = bankName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final initials = words.map((w) => w[0]).take(3).join();
    if (initials.length >= 2) return initials.toUpperCase();
    return bankName
        .replaceAll(RegExp(r'[^A-Za-z]'), '')
        .toUpperCase()
        .substring(0, bankName.length >= 3 ? 3 : bankName.length);
  }

  Future<void> _checkIfBlocked() async {
    try {
      final isBlocked = await FirebaseService.isCurrentUserBlocked();
      if (isBlocked && mounted) {
        Navigator.pushReplacementNamed(context, '/blocked');
      }
    } catch (e) {
      debugPrint('Error checking user status: $e');
      // If there's an error, we'll let the user stay on the home screen
      // rather than blocking them due to an error
    }
  }

  void _setupTransactionListener() {
    if (user == null || _selectedAccountId == null) return;

    _transactionsSubscription?.cancel();

    // Listen to account balance changes
    final accountDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('bankAccounts')
        .doc(_selectedAccountId);

    _transactionsSubscription = accountDoc.snapshots().listen((
      accountSnapshot,
    ) {
      if (!mounted || !accountSnapshot.exists) return;

      final accountData = accountSnapshot.data();
      if (accountData != null) {
        setState(() {
          totalBalance = (accountData['currentBalance'] ?? 0).toDouble();
        });
      }
    });

    // Listen to transactions
    final transactionsQuery = accountDoc
        .collection('transactions')
        .orderBy('date', descending: true);

    _transactionsSubscription = transactionsQuery.snapshots().listen(
      (snapshot) {
        if (!mounted) return;

        double income = 0.0;
        double expense = 0.0;
        final List<model.Transaction> newTransactions = [];

        for (final doc in snapshot.docs) {
          final data = doc.data();

          double amount = 0.0;
          try {
            amount = (data['amount'] ?? 0).toDouble();
          } catch (_) {
            amount = double.tryParse(data['amount']?.toString() ?? '0') ?? 0.0;
          }

          final typeStr = (data['type'] ?? 'expense').toString().toLowerCase();
          final isIncome = typeStr == 'income';

          if (isIncome) {
            income += amount.abs();
          } else {
            expense += amount.abs();
          }

          try {
            final t = model.Transaction.fromMap(
              data,
              id: doc.id,
            ).copyWith(userId: user!.uid);
            if (t.id.isNotEmpty) newTransactions.add(t);
          } catch (_) {
            // skip parse errors
          }
        }

        if (mounted) {
          setState(() {
            transactions = newTransactions;
            totalIncome = income;
            totalExpense = expense;
            isLoading = false;
          });
        }
      },
      onError: (error) {
        debugPrint('Error in transaction listener: $error');
        if (mounted) {
          setState(() => isLoading = false);
        }
      },
    );
  }

  void _setupLegacyTransactionListener() {
    if (user == null) return;

    _transactionsSubscription?.cancel();

    final transactionsQuery = FirebaseFirestore.instance
        .collection('transactions')
        .doc(user!.uid)
        .collection('user_transactions')
        .orderBy('date', descending: true);

    _transactionsSubscription = transactionsQuery.snapshots().listen(
      (snapshot) {
        if (!mounted) return;

        double income = 0.0;
        double expense = 0.0;
        final List<model.Transaction> newTransactions = [];

        for (final doc in snapshot.docs) {
          final data = doc.data();

          double amount = 0.0;
          try {
            amount = (data['amount'] ?? 0).toDouble();
          } catch (_) {
            amount = double.tryParse(data['amount']?.toString() ?? '0') ?? 0.0;
          }

          final typeStr = (data['type'] ?? 'expense').toString().toLowerCase();
          if (typeStr == 'income') {
            income += amount.abs();
          } else {
            expense += amount.abs();
          }

          try {
            final t = model.Transaction.fromMap(
              data,
              id: doc.id,
            ).copyWith(userId: user!.uid);
            if (t.id.isNotEmpty) newTransactions.add(t);
          } catch (_) {}
        }

        if (mounted) {
          setState(() {
            transactions = newTransactions;
            totalIncome = income;
            totalExpense = expense;
            totalBalance = income - expense;
            isLoading = false;
          });
        }
      },
      onError: (error) {
        debugPrint('Error in legacy transaction listener: $error');
        if (mounted) {
          setState(() => isLoading = false);
        }
      },
    );
  }

  // Keep this method for backward compatibility with RefreshIndicator
  Future<void> loadTransactions() async {
    if (user == null) return;

    setState(() => isLoading = true);

    if (_selectedAccountId != null) {
      _setupTransactionListener();
    } else {
      _setupLegacyTransactionListener();
    }
  }

  // Totals are computed inline when transactions are loaded to avoid parsing issues.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Money Mint',
      floatingActionButton: null, // Remove FAB
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadTransactions,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Keep spacing before balance card; account selector moved into the card
                    const SizedBox(height: 12),
                    // Balance Card
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    (accAccounts.isNotEmpty &&
                                            _selectedAccountId != null &&
                                            accAccounts.any(
                                              (a) => a.id == _selectedAccountId,
                                            ))
                                        ? '${_shortBankName((accAccounts.firstWhere((a) => a.id == _selectedAccountId)).bankName)} Balance'
                                        : 'Total Balance',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                if (accAccounts.isNotEmpty)
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.arrow_drop_down),
                                    itemBuilder: (context) => accAccounts.map((
                                      a,
                                    ) {
                                      final mask = a.accountNumber;
                                      final label = mask.length > 4
                                          ? '${a.bankName} • ****${mask.substring(mask.length - 4)}'
                                          : '${a.bankName} • $mask';
                                      return PopupMenuItem<String>(
                                        value: a.id,
                                        child: Text(
                                          label,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      );
                                    }).toList(),
                                    onSelected: (val) async {
                                      setState(() {
                                        _selectedAccountId = val;
                                        isLoading = true;
                                      });
                                      await loadTransactions();
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '₹${totalBalance.toStringAsFixed(2)}',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: totalBalance >= 0
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildAmountInfo(
                                  'Income',
                                  totalIncome,
                                  Colors.green,
                                ),
                                _buildAmountInfo(
                                  'Expense',
                                  totalExpense,
                                  Colors.red,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Income vs Expense Chart
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Income vs Expense',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 180, // Increased from 150
                              child: _buildPieChart(),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildLegend(Colors.green, 'Income'),
                                _buildLegend(Colors.red, 'Expense'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pushNamed(context, '/transactions');
                            },
                            icon: const Icon(Icons.history),
                            label: const Text('Transaction History'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              // Navigate to app settings
                              Navigator.pushNamed(context, '/settings');
                            },
                            icon: const Icon(Icons.settings),
                            label: const Text('App Settings'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAmountInfo(String label, double amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(height: 4),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildPieChart() {
    return PieChart(
      PieChartData(
        sectionsSpace: 3,
        centerSpaceRadius: 25, // Increased from 15
        sections: [
          PieChartSectionData(
            color: Colors.green,
            value: totalIncome,
            title:
                '${totalIncome > 0 ? (totalIncome / (totalIncome + totalExpense) * 100).toStringAsFixed(1) : 0}%',
            radius: 50, // Increased from 40
            titleStyle: const TextStyle(
              fontSize: 13, // Slightly increased font size
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          PieChartSectionData(
            color: Colors.red,
            value: totalExpense,
            title:
                '${totalExpense > 0 ? (totalExpense / (totalIncome + totalExpense) * 100).toStringAsFixed(1) : 0}%',
            radius: 50, // Increased from 40
            titleStyle: const TextStyle(
              fontSize: 13, // Slightly increased font size
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 16, color: color),
        const SizedBox(width: 8),
        Text(text),
      ],
    );
  }
}
