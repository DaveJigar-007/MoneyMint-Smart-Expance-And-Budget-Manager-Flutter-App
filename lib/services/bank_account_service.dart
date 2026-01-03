import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/bank_account.dart';

class BankAccountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // List of supported banks
  static const List<String> supportedBanks = [
    'Rajkot Nagarik Sahakari Bank (RNSB)',
    'State Bank of India (SBI)',
    'Bank of Baroda (BOB)',
    'Punjab National Bank (PNB)',
    'Canara Bank',
    'Union Bank of India',
    'Bank of India (BOI)',
    'Indian Bank',
    'Central Bank of India',
    'Indian Overseas Bank (IOB)',
    'UCO Bank',
  ];

  // Default minimum balances per bank (₹)
  static const Map<String, double> defaultMinimumBalances = {
    'Bank of Baroda (BOB)': 2000.0,
    'Rajkot Nagarik Sahakari Bank (RNSB)': 0.0,
    'State Bank of India (SBI)': 0.0,
    'Punjab National Bank (PNB)': 1000.0,
    'Canara Bank': 1000.0,
    'Union Bank of India': 1000.0,
    'Bank of India (BOI)': 1000.0,
    'Indian Bank': 1000.0,
    'Central Bank of India': 1000.0,
    'Indian Overseas Bank (IOB)': 1000.0,
    'UCO Bank': 1000.0,
  };

  static double minimumForBank(String bankName) {
    return defaultMinimumBalances[bankName] ?? 0.0;
  }

  // Get current user ID
  String? get _userId => _auth.currentUser?.uid;

  // Get user's bank accounts collection reference
  CollectionReference<Map<String, dynamic>> _getBankAccountsCollection() {
    if (_userId == null) {
      throw Exception('User not logged in');
    }
    return _firestore
        .collection('users')
        .doc(_userId)
        .collection('bankAccounts');
  }

  // Get transactions collection for a specific bank account
  CollectionReference<Map<String, dynamic>> _getTransactionsCollection(
    String bankAccountId,
  ) {
    if (_userId == null) {
      throw Exception('User not logged in');
    }
    return _firestore
        .collection('users')
        .doc(_userId)
        .collection('bankAccounts')
        .doc(bankAccountId)
        .collection('transactions');
  }

  // Add a new bank account
  Future<void> addBankAccount(BankAccount account) async {
    try {
      final collection = _getBankAccountsCollection();
      final batch = _firestore.batch();

      // If this account should be selected, unselect all others
      if (account.isSelected) {
        final query = await collection
            .where('isSelected', isEqualTo: true)
            .get();
        for (var doc in query.docs) {
          batch.update(doc.reference, {'isSelected': false});
        }
      }

      // Add the new account
      final docRef = collection.doc();
      batch.set(docRef, account.toMap());

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to add bank account: $e');
    }
  }

  // Get all bank accounts for the current user
  Stream<List<BankAccount>> getBankAccounts() {
    return _getBankAccountsCollection()
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          // Convert to list of accounts
          final accounts = snapshot.docs
              .map((doc) => BankAccount.fromMap(doc.id, doc.data()))
              .toList();

          // Sort by isSelected in memory (selected accounts first)
          accounts.sort((a, b) => b.isSelected ? 1 : -1);

          return accounts;
        });
  }

  // Update account selection state
  Future<void> updateAccountSelection(String accountId, bool isSelected) async {
    try {
      final batch = _firestore.batch();
      final collection = _getBankAccountsCollection();

      // If selecting an account, unselect all others first
      if (isSelected) {
        final query = await collection
            .where('isSelected', isEqualTo: true)
            .get();
        for (var doc in query.docs) {
          if (doc.id != accountId) {
            batch.update(doc.reference, {'isSelected': false});
          }
        }
      }

      // Update the target account's selection state
      batch.update(collection.doc(accountId), {
        'isSelected': isSelected,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to update account selection: $e');
    }
  }

  // Get the currently selected account
  Future<BankAccount?> getSelectedAccount() async {
    try {
      final snapshot = await _getBankAccountsCollection()
          .where('isSelected', isEqualTo: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      return BankAccount.fromMap(
        snapshot.docs.first.id,
        snapshot.docs.first.data(),
      );
    } catch (e) {
      throw Exception('Failed to get selected account: $e');
    }
  }

  // Update bank account
  Future<void> updateBankAccount(BankAccount account) async {
    try {
      await _getBankAccountsCollection()
          .doc(account.id)
          .update(account.toMap());
    } catch (e) {
      throw Exception('Failed to update bank account: $e');
    }
  }

  // Delete bank account
  Future<void> deleteBankAccount(String accountId) async {
    try {
      // First delete all transactions for this account
      final transactions = await _getTransactionsCollection(accountId).get();
      final batch = _firestore.batch();

      for (var doc in transactions.docs) {
        batch.delete(doc.reference);
      }

      // Then delete the account
      batch.delete(_getBankAccountsCollection().doc(accountId));

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to delete bank account: $e');
    }
  }

  // Add a transaction to a bank account
  Future<void> addTransaction({
    required String bankAccountId,
    required Map<String, dynamic> transactionData,
  }) async {
    try {
      final transactionRef = _getTransactionsCollection(bankAccountId).doc();
      final now = DateTime.now();

      await _firestore.runTransaction((transaction) async {
        // Read the bank account first (reads must happen before writes in a transaction)
        final accountDoc = await transaction.get(
          _getBankAccountsCollection().doc(bankAccountId),
        );

        double currentBalance = 0.0;
        double minimumBalance = 0.0;
        if (accountDoc.exists) {
          final data = accountDoc.data();
          if (data != null && data['currentBalance'] != null) {
            try {
              currentBalance = (data['currentBalance']).toDouble();
            } catch (_) {
              currentBalance =
                  double.tryParse(data['currentBalance'].toString()) ?? 0.0;
            }
          }
          // read minimumBalance if set
          if (data != null && data['minimumBalance'] != null) {
            try {
              minimumBalance = (data['minimumBalance']).toDouble();
            } catch (_) {
              minimumBalance =
                  double.tryParse(data['minimumBalance'].toString()) ?? 0.0;
            }
          }
        }

        final amount = () {
          try {
            return (transactionData['amount'] ?? 0).toDouble();
          } catch (_) {
            return double.tryParse(transactionData['amount'].toString()) ?? 0.0;
          }
        }();

        final isExpense = transactionData['type'] == 'expense';

        final newBalance = isExpense
            ? currentBalance - amount
            : currentBalance + amount;

        // Prevent transaction if it would reduce balance below minimumBalance
        if (newBalance < minimumBalance) {
          throw Exception(
            'Insufficient funds: this transaction would reduce balance below the minimum required balance of ₹${minimumBalance.toStringAsFixed(2)}.',
          );
        }

        // Now write: add the transaction and update balance
        transaction.set(transactionRef, {
          ...transactionData,
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        });

        if (accountDoc.exists) {
          transaction.update(accountDoc.reference, {
            'currentBalance': newBalance,
            'updatedAt': now.toIso8601String(),
          });
        }
      });
    } catch (e) {
      throw Exception('Failed to add transaction: $e');
    }
  }

  // Get transactions for a bank account
  Stream<QuerySnapshot<Map<String, dynamic>>> getTransactions(
    String bankAccountId,
  ) {
    return _getTransactionsCollection(
      bankAccountId,
    ).orderBy('date', descending: true).snapshots();
  }
}

// Singleton instance
final bankAccountService = BankAccountService();
