// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/bank_account_service.dart';
import '../../models/bank_account.dart';

final _bankAccountService = BankAccountService();

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  String? _selectedAccountId; // null means show all / fallback

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: StreamBuilder<List<BankAccount>>(
        stream: _bankAccountService.getBankAccounts(),
        builder: (context, accountsSnapshot) {
          if (accountsSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final accounts = accountsSnapshot.data ?? [];

          // If user hasn't chosen a specific account yet, default to the selected one
          if (_selectedAccountId == null && accounts.isNotEmpty) {
            final sel = accounts.firstWhere(
              (a) => a.isSelected,
              orElse: () => accounts.first,
            );
            _selectedAccountId = sel.id;
          }

          return Column(
            children: [
              // Accounts selector
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  itemCount: accounts.length,
                  itemBuilder: (context, index) {
                    final acc = accounts[index];
                    final mask = acc.accountNumber.length > 4
                        ? '****${acc.accountNumber.substring(acc.accountNumber.length - 4)}'
                        : acc.accountNumber;

                    final selected = _selectedAccountId == acc.id;
                    final primary = Theme.of(context).primaryColor;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              acc.bankName,
                              style: TextStyle(
                                fontSize: 12,
                                color: selected ? Colors.white : Colors.black,
                              ),
                            ),
                            Text(
                              mask,
                              style: TextStyle(
                                fontSize: 11,
                                color: selected
                                    ? Colors.white70
                                    : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                        selected: selected,
                        selectedColor: primary,
                        backgroundColor: Colors.grey[200],
                        onSelected: (_) =>
                            setState(() => _selectedAccountId = acc.id),
                      ),
                    );
                  },
                ),
              ),

              const Divider(height: 1),

              // Transactions list
              Expanded(
                child: _buildTransactionsList(user?.uid, _selectedAccountId),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTransactionsList(String? userId, String? accountId) {
    if (userId == null) {
      return const Center(child: Text('Please login to view transactions'));
    }

    // If an accountId is selected, stream that account's transactions
    Stream<QuerySnapshot<Map<String, dynamic>>> txStream;
    if (accountId != null) {
      txStream = _bankAccountService.getTransactions(accountId);
    } else {
      // Fallback to legacy global transactions collection
      txStream = FirebaseFirestore.instance
          .collection('transactions')
          .doc(userId)
          .collection('user_transactions')
          .orderBy('date', descending: true)
          .snapshots();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: txStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No transactions found'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final data = docs[index].data();

            // parse fields safely
            final rawAmount = data['amount'];
            double amount = 0;
            try {
              amount = (rawAmount ?? 0).toDouble();
            } catch (_) {
              amount = double.tryParse(rawAmount?.toString() ?? '0') ?? 0;
            }

            final type = (data['type'] ?? 'expense').toString();
            final displayAmount = type == 'expense' ? -amount : amount;

            DateTime date = DateTime.now();
            final rawDate = data['date'];
            if (rawDate is Timestamp) {
              date = rawDate.toDate();
            } else if (rawDate is String)
              date = DateTime.tryParse(rawDate) ?? date;

            final description = data['description'] ?? '';
            final category = data['category'] ?? '';

            // Slim compact row with proper category icon
            final icon = _categoryIcon(category.toString());
            final accountNumber = data['accountNumber']?.toString();

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: displayAmount < 0
                          ? Colors.red[50]
                          : Colors.green[50],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: displayAmount < 0
                          ? Colors.red[400]
                          : Colors.green[700],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          description.isNotEmpty ? description : category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${DateFormat('MMM dd, yyyy').format(date)}${accountNumber != null ? ' • ${_maskAccount(accountNumber)}' : ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${displayAmount < 0 ? '-' : ''}₹${displayAmount.abs().toStringAsFixed(2)}',
                    style: TextStyle(
                      color: displayAmount < 0 ? Colors.red : Colors.green,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  IconData _categoryIcon(String category) {
    final key = category.toLowerCase();
    if (key.contains('food')) return Icons.restaurant;
    if (key.contains('shop') || key.contains('shopping')) {
      return Icons.shopping_cart;
    }
    if (key.contains('transport') ||
        key.contains('taxi') ||
        key.contains('car')) {
      return Icons.directions_car;
    }
    if (key.contains('home') || key.contains('housing')) return Icons.home;
    if (key.contains('health') || key.contains('medical')) {
      return Icons.medical_services;
    }
    if (key.contains('entertain') || key.contains('movie')) return Icons.movie;
    if (key.contains('bill')) return Icons.receipt_long;
    if (key.contains('education') || key.contains('school')) {
      return Icons.school;
    }
    if (key.contains('gift')) return Icons.card_giftcard;
    if (key.contains('travel') || key.contains('flight')) {
      return Icons.flight_takeoff;
    }
    if (key.contains('personal')) return Icons.person;
    if (key.contains('salary') || key.contains('pay')) return Icons.work;
    if (key.contains('business')) return Icons.business;
    if (key.contains('savings') || key.contains('save')) return Icons.savings;
    if (key.contains('investment') || key.contains('invest')) {
      return Icons.trending_up;
    }
    if (key.contains('freelance') || key.contains('remote')) {
      return Icons.computer;
    }
    if (key.contains('bonus')) return Icons.celebration;
    return Icons.category;
  }

  String _maskAccount(String accountNumber) {
    if (accountNumber.length <= 4) return accountNumber;
    return '****${accountNumber.substring(accountNumber.length - 4)}';
  }
}
