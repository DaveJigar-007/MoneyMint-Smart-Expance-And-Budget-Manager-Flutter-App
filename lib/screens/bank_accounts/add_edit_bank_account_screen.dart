import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/bank_account.dart';
import '../../services/bank_account_service.dart';

class AddEditBankAccountScreen extends StatefulWidget {
  final BankAccount? account;

  const AddEditBankAccountScreen({super.key, this.account});

  @override
  State<AddEditBankAccountScreen> createState() =>
      _AddEditBankAccountScreenState();
}

class _AddEditBankAccountScreenState extends State<AddEditBankAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _bankNameController;
  late final TextEditingController _accountNumberController;
  late final TextEditingController _accountHolderNameController;
  late final TextEditingController _ifscCodeController;
  late final TextEditingController _branchNameController;

  bool _isLoading = false;
  bool _isSaving = false;
  String? _selectedBank;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _bankNameController = TextEditingController(text: account?.bankName ?? '');
    _accountNumberController = TextEditingController(
      text: account?.accountNumber ?? '',
    );
    _accountHolderNameController = TextEditingController(
      text: account?.accountHolderName ?? '',
    );
    _ifscCodeController = TextEditingController(text: account?.ifscCode ?? '');
    _branchNameController = TextEditingController(
      text: account?.branchName ?? '',
    );
    // current balance removed from add form; it'll be set automatically
    _selectedBank = account?.bankName;
  }

  @override
  void dispose() {
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _accountHolderNameController.dispose();
    _ifscCodeController.dispose();
    _branchNameController.dispose();

    super.dispose();
  }

  void _handleBackPress() {
    // Always allow back navigation
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.account != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Bank Account' : 'Add Bank Account'),
        centerTitle: true,
        elevation: 0,
        leading: BackButton(onPressed: _handleBackPress),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Bank Selection Dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedBank,
                      decoration: const InputDecoration(
                        labelText: 'Select Bank',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_balance),
                      ),
                      items: BankAccountService.supportedBanks
                          .map(
                            (bank) => DropdownMenuItem(
                              value: bank,
                              child: Text(bank),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedBank = value;
                          _bankNameController.text = value ?? '';
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please select a bank';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Account Number
                    TextFormField(
                      controller: _accountNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Account Number',
                        hintText: '14 digits only',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.credit_card),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(14),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter account number';
                        }
                        if (value.length != 14) {
                          return 'Account number must be exactly 14 digits';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Account Holder Name
                    TextFormField(
                      controller: _accountHolderNameController,
                      decoration: const InputDecoration(
                        labelText: 'Account Holder Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter account holder name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // IFSC Code
                    TextFormField(
                      controller: _ifscCodeController,
                      decoration: const InputDecoration(
                        labelText: 'IFSC Code',
                        hintText: '11 alphanumeric characters',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.qr_code),
                      ),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
                        LengthLimitingTextInputFormatter(11),
                      ],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter IFSC code';
                        }
                        if (value.length != 11) {
                          return 'IFSC code must be exactly 11 characters';
                        }
                        if (!RegExp(r'^[A-Z0-9]{11}$').hasMatch(value)) {
                          return 'IFSC code must contain only alphanumeric characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Branch Name
                    TextFormField(
                      controller: _branchNameController,
                      decoration: const InputDecoration(
                        labelText: 'Branch Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter branch name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    const SizedBox(height: 12),

                    // Save Button
                    ElevatedButton(
                      onPressed: _saveBankAccount,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        isEdit ? 'UPDATE ACCOUNT' : 'ADD ACCOUNT',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _saveBankAccount() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return; // Prevent duplicate saves

    _isSaving = true;
    setState(() => _isLoading = true);

    try {
      // determine minimum balance for the selected bank
      final selectedBankName = _bankNameController.text.trim();
      final minBal = BankAccountService.minimumForBank(selectedBankName);

      final account = BankAccount(
        id: widget.account?.id ?? '',
        bankName: selectedBankName,
        accountNumber: _accountNumberController.text.trim(),
        accountHolderName: _accountHolderNameController.text.trim(),
        ifscCode: _ifscCodeController.text.trim().toUpperCase(),
        branchName: _branchNameController.text.trim(),
        minimumBalance: minBal,
        // For new accounts set current balance equal to minimum balance,
        // for edits preserve existing current balance
        currentBalance: widget.account?.currentBalance ?? minBal,
      );

      if (widget.account != null) {
        await bankAccountService.updateBankAccount(account);
        if (mounted) {
          // reset flags then notify parent that save succeeded
          setState(() {
            _isSaving = false;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context, true);
          }
        }
      } else {
        await bankAccountService.addBankAccount(account);
        if (mounted) {
          setState(() {
            _isSaving = false;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account added successfully'),
              backgroundColor: Colors.green,
            ),
          );
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context, true);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
      _isSaving = false;
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
