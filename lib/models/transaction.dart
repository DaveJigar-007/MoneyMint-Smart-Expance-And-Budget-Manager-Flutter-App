import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp, FieldValue;

enum TransactionType { income, expense }

enum Category {
  // Expense categories
  food,
  shopping,
  transport,
  housing,
  health,
  entertainment,
  
  // Income categories
  salary,
  otherIncome,
  business,
  savings,
  gift,
  investment,
  freelance,
  bonus,

  // Add 'none' as a default category
  none,
}

class Transaction {
  final String id;
  final double amount;
  final String description;
  final DateTime date;
  final Category category;
  final TransactionType type;
  final String userId; // Add user ID to associate transactions with users
  final String bankAccountId; // Add bank account ID to associate transactions with bank accounts
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Transaction({
    required this.id,
    required this.amount,
    required this.description,
    required this.date,
    required this.category,
    required this.type,
    required this.userId,
    required this.bankAccountId,
    this.createdAt,
    this.updatedAt,
  });

  // Create a new empty transaction
  factory Transaction.empty() {
    return Transaction(
      id: '',
      amount: 0.0,
      description: '',
      date: DateTime.now(),
      category: Category.none,
      type: TransactionType.expense,
      userId: '',
      bankAccountId: '',
      createdAt: null,
      updatedAt: null,
    );
  }

  // Convert a Transaction into a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'description': description,
      'date': Timestamp.fromDate(date),
      'category': category.toString().split('.').last,
      'type': type.toString().split('.').last,
      'userId': userId,
      'bankAccountId': bankAccountId,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // Create a Transaction from a Map (from Firestore)
  factory Transaction.fromMap(Map<String, dynamic> map, {String? id}) {
    try {
      return Transaction(
        id: id ?? map['id'] ?? '',
        amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
        description: map['description']?.toString() ?? '',
        date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
        category: _parseCategory(map['category']?.toString() ?? ''),
        type: _parseTransactionType(map['type']?.toString() ?? ''),
        userId: map['userId']?.toString() ?? '',
        bankAccountId: map['bankAccountId']?.toString() ?? '',
        createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
        updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      );
    } catch (e) {
      debugPrint('Error parsing transaction: $e');
      rethrow;
    }
  }

  // Helper method to parse category from string
  static Category _parseCategory(String categoryStr) {
    try {
      return Category.values.firstWhere(
        (e) => e.toString() == 'Category.${categoryStr.toLowerCase()}',
        orElse: () => Category.none,
      );
    } catch (e) {
      return Category.none;
    }
  }

  // Helper method to parse transaction type from string
  static TransactionType _parseTransactionType(String typeStr) {
    try {
      return TransactionType.values.firstWhere(
        (e) => e.toString() == 'TransactionType.${typeStr.toLowerCase()}',
        orElse: () => TransactionType.expense,
      );
    } catch (e) {
      return TransactionType.expense;
    }
  }

  // Create a copy of the transaction with updated fields
  Transaction copyWith({
    String? id,
    double? amount,
    String? description,
    DateTime? date,
    Category? category,
    TransactionType? type,
    String? userId,
    String? bankAccountId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      date: date ?? this.date,
      category: category ?? this.category,
      type: type ?? this.type,
      userId: userId ?? this.userId,
      bankAccountId: bankAccountId ?? this.bankAccountId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Get category name as string
  String get categoryName {
    switch (category) {
      case Category.food:
        return 'Food';
      case Category.shopping:
        return 'Shopping';
      case Category.transport:
        return 'Transport';
      case Category.housing:
        return 'Housing';
      case Category.health:
        return 'Health';
      case Category.entertainment:
        return 'Entertainment';
      case Category.salary:
        return 'Salary';
      case Category.otherIncome:
        return 'Other Income';
      case Category.business:
        return 'Business';
      case Category.savings:
        return 'Savings';
      case Category.gift:
        return 'Gift';
      case Category.investment:
        return 'Investment';
      case Category.freelance:
        return 'Freelance';
      case Category.bonus:
        return 'Bonus';
      case Category.none:
        return 'Uncategorized';
    }
  }

  // Get transaction type as string
  String get typeName => type == TransactionType.income ? 'Income' : 'Expense';

  // Get transaction color based on type
  Color get typeColor => type == TransactionType.income ? Colors.green : Colors.red;

  // Format date
  String get formattedDate => '${date.day}/${date.month}/${date.year}';

  // Check if transaction is valid
  bool get isValid =>
      id.isNotEmpty &&
      amount > 0 &&
      description.isNotEmpty &&
      category != Category.none &&
      userId.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Transaction &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Transaction{id: $id, amount: $amount, description: $description, date: $date, category: $category, type: $type, userId: $userId}';
  }

  // Get category icon
  IconData get categoryIcon {
    switch (category) {
      case Category.food:
        return Icons.restaurant;
      case Category.shopping:
        return Icons.shopping_cart;
      case Category.transport:
        return Icons.directions_car;
      case Category.housing:
        return Icons.home;
      case Category.health:
        return Icons.medical_services;
      case Category.entertainment:
        return Icons.movie;
      case Category.salary:
        return Icons.work;
      case Category.otherIncome:
        return Icons.attach_money;
      case Category.business:
        return Icons.business;
      case Category.savings:
        return Icons.account_balance_wallet;
      case Category.gift:
        return Icons.card_giftcard;
      case Category.investment:
        return Icons.trending_up;
      case Category.freelance:
        return Icons.computer;
      case Category.bonus:
        return Icons.celebration;
      case Category.none:
        return Icons.category;
    }
  }

  // Get amount with proper sign
  String get formattedAmount {
    final isExpense = type == TransactionType.expense;
    return '${isExpense ? '-' : '+'}₹${amount.abs().toStringAsFixed(2)}';
  }

  // Get color based on transaction type
  Color get amountColor {
    return type == TransactionType.expense ? Colors.red : Colors.green;
  }
}
