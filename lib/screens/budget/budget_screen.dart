import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// ignore: depend_on_referenced_packages
import 'package:rxdart/rxdart.dart';
import 'dart:async';
import '../../services/budget_service.dart';
import '../../widgets/app_scaffold.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _BudgetScreenState createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final BudgetService _budgetService = BudgetService();
  late TextEditingController budgetController;

  double monthlyBudget = 0.0;
  bool isLoading = true;
  List<Map<String, dynamic>> categories = [];
  StreamSubscription? _transactionStreamSubscription;

  // Category data with colors and icons matching the transaction screen
  final List<Map<String, dynamic>> _expenseCategories = [
    {
      'name': 'Food',
      'icon': Icons.restaurant,
      'color': const Color(0xFF4285F4),
      'allocated': 0.0,
      'spent': 0.0,
    },
    {
      'name': 'Shopping',
      'icon': Icons.shopping_cart,
      'color': const Color(0xFFFF9800),
      'allocated': 0.0,
      'spent': 0.0,
    },
    {
      'name': 'Transport',
      'icon': Icons.directions_car,
      'color': const Color(0xFF0F9D58),
      'allocated': 0.0,
      'spent': 0.0,
    },
    {
      'name': 'Housing',
      'icon': Icons.home,
      'color': const Color(0xFF9C27B0),
      'allocated': 0.0,
      'spent': 0.0,
    },
    {
      'name': 'Health',
      'icon': Icons.medical_services,
      'color': const Color(0xFFE91E63),
      'allocated': 0.0,
      'spent': 0.0,
    },
    {
      'name': 'Entertainment',
      'icon': Icons.movie,
      'color': const Color(0xFF9C27B0),
      'allocated': 0.0,
      'spent': 0.0,
    },
    {
      'name': 'Bills',
      'icon': Icons.receipt_long,
      'color': const Color(0xFF607D8B),
      'allocated': 0.0,
      'spent': 0.0,
    },
    {
      'name': 'Education',
      'icon': Icons.school,
      'color': const Color(0xFF795548),
      'allocated': 0.0,
      'spent': 0.0,
    },
    {
      'name': 'Gifts',
      'icon': Icons.card_giftcard,
      'color': const Color(0xFFE91E63),
      'allocated': 0.0,
      'spent': 0.0,
    },
    {
      'name': 'Travel',
      'icon': Icons.flight_takeoff,
      'color': const Color(0xFF3F51B5),
      'allocated': 0.0,
      'spent': 0.0,
    },
    {
      'name': 'Personal',
      'icon': Icons.person,
      'color': const Color(0xFF9C27B0),
      'allocated': 0.0,
      'spent': 0.0,
    },
    {
      'name': 'Other',
      'icon': Icons.category,
      'color': const Color(0xFF9E9E9E),
      'allocated': 0.0,
      'spent': 0.0,
    },
  ];

  @override
  void initState() {
    super.initState();
    budgetController = TextEditingController();
    // Initialize categories immediately
    _initializeCategories();
    // Set loading to false immediately for instant UI display
    isLoading = false;
    // Load data asynchronously in background
    _loadBudgetDataFast();
    _listenToTransactionUpdates();
  }

  @override
  void dispose() {
    budgetController.dispose();
    _transactionStreamSubscription?.cancel();
    super.dispose();
  }

  // Initialize categories with default values
  void _initializeCategories() {
    // Create a map of existing categories for quick lookup
    final existingCategories = <String, Map<String, dynamic>>{};
    for (final cat in categories) {
      existingCategories[cat['name']] = Map<String, dynamic>.from(cat);
    }

    // Create new categories list with defaults or existing values
    categories = _expenseCategories.map((defaultCat) {
      final categoryName = defaultCat['name'];
      if (existingCategories.containsKey(categoryName)) {
        // Preserve existing category data but ensure all required fields exist
        return {
          'name': categoryName,
          'icon': defaultCat['icon'],
          'color': defaultCat['color'],
          'allocated': (existingCategories[categoryName]!['allocated'] ?? 0)
              .toDouble(),
          'spent': (existingCategories[categoryName]!['spent'] ?? 0).toDouble(),
        };
      } else {
        // Create new category with default values
        return Map<String, dynamic>.from(defaultCat);
      }
    }).toList();
  }

  // Check and handle month rollover (execute only once per month)
  Future<void> _handleMonthRollover(Map<String, dynamic> budgetData) async {
    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month}';
    final lastProcessedMonth = budgetData['lastProcessedMonth'] ?? '';

    // Only process if month has changed
    if (lastProcessedMonth != currentMonth) {
      try {
        // Get current month's budget and spent amounts
        final currentMonthlyBudget = (budgetData['monthlyBudget'] ?? 0)
            .toDouble();
        final savedCategories = List<Map<String, dynamic>>.from(
          budgetData['categories'] ?? [],
        );

        // Calculate total spent in current month
        double totalSpent = 0.0;
        for (var cat in savedCategories) {
          totalSpent += (cat['spent'] ?? 0.0) as double;
        }

        // Calculate remaining budget from last month
        final remainingBudget = currentMonthlyBudget - totalSpent;

        // New month's budget = old budget + remaining (if positive)
        final newMonthlyBudget =
            currentMonthlyBudget + (remainingBudget > 0 ? remainingBudget : 0);

        debugPrint(
          'Month Rollover: Previous Budget: ₹$currentMonthlyBudget | Spent: ₹$totalSpent | Remaining: ₹$remainingBudget | New Budget: ₹$newMonthlyBudget',
        );

        // Reset all category spent amounts to 0 for the new month
        final resetCategories = savedCategories.map((cat) {
          return {
            ...cat,
            'spent': 0.0, // Reset spent amount to 0
            'updatedAt': DateTime.now().toIso8601String(),
          };
        }).toList();

        // Save updated monthly budget with remaining amount added
        await _budgetService.saveMonthlyBudget(newMonthlyBudget);
        
        // Save the reset categories
        for (final category in resetCategories) {
          await _budgetService.saveCategoryBudget(
            category['name'],
            category['allocated'] ?? 0.0,
            0.0, // Spent amount reset to 0
          );
        }

        // Save the current month as processed to prevent repeated rollovers
        await _budgetService.saveMonthRolloverTimestamp(currentMonth);

        // Update UI after rollover
        if (mounted) {
          setState(() {
            monthlyBudget = newMonthlyBudget;
            budgetController.text = newMonthlyBudget.toStringAsFixed(0);
            // Update local categories with reset spent amounts
            for (int i = 0; i < categories.length; i++) {
              categories[i] = {
                ...categories[i],
                'spent': 0.0, // Reset spent amount to 0
              };
            }
          });
        }

        if (kDebugMode) {
          print(
            'Month rollover completed for $currentMonth. Previous budget: ₹$currentMonthlyBudget, Remaining: ₹$remainingBudget, New budget: ₹$newMonthlyBudget',
          );
          print('All category spent amounts have been reset to 0');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error processing month rollover: $e'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        if (kDebugMode) {
          print('Month rollover error: $e');
        }
      }
    }
  }

  // Load budget data fast - only load budget, not transactions
  Future<void> _loadBudgetDataFast() async {
    if (!mounted) return;

    try {
      // Load budget data
      final budgetData = await _budgetService.getBudgetData();

      // Check and handle month rollover (only once per month)
      await _handleMonthRollover(budgetData);

      // Reload budget data after potential rollover
      final updatedBudgetData = await _budgetService.getBudgetData();

      // Update monthly budget
      final newMonthlyBudget = (updatedBudgetData['monthlyBudget'] ?? 0)
          .toDouble();

      // Apply saved budget allocations
      final savedCategories = List<Map<String, dynamic>>.from(
        updatedBudgetData['categories'] ?? [],
      );

      // Create a map of saved categories for quick lookup
      final savedCategoriesMap = {
        for (var cat in savedCategories) cat['name']: cat,
      };

      // Update categories with saved data
      for (int i = 0; i < categories.length; i++) {
        final categoryName = categories[i]['name'];
        if (savedCategoriesMap.containsKey(categoryName)) {
          categories[i] = {
            ...categories[i],
            'allocated': (savedCategoriesMap[categoryName]!['allocated'] ?? 0)
                .toDouble(),
            'spent': (savedCategoriesMap[categoryName]!['spent'] ?? 0)
                .toDouble(),
          };
        }
      }

      // Update state
      if (mounted) {
        setState(() {
          monthlyBudget = newMonthlyBudget;
          budgetController.text = newMonthlyBudget.toStringAsFixed(0);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load budget data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Listen to transaction updates in real-time
  void _listenToTransactionUpdates() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _transactionStreamSubscription = _buildTransactionStream(user.uid).listen(
      (spentAmounts) {
        if (!mounted) return;

        // Update categories with real-time spent amounts
        final updatedCategories = <Map<String, dynamic>>[];

        for (final category in categories) {
          final categoryName = category['name'].toString().toLowerCase();
          final spent = spentAmounts[categoryName] ?? 0.0;

          updatedCategories.add({...category, 'spent': spent});
        }

        setState(() {
          categories = updatedCategories;
        });
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading transactions: $error')),
          );
        }
      },
    );
  }

  // Build a stream that combines all transaction data
  Stream<Map<String, double>> _buildTransactionStream(String userId) {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);

    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('bankAccounts')
        .snapshots()
        .asyncExpand((accountsSnapshot) {
          if (accountsSnapshot.docs.isEmpty) {
            return Stream.value(<String, double>{});
          }

          // Create streams for each account's transactions
          final transactionStreams = accountsSnapshot.docs.map((accountDoc) {
            return accountDoc.reference
                .collection('transactions')
                .where('type', isEqualTo: 'expense')
                .snapshots()
                .map((transactionsSnapshot) {
                  final spentAmounts = <String, double>{};

                  for (final doc in transactionsSnapshot.docs) {
                    final data = doc.data();
                    final date = data['date'] as Timestamp?;

                    // Filter by current month in code
                    if (date != null &&
                        date.millisecondsSinceEpoch >=
                            firstDayOfMonth.millisecondsSinceEpoch) {
                      final categoryName = data['category']
                          ?.toString()
                          .toLowerCase();
                      final amount =
                          (data['amount'] as num?)?.abs().toDouble() ?? 0.0;

                      if (categoryName != null && amount > 0) {
                        spentAmounts[categoryName] =
                            (spentAmounts[categoryName] ?? 0.0) + amount;
                      }
                    }
                  }

                  return spentAmounts;
                });
          }).toList();

          // Combine all streams
          if (transactionStreams.isEmpty) {
            return Stream.value(<String, double>{});
          }

          return Rx.combineLatestList(transactionStreams).map((listOfMaps) {
            final combined = <String, double>{};
            for (final map in listOfMaps) {
              for (final entry in map.entries) {
                combined[entry.key] =
                    (combined[entry.key] ?? 0.0) + entry.value;
              }
            }
            return combined;
          });
        });
  }

  // Load budget data from Firestore
  Future<void> _loadBudgetData() async {
    if (!mounted) return;

    try {
      setState(() => isLoading = true);

      // Initialize with default categories first
      _initializeCategories();

      // Load budget data
      final budgetData = await _budgetService.getBudgetData();

      // Update monthly budget
      final newMonthlyBudget = (budgetData['monthlyBudget'] ?? 0).toDouble();

      // Apply saved budget allocations
      final savedCategories = List<Map<String, dynamic>>.from(
        budgetData['categories'] ?? [],
      );

      // Create a map of saved categories for quick lookup
      final savedCategoriesMap = {
        for (var cat in savedCategories) cat['name']: cat,
      };

      // Update categories with saved data
      for (int i = 0; i < categories.length; i++) {
        final categoryName = categories[i]['name'];
        if (savedCategoriesMap.containsKey(categoryName)) {
          categories[i] = {
            ...categories[i],
            'allocated': (savedCategoriesMap[categoryName]!['allocated'] ?? 0)
                .toDouble(),
            'spent': (savedCategoriesMap[categoryName]!['spent'] ?? 0)
                .toDouble(),
          };
        }
      }

      // Update state once with all changes
      if (mounted) {
        setState(() {
          monthlyBudget = newMonthlyBudget;
          budgetController.text = monthlyBudget.toStringAsFixed(0);
        });
      }

      // Then load and update with transaction data
      await _loadTransactionData();

      if (mounted) {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load budget data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateBudget() async {
    final newBudget = double.tryParse(budgetController.text) ?? 0.0;
    if (newBudget > 0) {
      try {
        await _budgetService.saveMonthlyBudget(newBudget);
        setState(() {
          monthlyBudget = newBudget;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Budget updated successfully!'),
              backgroundColor: Color(0xFF274647),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update budget: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid budget amount'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Load transaction data to update spent amounts
  Future<void> _loadTransactionData() async {
    if (!mounted) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final now = DateTime.now();
      final firstDayOfMonth = Timestamp.fromDate(
        DateTime(now.year, now.month, 1),
      );

      // Get all bank accounts for the user
      final bankAccountsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('bankAccounts')
          .get();

      // Create a map to track spent amounts by category
      final spentAmounts = <String, double>{};

      // Process transactions from all bank accounts
      for (final accountDoc in bankAccountsSnapshot.docs) {
        final transactionsSnapshot = await accountDoc.reference
            .collection('transactions')
            .where('type', isEqualTo: 'expense')
            .get();

        for (final doc in transactionsSnapshot.docs) {
          final data = doc.data();
          final date = data['date'] as Timestamp?;

          if (date != null &&
              date.millisecondsSinceEpoch >=
                  firstDayOfMonth.millisecondsSinceEpoch) {
            final categoryName = data['category']?.toString().toLowerCase();
            final amount = (data['amount'] as num?)?.abs().toDouble() ?? 0.0;

            if (categoryName != null && amount > 0) {
              spentAmounts[categoryName] =
                  (spentAmounts[categoryName] ?? 0.0) + amount;
            }
          }
        }
      }

      // Update categories with new spent amounts
      final updatedCategories = <Map<String, dynamic>>[];

      for (final category in categories) {
        final categoryName = category['name'].toString().toLowerCase();
        final spent = spentAmounts[categoryName] ?? 0.0;

        updatedCategories.add({...category, 'spent': spent});

        // Update Firestore if there are transactions for this category
        if (spent > 0) {
          await _budgetService.updateSpentAmount(category['name'], spent);
        }
      }

      // Update state once with all changes
      if (mounted) {
        setState(() {
          categories = updatedCategories;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading transactions: $e')),
        );
      }
    }
  }

  // Reset all category spent amounts manually
  Future<void> _resetCategorySpentAmounts() async {
    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reset All Spent Amounts'),
          content: const Text(
            'This will reset all category spent amounts to ₹0. This action cannot be undone. Do you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Reset'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await _budgetService.resetAllCategorySpentAmounts();
        
        // Update local state to reflect the reset
        if (mounted) {
          setState(() {
            for (int i = 0; i < categories.length; i++) {
              categories[i] = {
                ...categories[i],
                'spent': 0.0,
              };
            }
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All spent amounts have been reset to ₹0'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reset spent amounts: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  double getTotalSpent() {
    // ignore: avoid_types_as_parameter_names
    return categories.fold(0.0, (sum, item) {
      final spent = item['spent'];
      return sum + (spent is int ? spent.toDouble() : (spent ?? 0.0));
    });
  }

  // Show dialog to edit category budget
  Future<void> _showEditBudgetDialog(Map<String, dynamic> category) async {
    // Check if monthly budget is set
    if (monthlyBudget <= 0) {
      if (mounted) {
        // ignore: use_build_context_synchronously
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Monthly Budget Required'),
            content: const Text(
              'Please set your monthly budget before setting category budgets.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final TextEditingController amountController = TextEditingController(
      text: category['allocated'] > 0
          ? category['allocated'].toStringAsFixed(0)
          : '',
    );

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set Budget for ${category['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monthly Budget: ₹${monthlyBudget.toStringAsFixed(0)}'),
            const SizedBox(height: 8),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Category Budget',
                prefixText: '₹ ',
                border: const OutlineInputBorder(),
                hintText: 'Enter amount',
                suffixText: 'of ₹${monthlyBudget.toStringAsFixed(0)}',
              ),
            ),
            if (monthlyBudget > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Remaining budget: ₹${(monthlyBudget - getTotalAllocated() + (category['allocated'] ?? 0)).toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newAmount = double.tryParse(amountController.text) ?? 0.0;

              // Calculate total allocated including the new amount
              final currentAllocated = getTotalAllocated();
              final currentCategoryAllocated = category['allocated'] ?? 0.0;
              final totalAfterUpdate =
                  currentAllocated - currentCategoryAllocated + newAmount;

              if (totalAfterUpdate > monthlyBudget) {
                if (mounted) {
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Total allocated amount (₹${totalAfterUpdate.toStringAsFixed(0)}) exceeds monthly budget (₹${monthlyBudget.toStringAsFixed(0)})',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return;
              }

              // Update the category in the list
              final updatedCategories = List<Map<String, dynamic>>.from(
                categories,
              );
              final index = updatedCategories.indexWhere(
                (c) => c['name'] == category['name'],
              );

              if (index != -1) {
                updatedCategories[index]['allocated'] = newAmount;

                setState(() {
                  categories = updatedCategories;
                });

                // Save to Firestore
                await _budgetService.saveCategoryBudget(
                  category['name'],
                  newAmount,
                  category['spent'],
                );

                if (mounted) {
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Category budget updated successfully!'),
                      backgroundColor: Color(0xFF274647),
                    ),
                  );
                }
              }

              if (mounted) {
                // ignore: use_build_context_synchronously
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Build category item widget
  Widget _buildCategoryItem(Map<String, dynamic> category) {
    final double spent = category['spent'] is int
        ? (category['spent'] as int).toDouble()
        : (category['spent'] ?? 0.0);

    final double allocated = category['allocated'] is int
        ? (category['allocated'] as int).toDouble()
        : (category['allocated'] ?? 0.0);

    final double progress = allocated > 0 ? spent / allocated : 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: category['color'].withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    category['icon'],
                    color: category['color'],
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category['name'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${spent.toStringAsFixed(0)} of ₹${allocated.toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _showEditBudgetDialog(category),
                  color: Colors.blue,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                progress > 0.9
                    ? Colors.red
                    : progress > 0.7
                    ? Colors.orange
                    : Colors.green,
              ),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  allocated > 0
                      ? '${(progress * 100).toStringAsFixed(0)}% of budget used'
                      : 'No budget set',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (allocated > 0)
                  Text(
                    '₹${(allocated - spent).toStringAsFixed(0)} left',
                    style: TextStyle(
                      fontSize: 12,
                      color: (allocated - spent) < 0
                          ? Colors.red
                          : Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double getRemainingBudget() {
    return monthlyBudget - getTotalSpent();
  }

  // Helper method to get total allocated budget across all categories
  double getTotalAllocated() {
    // ignore: avoid_types_as_parameter_names
    return categories.fold(0.0, (sum, category) {
      final allocated = category['allocated'];
      return sum +
          (allocated is int ? allocated.toDouble() : (allocated ?? 0.0));
    });
  }

  Widget _buildBudgetInfo(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final double totalSpent = getTotalSpent();
    final double remainingBudget = monthlyBudget - totalSpent;
    final double progress = monthlyBudget > 0
        ? totalSpent / monthlyBudget
        : 0.0;

    // Sort categories by spent amount (highest first)
    final sortedCategories = List<Map<String, dynamic>>.from(categories)
      ..sort((a, b) => (b['spent'] as double).compareTo(a['spent'] as double));

    return AppScaffold(
      title: 'Budget Tracker',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Budget Overview Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      'Monthly Budget',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Budget Input
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: budgetController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Enter Monthly Budget',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  prefixText: '₹ ',
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                                onSubmitted: (_) => _updateBudget(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _updateBudget,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                              child: const Text('Update'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Budget Summary Row
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildBudgetInfo(
                                'Spent',
                                '₹${totalSpent.toStringAsFixed(0)}',
                                Colors.red[700]!,
                              ),
                              _buildBudgetInfo(
                                'Remaining',
                                '₹${(monthlyBudget - totalSpent).toStringAsFixed(0)}',
                                (monthlyBudget - totalSpent) >= 0
                                    ? Colors.green[700]!
                                    : Colors.red[700]!,
                              ),
                              _buildBudgetInfo(
                                'Monthly Budget',
                                '₹${monthlyBudget.toStringAsFixed(0)}',
                                Theme.of(context).primaryColor,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Budget Progress
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '₹${totalSpent.toStringAsFixed(0)} spent',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '₹${remainingBudget.toStringAsFixed(0)} remaining',
                              style: TextStyle(
                                color: remainingBudget < 0
                                    ? Colors.red
                                    : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 12,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress > 0.9 ? Colors.red : Colors.green,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(progress * 100).toStringAsFixed(1)}% of monthly budget used',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Category Budgets
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Category Budgets',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _loadBudgetData,
                      tooltip: 'Refresh',
                    ),
                    IconButton(
                      icon: const Icon(Icons.restart_alt, color: Colors.orange),
                      onPressed: _resetCategorySpentAmounts,
                      tooltip: 'Reset All Spent Amounts',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...sortedCategories.map((category) => _buildCategoryItem(category)),
            const SizedBox(height: 24),
            // Budget Summary Chart
            const Text(
              'Budget Allocation',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: categories.where((c) => c['allocated'] > 0).map((
                    category,
                  ) {
                    return PieChartSectionData(
                      color: category['color'],
                      value: (category['allocated'] as num).toDouble(),
                      title:
                          '${category['name']}\n${(category['allocated'] / monthlyBudget * 100).toStringAsFixed(0)}%',
                      radius: 60,
                      titleStyle: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      borderSide: const BorderSide(
                        color: Colors.white,
                        width: 2,
                      ),
                    );
                  }).toList(),
                  sectionsSpace: 1,
                  centerSpaceRadius: 40,
                  // ignore: deprecated_member_use
                  centerSpaceColor: Theme.of(context).colorScheme.background,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      IterableProperty<Map<String, dynamic>>(
        '_expenseCategories',
        _expenseCategories,
      ),
    );
  }
}
