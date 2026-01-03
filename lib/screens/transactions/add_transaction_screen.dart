// ignore_for_file: non_constant_identifier_names

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../widgets/app_scaffold.dart';
import '../../services/budget_service.dart';
import '../../services/bank_account_service.dart';
import '../../models/bank_account.dart';

class AddTransactionScreen extends StatefulWidget {
  final Function(Transaction)? onSave;

  const AddTransactionScreen({super.key, this.onSave});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final BudgetService _budgetService = BudgetService();
  final BankAccountService _bankAccountService = BankAccountService();
  DateTime _selectedDate = DateTime.now();
  TransactionType _selectedType = TransactionType.expense;
  Category _selectedCategory = Category.food;
  bool _isSubmitting = false;

  BankAccount? _selectedAccount;

  @override
  void initState() {
    super.initState();
    _loadSelectedAccount();
  }

  Future<void> _loadSelectedAccount() async {
    try {
      final acc = await _bank_account_getSelected();
      if (mounted) setState(() => _selectedAccount = acc);
    } catch (_) {}
  }

  Future<BankAccount?> _bank_account_getSelected() async {
    try {
      return await _bankAccountService.getSelectedAccount();
    } catch (e) {
      return null;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _changeAccount() async {
    // Open bank accounts screen where user can change selected account.
    // After returning, reload the selected account.
    await Navigator.pushNamed(context, '/bank-accounts');
    await _loadSelectedAccount();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final amount = double.parse(_amountController.text);
      final isExpense = _selectedType == TransactionType.expense;
      final categoryName = _selectedCategory.toString().split('.').last;

      // Ensure user has set a monthly budget before allowing expense transactions
      Map<String, dynamic> budgetData = {};
      if (isExpense) {
        try {
          budgetData = await _budgetService.getBudgetData();
          final monthlyBudget = (budgetData['monthlyBudget'] ?? 0).toDouble();
          if (monthlyBudget <= 0) {
            if (mounted) {
              setState(() => _isSubmitting = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please set your monthly budget first!'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
              Navigator.pushReplacementNamed(context, '/budget');
            }
            return;
          }
        } catch (e) {
          // If fetching budget fails for expense, prevent transaction
          if (mounted) {
            setState(() => _isSubmitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please set your monthly budget first!'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
            Navigator.pushReplacementNamed(context, '/budget');
          }
          return;
        }
      }

      // Ensure a bank account is selected
      final selectedAccount =
          _selectedAccount ?? await _bankAccountService.getSelectedAccount();
      if (selectedAccount == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please add and select a bank account first!'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
          Navigator.pushReplacementNamed(context, '/bank-accounts');
        }
        setState(() => _isSubmitting = false);
        return;
      }

      // Budget checks (only for expenses)
      if (isExpense) {
        final categories = List<Map<String, dynamic>>.from(
          budgetData['categories'] ?? [],
        );

        // Find category with case-insensitive match
        final category = categories.firstWhere(
          (cat) =>
              cat['name'].toString().toLowerCase() ==
              categoryName.toLowerCase(),
          orElse: () => {'allocated': 0.0, 'spent': 0.0},
        );

        final allocated = (category['allocated'] ?? 0).toDouble();
        final spent = (category['spent'] ?? 0).toDouble();
        final remaining = (allocated - spent).toDouble();

        debugPrint(
          'Category: $categoryName | Allocated: ₹$allocated | Spent: ₹$spent | Remaining: ₹$remaining | Transaction: ₹$amount',
        );

        // If user has set a category budget (allocated > 0), enforce it.
        if (allocated > 0) {
          // If already over or fully utilized, block any further expense in this category
          if (remaining <= 0) {
            if (mounted) {
              setState(() => _isSubmitting = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Budget fully utilized for this category!',
                  ),
                  backgroundColor: Colors.red,
                  action: SnackBarAction(
                    label: 'Adjust Budget',
                    textColor: Colors.white,
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/budget');
                    },
                  ),
                ),
              );
            }
            return;
          }

          // If this transaction would exceed the remaining budget, block it
          if (amount > remaining) {
            if (mounted) {
              setState(() => _isSubmitting = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Budget exceeded for $categoryName! You can spend up to ₹${remaining.toStringAsFixed(2)} (Allocated: ₹${allocated.toStringAsFixed(2)}, Already spent: ₹${spent.toStringAsFixed(2)})',
                  ),
                  backgroundColor: Colors.red,
                  action: SnackBarAction(
                    label: 'Adjust Budget',
                    textColor: Colors.white,
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/budget');
                    },
                  ),
                ),
              );
            }
            return;
          }
        }
        // If allocated == 0 (no category budget set), allow the expense.
      }

      // Prepare transaction data for bank account storage
      final bankTransactionData = {
        'amount': amount
            .abs(), // store positive amount; BankAccountService will use 'type' to adjust balance
        'description': _descriptionController.text,
        'date': Timestamp.fromDate(_selectedDate),
        'category': categoryName,
        'type': _selectedType.toString().split('.').last,
        'userId': user.uid,
        'accountNumber': selectedAccount.accountNumber,
      };

      // Add transaction to the selected bank account (this updates balance transactionally)
      // Pre-check: ensure transaction won't breach minimumBalance
      try {
        final predictedNewBalance =
            selectedAccount.currentBalance + (isExpense ? -amount : amount);
        final minBal = selectedAccount.minimumBalance;
        if (predictedNewBalance < minBal) {
          if (mounted) {
            setState(() => _isSubmitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "You don't have enough balance for this transaction. Minimum required: ₹${minBal.toStringAsFixed(2)}",
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      } catch (_) {
        // if any model field is missing, fall back to service-level validation
      }

      await _bankAccountService.addTransaction(
        bankAccountId: selectedAccount.id,
        transactionData: bankTransactionData,
      );

      // Update the spent amount in the budget (only for expense)
      if (isExpense) {
        await _budgetService.updateSpentAmount(
          categoryName,
          double.parse(_amountController.text),
        );
      }

      // Build local Transaction object
      final transaction = Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        amount: isExpense ? -amount.abs() : amount.abs(),
        description: _descriptionController.text,
        date: _selectedDate,
        category: _selectedCategory,
        type: _selectedType,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction saved successfully!'),
            backgroundColor: Color(0xFF274647),
            duration: Duration(seconds: 2),
          ),
        );

        widget.onSave?.call(transaction);

        // Return to transactions list after short delay
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) Navigator.pushReplacementNamed(context, '/transactions');
        });
      }
    } catch (e) {
      if (mounted) {
        final err = e.toString();
        if (err.toLowerCase().contains('minimum') ||
            err.toLowerCase().contains('insufficient')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "You don't have enough balance for this transaction.",
              ),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving transaction: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildSelectedAccountTile() {
    if (_selectedAccount == null) {
      return ListTile(
        leading: const Icon(Icons.account_balance),
        title: const Text('No bank account selected'),
        subtitle: const Text('Tap to add or select an account'),
        trailing: ElevatedButton(
          onPressed: _changeAccount,
          child: const Text('Select'),
        ),
        onTap: _changeAccount,
      );
    }

    final acc = _selectedAccount!;
    final masked = acc.accountNumber.length > 4
        ? '****${acc.accountNumber.substring(acc.accountNumber.length - 4)}'
        : acc.accountNumber;

    return ListTile(
      leading: const Icon(Icons.account_balance),
      title: Text(acc.bankName),
      subtitle: Text(
        'A/C: $masked • Balance: ₹${acc.currentBalance.toStringAsFixed(2)}',
      ),
      trailing: TextButton(
        onPressed: _changeAccount,
        child: const Text('Change'),
      ),
      onTap: _changeAccount,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Add Transaction',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSelectedAccountTile(),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an amount';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Expense'),
                      selected: _selectedType == TransactionType.expense,
                      onSelected: (_) => setState(
                        () => _selectedType = TransactionType.expense,
                      ),
                      selectedColor: Colors.red[100],
                      backgroundColor: Colors.grey[200],
                      labelStyle: TextStyle(
                        color: _selectedType == TransactionType.expense
                            ? Colors.red[800]
                            : Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Income'),
                      selected: _selectedType == TransactionType.income,
                      onSelected: (_) => setState(
                        () => _selectedType = TransactionType.income,
                      ),
                      selectedColor: Colors.green[100],
                      backgroundColor: Colors.grey[200],
                      labelStyle: TextStyle(
                        color: _selectedType == TransactionType.income
                            ? Colors.green[800]
                            : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              const Text(
                'Category',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: _currentCategories.map((category) {
                  final isSelected = _selectedCategory == category['value'];
                  return ChoiceChip(
                    avatar: Icon(
                      category['icon'],
                      color: isSelected ? Colors.white : null,
                    ),
                    label: Text(category['label']),
                    selected: isSelected,
                    onSelected: (_) =>
                        setState(() => _selectedCategory = category['value']),
                    backgroundColor: !isSelected
                        ? Colors.grey[200]
                        : theme.primaryColor.withOpacity(0.2),
                    selectedColor: theme.primaryColor,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Date'),
                subtitle: Text(
                  DateFormat('MMM dd, yyyy').format(_selectedDate),
                ),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: () => _selectDate(context),
              ),

              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                maxLines: 3,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Please enter a description'
                    : null,
              ),

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  backgroundColor: _isSubmitting
                      ? Colors.grey[300]
                      : theme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: _isSubmitting ? 0 : 2,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save Transaction',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Category lists
  List<Map<String, dynamic>> get _expenseCategories => [
    {
      'icon': Icons.restaurant,
      'label': 'Food',
      'value': Category.food,
      'color': const Color(0xFF4285F4),
    },
    {
      'icon': Icons.shopping_cart,
      'label': 'Shopping',
      'value': Category.shopping,
      'color': const Color(0xFFFF9800),
    },
    {
      'icon': Icons.directions_car,
      'label': 'Transport',
      'value': Category.transport,
      'color': const Color(0xFF0F9D58),
    },
    {
      'icon': Icons.home,
      'label': 'Housing',
      'value': Category.housing,
      'color': const Color(0xFF9C27B0),
    },
    {
      'icon': Icons.medical_services,
      'label': 'Health',
      'value': Category.health,
      'color': const Color(0xFFE91E63),
    },
    {
      'icon': Icons.movie,
      'label': 'Entertainment',
      'value': Category.entertainment,
      'color': const Color(0xFF9C27B0),
    },
    {
      'icon': Icons.receipt_long,
      'label': 'Bills',
      'value': Category.bills,
      'color': const Color(0xFF607D8B),
    },
    {
      'icon': Icons.school,
      'label': 'Education',
      'value': Category.education,
      'color': const Color(0xFF795548),
    },
    {
      'icon': Icons.card_giftcard,
      'label': 'Gifts',
      'value': Category.gifts,
      'color': const Color(0xFFE91E63),
    },
    {
      'icon': Icons.flight_takeoff,
      'label': 'Travel',
      'value': Category.travel,
      'color': const Color(0xFF3F51B5),
    },
    {
      'icon': Icons.person,
      'label': 'Personal',
      'value': Category.personal,
      'color': const Color(0xFF9C27B0),
    },
    {
      'icon': Icons.category,
      'label': 'Other',
      'value': Category.other,
      'color': const Color(0xFF9E9E9E),
    },
  ];

  List<Map<String, dynamic>> get _incomeCategories => [
    {'icon': Icons.work, 'label': 'Salary', 'value': Category.salary},
    {
      'icon': Icons.account_balance_wallet,
      'label': 'Other Income',
      'value': Category.otherIncome,
    },
    {'icon': Icons.business, 'label': 'Business', 'value': Category.business},
    {'icon': Icons.savings, 'label': 'Savings', 'value': Category.savings},
    {'icon': Icons.card_giftcard, 'label': 'Gift', 'value': Category.gift},
    {
      'icon': Icons.trending_up,
      'label': 'Investment',
      'value': Category.investment,
    },
    {'icon': Icons.computer, 'label': 'Freelance', 'value': Category.freelance},
    {'icon': Icons.celebration, 'label': 'Bonus', 'value': Category.bonus},
  ];

  List<Map<String, dynamic>> get _currentCategories =>
      _selectedType == TransactionType.expense
      ? _expenseCategories
      : _incomeCategories;
}

enum TransactionType { income, expense }

enum Category {
  food,
  shopping,
  transport,
  housing,
  health,
  entertainment,
  bills,
  education,
  gifts,
  travel,
  personal,
  other,
  salary,
  otherIncome,
  business,
  savings,
  gift,
  investment,
  freelance,
  bonus,
  otherExpense,
}

class Transaction {
  final String id;
  final double amount;
  final String description;
  final DateTime date;
  final Category category;
  final TransactionType type;

  Transaction({
    required this.id,
    required this.amount,
    required this.description,
    required this.date,
    required this.category,
    required this.type,
  });
}
