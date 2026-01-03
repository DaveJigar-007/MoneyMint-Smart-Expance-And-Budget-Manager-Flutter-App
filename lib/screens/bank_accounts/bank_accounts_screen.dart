// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import '../../models/bank_account.dart';
import '../../services/bank_account_service.dart';
import '../../widgets/app_drawer.dart';
import 'add_edit_bank_account_screen.dart';

class BankAccountsScreen extends StatefulWidget {
  final bool isSelectionMode;
  final String? preSelectedAccountId;

  const BankAccountsScreen({
    super.key,
    this.isSelectionMode = false,
    this.preSelectedAccountId,
  });

  @override
  State<BankAccountsScreen> createState() => _BankAccountsScreenState();
}

class _BankAccountsScreenState extends State<BankAccountsScreen> {
  String? _selectedAccountId;

  Future<void> _updateAccountSelection(
    BankAccount account,
    bool isSelected,
  ) async {
    try {
      // Update local state first for immediate UI update
      setState(() {
        _selectedAccountId = isSelected ? account.id : null;
      });

      // Update in Firestore using the service
      await bankAccountService.updateAccountSelection(account.id, isSelected);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account selection updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Revert local state on error
      setState(() {
        _selectedAccountId = isSelected ? null : account.id;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update account selection: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedAccountId = widget.preSelectedAccountId;
    _loadSelectedAccount();
  }

  // Load the currently selected account from the database
  Future<void> _loadSelectedAccount() async {
    try {
      final selectedAccount = await bankAccountService.getSelectedAccount();
      if (mounted && selectedAccount != null) {
        setState(() {
          _selectedAccountId = selectedAccount.id;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load selected account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(
          widget.isSelectionMode ? 'Select Account' : 'My Bank Accounts',
        ),
        backgroundColor: widget.isSelectionMode ? Colors.blue[800] : null,
        automaticallyImplyLeading: !widget.isSelectionMode,
        leading: widget.isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        actions: [
          if (widget.isSelectionMode && _selectedAccountId != null)
            TextButton(
              onPressed: _clearSelection,
              child: const Text('Clear', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: StreamBuilder<List<BankAccount>>(
        stream: bankAccountService.getBankAccounts(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final accounts = snapshot.data ?? [];

          if (accounts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.account_balance,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No bank accounts found',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _navigateToAddAccount(context),
                    child: const Text('Add Your First Account'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              final account = accounts[index];
              return _buildBankAccountCard(context, account);
            },
          );
        },
      ),
      floatingActionButton: widget.isSelectionMode
          ? null
          : FloatingActionButton(
              onPressed: () => _navigateToAddAccount(context),
              child: const Icon(Icons.add),
            ),
    );
  }

  Future<void> _handleAccountSelection(BankAccount account) async {
    if (_selectedAccountId == account.id) {
      // If clicking the already selected account, deselect it
      setState(() {
        _selectedAccountId = null;
      });
      // Update the account in the database to mark as not selected
      await _updateAccountSelection(account, false);
      if (mounted) {
        Navigator.of(context).pop(null);
      }
      return;
    }

    if (_selectedAccountId != null) {
      // Show confirmation dialog if another account is already selected
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Change Account'),
          content: const Text(
            'You already have an account selected. Do you want to change your selection?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Change'),
            ),
          ],
        ),
      );

      if (shouldProceed != true) {
        return;
      }
    }

    // Update the account in the database to mark as selected
    await _updateAccountSelection(account, true);

    if (mounted) {
      setState(() {
        _selectedAccountId = account.id;
      });

      if (widget.isSelectionMode) {
        Navigator.of(context).pop(account);
      }
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedAccountId = null;
    });
    if (widget.isSelectionMode) {
      Navigator.of(context).pop(null);
    }
  }

  Widget _buildBankAccountCard(BuildContext context, BankAccount account) {
    final isSelected = _selectedAccountId == account.id;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      elevation: isSelected ? 2 : 1,
      color: isSelected
          ? theme.colorScheme.primary.withOpacity(0.08)
          : theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 1.0)
            : BorderSide.none,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.account_balance,
            size: 20,
            color: theme.colorScheme.primary,
          ),
        ),
        title: Text(
          account.bankName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: isSelected ? theme.colorScheme.primary : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '•••• ${account.accountNumber.substring(account.accountNumber.length - 4)}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              '₹${account.currentBalance.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.green[700],
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        trailing: widget.isSelectionMode
            ? ElevatedButton(
                onPressed: () => _handleAccountSelection(account),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected
                      ? Colors.grey[400]
                      : theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
                child: Text(
                  isSelected ? 'Selected' : 'Select',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSelected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Selected',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'select') {
                        _handleAccountSelection(account);
                      } else if (value == 'edit') {
                        _navigateToEditAccount(context, account);
                      } else if (value == 'delete') {
                        _showDeleteConfirmation(context, account);
                      }
                    },
                    itemBuilder: (context) => [
                      if (!isSelected)
                        const PopupMenuItem(
                          value: 'select',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline, size: 20),
                              SizedBox(width: 8),
                              Text('Select Account'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        onTap: widget.isSelectionMode
            ? () => _handleAccountSelection(account)
            : null,
      ),
    );
  }

  void _navigateToAddAccount(BuildContext context) async {
    final result = await Navigator.push<bool?>(
      context,
      MaterialPageRoute(builder: (context) => const AddEditBankAccountScreen()),
    );

    // If add/edit returned true, StreamBuilder will already reflect changes.
    if (result == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account saved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _navigateToEditAccount(BuildContext context, BankAccount account) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditBankAccountScreen(account: account),
      ),
    );

    if (result != null && widget.isSelectionMode) {}
  }

  void _showDeleteConfirmation(
    BuildContext context,
    BankAccount account,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text(
          'Are you sure you want to delete ${account.bankName} account? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      await bankAccountService.deleteBankAccount(account.id);
      if (mounted) {
        if (_selectedAccountId == account.id) {
          setState(() {
            _selectedAccountId = null;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text(
          'Are you sure you want to delete ${account.bankName} account? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await bankAccountService.deleteBankAccount(account.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Account deleted successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete account: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
