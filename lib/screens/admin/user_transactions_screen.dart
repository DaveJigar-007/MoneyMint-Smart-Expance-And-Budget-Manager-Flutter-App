// ignore_for_file: avoid_types_as_parameter_names

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/transaction.dart' as model;

class UserTransactionsScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const UserTransactionsScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<UserTransactionsScreen> createState() => _UserTransactionsScreenState();
}

class _UserTransactionsScreenState extends State<UserTransactionsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, List<model.Transaction>> _transactionsByAccount = {};
  Map<String, double> _accountBalances = {};
  bool _isLoading = true;
  List<Map<String, dynamic>> _bankAccounts = [];
  String _selectedAccountId = '';

  String _getShortBankName(Map<String, dynamic> account) {
    // Use explicit shortName if provided in the account document
    final shortFromDoc = account['shortName'];
    if (shortFromDoc != null && shortFromDoc.toString().trim().isNotEmpty) {
      return shortFromDoc.toString();
    }

    final bankName = (account['bankName'] ?? '').toString().trim();
    if (bankName.isEmpty) return 'BANK';

    final nameLower = bankName.toLowerCase();

    // Explicit mappings for requested banks
    const Map<String, String> mapping = {
      'rajkot nagarik sahakari bank': 'RNSB',
      'state bank of india': 'SBI',
      'bank of baroda': 'BOB',
      'punjab national bank': 'PNB',
      'canara bank': 'Canara',
      'union bank of india': 'Union',
      'bank of india': 'BOI',
      'indian bank': 'Indian',
      'central bank of india': 'Central',
      'indian overseas bank': 'IOB',
      'uco bank': 'UCO',
    };

    for (final entry in mapping.entries) {
      if (nameLower.contains(entry.key)) return entry.value;
    }

    // Fallback: generate an acronym (max 3 chars)
    final smallWords = {'and', 'the', '&'};
    final words = bankName.split(RegExp(r"\s+"));
    final filtered = words
        .where((w) => w.isNotEmpty && !smallWords.contains(w.toLowerCase()))
        .toList();

    final sourceWords = filtered.isNotEmpty ? filtered : words;
    final initials = sourceWords.map((w) => w[0]).join();
    var acronym = initials.toUpperCase();

    if (acronym.length == 1) {
      // fallback to first 3 letters of bank name
      return bankName.length <= 3
          ? bankName.toUpperCase()
          : bankName.substring(0, 3).toUpperCase();
    }

    // Limit to max 3 characters for display
    if (acronym.length > 3) {
      acronym = acronym.substring(0, 3);
    }

    return acronym;
  }

  @override
  void initState() {
    super.initState();
    _loadBankAccounts();
  }

  Future<void> _loadBankAccounts() async {
    try {
      final accountsSnapshot = await _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('bankAccounts')
          .get();

      _bankAccounts = accountsSnapshot.docs.map((doc) {
        return {'id': doc.id, ...doc.data()};
      }).toList();

      // Set the first account as selected by default
      if (_bankAccounts.isNotEmpty) {
        _selectedAccountId = _bankAccounts[0]['id'];
      }

      // Load transactions for all accounts
      await _loadAllTransactions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading accounts: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadAllTransactions() async {
    try {
      // Initialize with all accounts
      _transactionsByAccount = {'all': []};
      _accountBalances = {'all': 0.0};

      // Load transactions for each bank account
      for (final account in _bankAccounts) {
        if (account['id'] == 'all') continue;

        final accountId = account['id'] as String;
        _transactionsByAccount[accountId] = [];
        _accountBalances[accountId] = (account['currentBalance'] ?? 0.0)
            .toDouble();

        // Listen to transactions for this account
        _firestore
            .collection('users')
            .doc(widget.userId)
            .collection('bankAccounts')
            .doc(accountId)
            .collection('transactions')
            .orderBy('date', descending: true)
            .snapshots()
            .listen((snapshot) {
              if (!mounted) return;

              final transactions = snapshot.docs.map((doc) {
                final data = doc.data();
                return model.Transaction(
                  id: doc.id,
                  amount: (data['amount'] as num).toDouble(),
                  description: data['description'] ?? 'No description',
                  date: (data['date'] as Timestamp).toDate(),
                  category: model.Category.values.firstWhere(
                    (e) => e.toString() == 'Category.${data['category']}',
                    orElse: () => model.Category.otherIncome,
                  ),
                  type: data['type'].toString().contains('expense')
                      ? model.TransactionType.expense
                      : model.TransactionType.income,
                  userId: widget.userId,
                  bankAccountId: accountId,
                );
              }).toList();

              setState(() {
                _transactionsByAccount[accountId] = transactions;
                _updateAllTransactions();
              });
            });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading transactions: $e')),
        );
      }
    }
  }

  void _updateAllTransactions() {
    if (_bankAccounts.length <= 1) return;

    final allTransactions = <model.Transaction>[];
    double totalBalance = 0.0;

    // Skip the first 'All Accounts' item
    for (int i = 1; i < _bankAccounts.length; i++) {
      final accountId = _bankAccounts[i]['id'];
      allTransactions.addAll(_transactionsByAccount[accountId] ?? []);
      totalBalance += _accountBalances[accountId] ?? 0.0;
    }

    // Sort all transactions by date
    allTransactions.sort((a, b) => b.date.compareTo(a.date));

    setState(() {
      _transactionsByAccount['all'] = allTransactions;
      _accountBalances['all'] = totalBalance;
    });
  }

  Widget _buildTransactionList(List<model.Transaction> transactions) {
    if (transactions.isEmpty) {
      return Column(
        children: [
          _buildTransactionHeader(),
          const Expanded(child: Center(child: Text('No transactions found'))),
        ],
      );
    }

    final List<Widget> transactionWidgets = [_buildTransactionHeader()];

    // Group transactions by date
    final Map<String, List<model.Transaction>> transactionsByDate = {};

    for (final transaction in transactions) {
      final dateKey = DateFormat('EEEE, MMMM d, y').format(transaction.date);
      if (!transactionsByDate.containsKey(dateKey)) {
        transactionsByDate[dateKey] = [];
      }
      transactionsByDate[dateKey]!.add(transaction);
    }

    // Add date headers and transactions
    transactionsByDate.forEach((date, dateTransactions) {
      transactionWidgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey[100],
          child: Text(
            date,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
        ),
      );

      transactionWidgets.add(
        Column(
          children: dateTransactions
              .map((transaction) => _buildTransactionItem(transaction))
              .toList(),
        ),
      );
    });

    return ListView(children: transactionWidgets);
  }

  Widget _buildTransactionItem(model.Transaction transaction) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 0,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: transaction.type == model.TransactionType.income
                ? Colors.green[50]
                : Colors.red[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            transaction.categoryIcon,
            color: transaction.type == model.TransactionType.income
                ? Colors.green
                : Colors.red,
          ),
        ),
        title: Text(
          transaction.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${transaction.categoryName} • ${DateFormat('h:mm a').format(transaction.date)}',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${transaction.type == model.TransactionType.income ? '+' : '-'}₹${transaction.amount.abs().toStringAsFixed(2)}',
              style: TextStyle(
                color: transaction.type == model.TransactionType.income
                    ? Colors.green
                    : Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (_bankAccounts.any(
              (acc) => acc['id'] == transaction.bankAccountId,
            ))
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _bankAccounts
                          .firstWhere(
                            (acc) => acc['id'] == transaction.bankAccountId,
                            orElse: () => {'bankName': 'Bank'},
                          )['bankName']
                          ?.toString() ??
                      'Bank',
                  style: TextStyle(
                    color: Colors.grey[800],
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionHeader() {
    final account = _bankAccounts.firstWhere(
      (acc) => acc['id'] == _selectedAccountId,
      orElse: () => {'bankName': 'Account'},
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account['bankName'] ?? 'Transactions',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_transactionsByAccount[_selectedAccountId]?.length ?? 0} transactions',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Balance',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              Text(
                '₹${_accountBalances[_selectedAccountId]?.toStringAsFixed(2) ?? '0.00'}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBankCard(Map<String, dynamic> account) {
    final bool isSelected = _selectedAccountId == account['id'];
    final String accountNumber = account['accountNumber']?.toString() ?? '';
    final String lastFourDigits = accountNumber.length > 4
        ? accountNumber.substring(accountNumber.length - 4)
        : accountNumber;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedAccountId = account['id'];
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 12, bottom: 8, top: 8, left: 4),
        width: 150,
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).primaryColor.withOpacity(0.5)
                : Colors.grey[200]!,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
              spreadRadius: 1,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Bank name with icon
              Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 16,
                    color: isSelected
                        ? Colors.white
                        : Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _getShortBankName(account),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        overflow: TextOverflow.ellipsis,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Balance
              Text(
                '₹${(account['currentBalance'] ?? 0.0).toStringAsFixed(2)}',
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).primaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 4),

              // Account number
              Text(
                '•••• $lastFourDigits',
                style: TextStyle(
                  color: isSelected ? Colors.white70 : Colors.grey[600],
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_bankAccounts.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No bank accounts found')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('${widget.userName}\'s Transactions')),
      body: Column(
        children: [
          // Bank Cards Horizontal List
          SizedBox(
            height: 130,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
              itemCount: _bankAccounts.length,
              itemBuilder: (context, index) {
                return _buildBankCard(_bankAccounts[index]);
              },
            ),
          ),

          // Transactions List
          Expanded(
            child: _buildTransactionList(
              _transactionsByAccount[_selectedAccountId] ?? [],
            ),
          ),
        ],
      ),
    );
  }
}
