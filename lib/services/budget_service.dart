import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BudgetService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get user's budget document reference
  DocumentReference<Map<String, dynamic>> _getUserBudgetDoc() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw Exception('User not logged in');
    }
    return _firestore.collection('budgets').doc(userId);
  }

  // Get current month and year as string (YYYY-MM)
  String _getCurrentMonthYear() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  // Save the month rollover timestamp to prevent repeated rollovers
  Future<void> saveMonthRolloverTimestamp(String monthYear) async {
    try {
      final userDoc = _getUserBudgetDoc();
      await userDoc.update({
        'lastProcessedMonth': monthYear,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to save month rollover timestamp: $e');
    }
  }

  // Save or update monthly budget
  Future<void> saveMonthlyBudget(double amount) async {
    try {
      final currentMonthYear = _getCurrentMonthYear();
      final userDoc = _getUserBudgetDoc();

      await _firestore.runTransaction((transaction) async {
        // Get the current document
        final doc = await transaction.get(userDoc);
        final data = doc.data() ?? {};

        // Get the current month's budget data
        final monthlyBudgets = Map<String, dynamic>.from(
          data['monthlyBudgets'] ?? {},
        );
        final currentBudget = Map<String, dynamic>.from(
          monthlyBudgets[currentMonthYear] ?? {},
        );

        // Calculate remaining budget from previous month if it's a new month
        if (!monthlyBudgets.containsKey(currentMonthYear)) {
          final now = DateTime.now();
          final lastMonth = DateTime(now.year, now.month - 1, now.day);
          final lastMonthYear =
              '${lastMonth.year}-${lastMonth.month.toString().padLeft(2, '0')}';

          if (monthlyBudgets.containsKey(lastMonthYear)) {
            final lastMonthBudget = Map<String, dynamic>.from(
              monthlyBudgets[lastMonthYear],
            );
            final lastMonthAllocated = (lastMonthBudget['monthlyBudget'] ?? 0)
                .toDouble();
            final lastMonthSpent = (lastMonthBudget['totalSpent'] ?? 0)
                .toDouble();
            final remaining = lastMonthAllocated - lastMonthSpent;

            if (remaining > 0) {
              // Add remaining to the new month's budget
              amount += remaining;
            }
          }
        }

        // Update current month's budget
        monthlyBudgets[currentMonthYear] = {
          ...currentBudget,
          'monthlyBudget': amount,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Update the document
        transaction.set(userDoc, {
          'monthlyBudget': amount, // Keep for backward compatibility
          'monthlyBudgets': monthlyBudgets,
          'currentMonthYear': currentMonthYear,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      throw Exception('Failed to save budget: $e');
    }
  }

  // Save or update category budget
  Future<void> saveCategoryBudget(
    String category,
    double allocated,
    double spent,
  ) async {
    try {
      final userDoc = _getUserBudgetDoc();

      // Use a transaction to ensure data consistency
      await _firestore.runTransaction((transaction) async {
        // Get the current document
        final doc = await transaction.get(userDoc);

        // Initialize categories list
        List<dynamic> categories = [];
        if (doc.exists) {
          categories = List<Map<String, dynamic>>.from(
            doc.data()?['categories'] ?? [],
          );
        }

        // Check if category already exists
        final index = categories.indexWhere((cat) => cat['name'] == category);
        final now = DateTime.now();

        if (index != -1) {
          // Update existing category
          categories[index] = {
            'name': category,
            'allocated': allocated,
            'spent':
                categories[index]['spent'] ?? 0.0, // Keep existing spent amount
            'updatedAt': now
                .toIso8601String(), // Use string timestamp instead of FieldValue
          };
        } else {
          // Add new category
          categories.add({
            'name': category,
            'allocated': allocated,
            'spent': spent,
            'createdAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
          });
        }

        // Update the document with the modified categories
        transaction.update(userDoc, {
          'categories': categories,
          'updatedAt':
              FieldValue.serverTimestamp(), // This is fine at the document level
        });
      });
    } catch (e) {
      throw Exception('Failed to save category budget: $e');
    }
  }

  // Check if we need to reset the budget for a new month
  Future<void> _checkAndResetForNewMonth(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (!doc.exists) return;

    final data = doc.data()!;
    final lastResetMonth = data['lastResetMonth'] as String?;
    final currentMonthYear = _getCurrentMonthYear();

    // If it's a new month, reset the budget
    if (lastResetMonth != currentMonthYear) {
      final userDoc = _getUserBudgetDoc();
      final now = DateTime.now();

      // Get the previous month's data if it exists
      final monthlyBudgets = Map<String, dynamic>.from(
        data['monthlyBudgets'] ?? {},
      );
      final previousMonthData =
          monthlyBudgets[lastResetMonth] as Map<String, dynamic>?;

      // Calculate any remaining budget to carry over
      double remainingBudget = 0.0;
      if (previousMonthData != null) {
        final previousBudget = (previousMonthData['monthlyBudget'] ?? 0)
            .toDouble();
        final previousSpent = (previousMonthData['totalSpent'] ?? 0).toDouble();
        remainingBudget = (previousBudget - previousSpent).clamp(
          0.0,
          double.infinity,
        );
      }

      // Reset categories' spent amounts for the new month
      final categories = List<Map<String, dynamic>>.from(
        data['categories'] ?? [],
      );
      final resetCategories = categories
          .map(
            (cat) => {...cat, 'spent': 0.0, 'updatedAt': now.toIso8601String()},
          )
          .toList();

      // Update the document with reset data
      await userDoc.update({
        'categories': resetCategories,
        'lastResetMonth': currentMonthYear,
        'monthlyBudgets.$currentMonthYear': {
          'monthlyBudget': remainingBudget, // Carry over remaining budget
          'totalSpent': 0.0,
          'carriedOver': remainingBudget,
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Get user's budget data
  Future<Map<String, dynamic>> getBudgetData() async {
    try {
      final userDoc = _getUserBudgetDoc();
      final doc = await userDoc.get();

      // Check and reset budget if it's a new month
      await _checkAndResetForNewMonth(doc);

      // Get fresh data after potential reset
      final freshDoc = await userDoc.get();

      if (!freshDoc.exists) {
        // Initialize with default values if document doesn't exist
        final now = DateTime.now();
        await userDoc.set({
          'monthlyBudget': 0.0,
          'categories': [],
          'lastResetMonth': _getCurrentMonthYear(),
          'monthlyBudgets': {
            _getCurrentMonthYear(): {
              'monthlyBudget': 0.0,
              'totalSpent': 0.0,
              'createdAt': now.toIso8601String(),
              'updatedAt': now.toIso8601String(),
            },
          },
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        });

        return {
          'monthlyBudget': 0.0,
          'categories': [],
          'lastResetMonth': _getCurrentMonthYear(),
          'monthlyBudgets': {
            _getCurrentMonthYear(): {
              'monthlyBudget': 0.0,
              'totalSpent': 0.0,
              'createdAt': now.toIso8601String(),
              'updatedAt': now.toIso8601String(),
            },
          },
        };
      }

      return freshDoc.data() ?? {};
    } catch (e) {
      throw Exception('Failed to get budget data: $e');
    }
  }

  // Update spent amount for a category
  Future<void> updateSpentAmount(String category, double amount) async {
    try {
      final userDoc = _getUserBudgetDoc();
      final now = DateTime.now();
      final currentMonthYear = _getCurrentMonthYear();

      // Use a transaction to ensure data consistency
      await _firestore.runTransaction((transaction) async {
        // Get the current document
        final doc = await transaction.get(userDoc);
        final data = doc.data() ?? {};

        // Initialize categories list
        List<dynamic> categories = [];
        if (doc.exists) {
          categories = List<Map<String, dynamic>>.from(
            data['categories'] ?? [],
          );
        } else {
          // Create document if it doesn't exist
          transaction.set(userDoc, {
            'monthlyBudget': 0.0,
            'categories': [],
            'lastResetMonth': currentMonthYear,
            'monthlyBudgets': {
              currentMonthYear: {
                'monthlyBudget': 0.0,
                'totalSpent': 0.0,
                'createdAt': now.toIso8601String(),
                'updatedAt': now.toIso8601String(),
              },
            },
            'createdAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
          });
        }

        // Initialize monthly budgets if not exists
        Map<String, dynamic> monthlyBudgets = Map<String, dynamic>.from(
          data['monthlyBudgets'] ?? {},
        );
        if (!monthlyBudgets.containsKey(currentMonthYear)) {
          monthlyBudgets[currentMonthYear] = {
            'monthlyBudget': data['monthlyBudget'] ?? 0.0,
            'totalSpent': 0.0,
            'createdAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
          };
        }

        // Update current month's total spent
        final currentMonth = Map<String, dynamic>.from(
          monthlyBudgets[currentMonthYear] ?? {},
        );
        final currentSpent = (currentMonth['totalSpent'] ?? 0).toDouble();

        // Find and update the category
        final index = categories.indexWhere((cat) => cat['name'] == category);
        final double previousSpent = index != -1
            ? (categories[index]['spent'] ?? 0.0)
            : 0.0;

        if (index != -1) {
          // Preserve existing allocated amount if it exists
          final double allocated = categories[index]['allocated'] ?? 0.0;
          categories[index] = {
            'name': category,
            'allocated': allocated,
            'spent': amount,
            'updatedAt': now.toIso8601String(),
          };
        } else {
          // If category doesn't exist, add it with default values
          categories.add({
            'name': category,
            'allocated': 0.0,
            'spent': amount,
            'createdAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
          });
        }

        // Calculate the difference in spent amount
        final spentDifference = amount - previousSpent;

        // Update the document with new values
        transaction.update(userDoc, {
          'categories': categories,
          'monthlyBudgets.$currentMonthYear.totalSpent':
              currentSpent + spentDifference,
          'monthlyBudgets.$currentMonthYear.updatedAt': now.toIso8601String(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      throw Exception('Failed to update spent amount: $e');
    }
  }

  // Reset all category spent amounts to 0
  Future<void> resetAllCategorySpentAmounts() async {
    try {
      final userDoc = _getUserBudgetDoc();
      final now = DateTime.now();
      final currentMonthYear = _getCurrentMonthYear();

      // Use a transaction to ensure data consistency
      await _firestore.runTransaction((transaction) async {
        // Get the current document
        final doc = await transaction.get(userDoc);
        final data = doc.data() ?? {};

        // Initialize categories list
        List<dynamic> categories = [];
        if (doc.exists) {
          categories = List<Map<String, dynamic>>.from(
            data['categories'] ?? [],
          );
        }

        // Reset spent amounts for all categories
        final resetCategories = categories
            .map(
              (cat) => {
                ...cat,
                'spent': 0.0,
                'updatedAt': now.toIso8601String(),
              },
            )
            .toList();

        // Initialize monthly budgets if not exists
        Map<String, dynamic> monthlyBudgets = Map<String, dynamic>.from(
          data['monthlyBudgets'] ?? {},
        );
        if (!monthlyBudgets.containsKey(currentMonthYear)) {
          monthlyBudgets[currentMonthYear] = {
            'monthlyBudget': data['monthlyBudget'] ?? 0.0,
            'totalSpent': 0.0,
            'createdAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
          };
        }

        // Update the document with reset categories and reset total spent
        transaction.update(userDoc, {
          'categories': resetCategories,
          'monthlyBudgets.$currentMonthYear.totalSpent': 0.0,
          'monthlyBudgets.$currentMonthYear.updatedAt': now.toIso8601String(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      throw Exception('Failed to reset all category spent amounts: $e');
    }
  }
}
