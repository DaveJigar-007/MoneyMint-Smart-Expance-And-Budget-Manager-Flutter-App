class BankAccount {
  final String id;
  final String bankName;
  final String accountNumber;
  final String accountHolderName;
  final String ifscCode;
  final String branchName;
  final double currentBalance;
  final double minimumBalance;
  final bool isSelected;
  final DateTime createdAt;
  final DateTime updatedAt;

  BankAccount({
    required this.id,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolderName,
    required this.ifscCode,
    required this.branchName,
    this.currentBalance = 0.0,
    this.minimumBalance = 0.0,
    this.isSelected = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'bankName': bankName,
      'accountNumber': accountNumber,
      'accountHolderName': accountHolderName,
      'ifscCode': ifscCode,
      'branchName': branchName,
      'currentBalance': currentBalance,
      'minimumBalance': minimumBalance,
      'isSelected': isSelected,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  BankAccount copyWith({
    String? id,
    String? bankName,
    String? accountNumber,
    String? accountHolderName,
    String? ifscCode,
    String? branchName,
    double? currentBalance,
    double? minimumBalance,
    bool? isSelected,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BankAccount(
      id: id ?? this.id,
      bankName: bankName ?? this.bankName,
      accountNumber: accountNumber ?? this.accountNumber,
      accountHolderName: accountHolderName ?? this.accountHolderName,
      ifscCode: ifscCode ?? this.ifscCode,
      branchName: branchName ?? this.branchName,
      currentBalance: currentBalance ?? this.currentBalance,
      minimumBalance: minimumBalance ?? this.minimumBalance,
      isSelected: isSelected ?? this.isSelected,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory BankAccount.fromMap(String id, Map<String, dynamic> map) {
    return BankAccount(
      id: id,
      bankName: map['bankName'] ?? '',
      accountNumber: map['accountNumber'] ?? '',
      accountHolderName: map['accountHolderName'] ?? '',
      ifscCode: map['ifscCode'] ?? '',
      branchName: map['branchName'] ?? '',
      currentBalance: (map['currentBalance'] ?? 0.0).toDouble(),
      minimumBalance: (map['minimumBalance'] ?? 0.0).toDouble(),
      isSelected: map['isSelected'] ?? false,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }
}
