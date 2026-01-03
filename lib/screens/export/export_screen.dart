// lib/screens/export/export_screen.dart
// Place this file in your project and replace the existing export screen.
// Requires the project's existing services: BankAccountService, BankAccount model.

// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:open_file/open_file.dart' as open_file;

import '../../services/bank_account_service.dart';
import '../../models/bank_account.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final BankAccountService _bankService = BankAccountService();

  // Date range & filters
  DateTimeRange _selectedDateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  String _selectedFilter = 'last30days';

  final List<Map<String, String>> _dateFilters = [
    {'label': 'Today', 'value': 'today'},
    {'label': 'Yesterday', 'value': 'yesterday'},
    {'label': 'Last 7 Days', 'value': 'last7days'},
    {'label': 'Last 30 Days', 'value': 'last30days'},
    {'label': 'This Month', 'value': 'thismonth'},
    {'label': 'Last Month', 'value': 'lastmonth'},
    {'label': 'This Year', 'value': 'thisyear'},
    {'label': 'Last Year', 'value': 'lastyear'},
    {'label': 'Custom Date', 'value': 'custom'},
  ];

  // Accounts
  List<BankAccount> _accounts = [];
  String? _selectedAccountId; // null => All Accounts

  // Loading flags
  bool _isSharing = false;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    _applyDateFilter(_selectedFilter);
  }

  Future<void> _loadAccounts() async {
    try {
      final accounts = await _bankService.getBankAccounts().first;
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        if (_accounts.isNotEmpty && _selectedAccountId == null) {
          final sel = _accounts.firstWhere(
            (a) => a.isSelected,
            orElse: () => _accounts.first,
          );
          _selectedAccountId = sel.id;
        }
      });
    } catch (e) {
      debugPrint('Load accounts error: $e');
    }
  }

  String _shortBankName(String bankName) {
    // Preferred short codes for known banks (explicit mapping)
    final s = bankName.trim();
    if (s.isEmpty) return 'Acc';
    final lower = s.toLowerCase();

    if (lower.contains('rajkot') || lower.contains('rnsb')) return 'RNSB';
    if (lower.contains('state bank of india') ||
        lower.contains(' sbi') ||
        lower.contains('(sbi)'))
      return 'SBI';
    if (lower.contains('bank of baroda') || lower.contains(' bob'))
      return 'BOB';
    if (lower.contains('punjab national') || lower.contains(' pnb'))
      return 'PNB';
    if (lower.contains('canara bank')) return 'CAN';
    if (lower.contains('union bank')) return 'UBI';
    if (lower.contains('bank of india') || lower.contains(' boi')) return 'BOI';
    if (lower.contains('central bank')) return 'CBI';
    if (lower.contains('indian overseas') || lower.contains(' iob'))
      return 'IOB';
    if (lower.contains('uco bank') || lower.contains(' uco')) return 'UCO';
    if (lower.contains('indian bank')) return 'INB';

    // Fallback: build acronym from significant words (ignore common words)
    final cleaned = s.replaceAll(RegExp(r'[(),.]'), '');
    final words = cleaned
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final ignore = {
      'bank',
      'of',
      'india',
      'and',
      'the',
      'ltd',
      'limited',
      'co',
      'inc',
      '&',
    };
    final significant = words
        .where((w) => !ignore.contains(w.toLowerCase()))
        .toList();

    if (significant.isNotEmpty) {
      final initials = significant.map((w) => w[0]).take(3).join();
      if (initials.length >= 2) return initials.toUpperCase();
    }

    // Final fallback: first up-to-3 alphabetic characters
    final lettersOnly = s.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (lettersOnly.length >= 3)
      return lettersOnly.substring(0, 3).toUpperCase();
    return lettersOnly.toUpperCase();
  }

  void _applyDateFilter(String filter) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    setState(() {
      _selectedFilter = filter;
      switch (filter) {
        case 'today':
          _selectedDateRange = DateTimeRange(
            start: today,
            end: today.add(const Duration(days: 1)),
          );
          break;
        case 'yesterday':
          _selectedDateRange = DateTimeRange(
            start: today.subtract(const Duration(days: 1)),
            end: today,
          );
          break;
        case 'last7days':
          _selectedDateRange = DateTimeRange(
            start: today.subtract(const Duration(days: 6)),
            end: today.add(const Duration(days: 1)),
          );
          break;
        case 'last30days':
          _selectedDateRange = DateTimeRange(
            start: today.subtract(const Duration(days: 29)),
            end: today.add(const Duration(days: 1)),
          );
          break;
        case 'thismonth':
          _selectedDateRange = DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month + 1, 1),
          );
          break;
        case 'lastmonth':
          _selectedDateRange = DateTimeRange(
            start: DateTime(now.year, now.month - 1, 1),
            end: DateTime(now.year, now.month, 1),
          );
          break;
        case 'thisyear':
          _selectedDateRange = DateTimeRange(
            start: DateTime(now.year, 1, 1),
            end: DateTime(now.year + 1, 1, 1),
          );
          break;
        case 'lastyear':
          _selectedDateRange = DateTimeRange(
            start: DateTime(now.year - 1, 1, 1),
            end: DateTime(now.year, 1, 1),
          );
          break;
        case 'custom':
          _selectCustomDateRange();
          break;
        default:
          _selectedDateRange = DateTimeRange(
            start: today.subtract(const Duration(days: 29)),
            end: today.add(const Duration(days: 1)),
          );
      }
    });
  }

  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _selectedDateRange,
    );
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        _selectedFilter = 'custom';
      });
    }
  }

  // Build a Firestore Query for the selected account or legacy collection
  Query<Map<String, dynamic>> _transactionsQuery(
    String uid, {
    bool descending = true,
  }) {
    final desc = descending;
    if (_selectedAccountId != null && _selectedAccountId!.isNotEmpty) {
      return FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('bankAccounts')
          .doc(_selectedAccountId)
          .collection('transactions')
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(
              _selectedDateRange.start,
            ),
          )
          .where(
            'date',
            // use the selected end date as the exclusive upper-bound
            isLessThan: Timestamp.fromDate(_selectedDateRange.end),
          )
          .orderBy('date', descending: desc)
          .withConverter<Map<String, dynamic>>(
            fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
            toFirestore: (map, _) => map,
          );
    }

    return FirebaseFirestore.instance
        .collection('transactions')
        .doc(uid)
        .collection('user_transactions')
        .where(
          'date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(_selectedDateRange.start),
        )
        .where(
          'date',
          // use the selected end date as the exclusive upper-bound
          isLessThan: Timestamp.fromDate(_selectedDateRange.end),
        )
        .orderBy('date', descending: desc)
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
          toFirestore: (map, _) => map,
        );
  }

  // Request storage permissions (Android specifics handled)
  Future<bool> _requestStoragePermission() async {
    if (kIsWeb) return true;
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;
        if (sdkInt >= 33) {
          final status = await Permission.photos.request();
          if (status.isGranted) return true;
          if (status.isPermanentlyDenied) {
            await _showPermissionSettingsDialog(
              'Photos Permission Required',
              'Enable Photos permission in settings to save files.',
            );
            return false;
          }
          return status.isGranted;
        }
        if (sdkInt >= 29) {
          final status = await Permission.storage.request();
          if (status.isGranted) return true;
          if (status.isPermanentlyDenied) {
            await _showPermissionSettingsDialog(
              'Storage Permission Required',
              'Enable Storage permission in settings to save files.',
            );
            return false;
          }
          return status.isGranted;
        }
        final statuses = await [
          Permission.storage,
          Permission.manageExternalStorage,
        ].request();
        final ok =
            statuses[Permission.storage]?.isGranted == true ||
            statuses[Permission.manageExternalStorage]?.isGranted == true;
        if (!ok) {
          await _showPermissionSettingsDialog(
            'Storage Permission Required',
            'Enable Storage permission in settings to save files.',
          );
        }
        return ok;
      } else if (Platform.isIOS) {
        final status = await Permission.photos.request();
        return status.isGranted;
      }
    } catch (e) {
      debugPrint('Permission error: $e');
      return false;
    }
    return true;
  }

  Future<void> _showPermissionSettingsDialog(
    String title,
    String message,
  ) async {
    if (!mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
    if (open == true) await openAppSettings();
  }

  // Save PDF bytes to device. On Android tries Downloads/MoneyMint, otherwise app documents/MoneyMint
  Future<String?> _savePdfToDevice(Uint8List pdfBytes, String fileName) async {
    if (!kIsWeb) {
      final granted = await _requestStoragePermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission denied')),
          );
        }
        return null;
      }
    }

    try {
      String directoryPath;
      if (!kIsWeb && Platform.isAndroid) {
        // Try /storage/emulated/0/Download first
        String downloads = '/storage/emulated/0/Download';
        final downloadsDir = Directory(downloads);
        if (!await downloadsDir.exists()) {
          // fallback to external storage directory
          final ext = await getExternalStorageDirectory();
          downloads =
              ext?.path ?? (await getApplicationDocumentsDirectory()).path;
        }
        directoryPath = path.join(downloads, 'MoneyMint');
      } else {
        final appDoc = await getApplicationDocumentsDirectory();
        directoryPath = path.join(appDoc.path, 'MoneyMint');
      }

      final dir = Directory(directoryPath);
      if (!await dir.exists()) await dir.create(recursive: true);

      final filePath = path.join(directoryPath, fileName);
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes, flush: true);

      return file.path;
    } catch (e) {
      debugPrint('Save PDF error: $e');
      // fallback: write temp file and return its path
      final tmp = await getTemporaryDirectory();
      final tmpFile = File(path.join(tmp.path, fileName));
      await tmpFile.writeAsBytes(pdfBytes);
      return tmpFile.path;
    }
  }

  // Build PDF bytes from a list of raw transaction maps
  Future<Uint8List?> _buildPdfBytesFromDocs(
    List<Map<String, dynamic>> docs,
  ) async {
    try {
      // Normalize incoming docs: date -> DateTime, amount -> double, type string and description
      final normalized = docs.map<Map<String, dynamic>>((d) {
        final rawDate = d['date'];
        DateTime date;
        if (rawDate is Timestamp) {
          date = rawDate.toDate();
        } else if (rawDate is DateTime)
          date = rawDate;
        else
          date = DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();

        final amount = (d['amount'] as num?)?.toDouble() ?? 0.0;
        final type = (d['type'] ?? 'expense').toString().toLowerCase();
        final desc = d['description'] ?? '';

        return {
          'date': date,
          'amount': amount,
          'type': type,
          'description': desc,
        };
      }).toList();

      // Sort ascending by date for running balance
      normalized.sort(
        (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime),
      );

      // compute processed rows with running balance
      double running = 0.0;
      double totalDebit = 0.0;
      double totalCredit = 0.0;
      final processed = <Map<String, dynamic>>[];

      for (var t in normalized) {
        final amt = (t['amount'] as double).abs();
        final isExpense = (t['type'] as String) == 'expense';
        final debit = isExpense ? amt : 0.0;
        final credit = isExpense ? 0.0 : amt;
        totalDebit += debit;
        totalCredit += credit;
        running += isExpense ? -amt : amt;

        processed.add({
          'date': t['date'],
          'description': t['description'],
          'debit': debit,
          'credit': credit,
          'balance': running,
        });
      }

      // If an account is selected, adjust running balances so the final
      // balance matches the account's currentBalance (keeps relative changes).
      double closingBalance = processed.isNotEmpty
          ? (processed.last['balance'] as double)
          : 0.0;
      if (_selectedAccountId != null && _selectedAccountId!.isNotEmpty) {
        try {
          final acc = _accounts.firstWhere(
            (a) => a.id == _selectedAccountId,
            orElse: () => _accounts.first,
          );
          final accBal = (acc.currentBalance as num).toDouble();
          // If processed is empty, we'll use accBal as the closing and keep processed empty.
          final offset = accBal - closingBalance;
          if (processed.isNotEmpty && offset != 0.0) {
            for (var p in processed) {
              p['balance'] = (p['balance'] as double) + offset;
            }
            closingBalance = processed.last['balance'] as double;
          } else if (processed.isEmpty) {
            closingBalance = accBal;
          }
        } catch (e) {
          // ignore and leave computed closingBalance as-is
          debugPrint('Account balance adjust ignored: $e');
        }
      }

      // prepare account label for PDF header
      String accountLabel = 'All Accounts';
      try {
        if (_selectedAccountId != null && _selectedAccountId!.isNotEmpty) {
          final acc = _accounts.firstWhere(
            (a) => a.id == _selectedAccountId,
            orElse: () => _accounts.first,
          );
          final mask = acc.accountNumber;
          final acctMask = mask.length > 4
              ? '****${mask.substring(mask.length - 4)}'
              : mask;
          accountLabel = '${acc.bankName} • $acctMask';
        }
      } catch (_) {
        // ignore and leave as 'All Accounts'
      }

      // Build PDF
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Text(
                  'MoneyMint Transaction History',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Text(
                'Account: $accountLabel',
                style: const pw.TextStyle(
                  fontSize: 12,
                  color: PdfColors.grey700,
                ),
              ),
              pw.Text(
                'Date Range: ${DateFormat('yyyy-MM-dd').format(_selectedDateRange.start)} to ${DateFormat('yyyy-MM-dd').format(_selectedDateRange.end)}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
              ),
              pw.SizedBox(height: 12),
              pw.Table.fromTextArray(
                headers: ['Date', 'Narration', 'Debit', 'Credit', 'Balance'],
                data: processed.map((row) {
                  final date = row['date'] as DateTime;
                  final debit = (row['debit'] as double);
                  final credit = (row['credit'] as double);
                  final balance = (row['balance'] as double).toStringAsFixed(2);
                  return [
                    DateFormat('dd/MM/yyyy').format(date),
                    row['description'] ?? '',
                    debit != 0.0 ? debit.toStringAsFixed(2) : '',
                    credit != 0.0 ? credit.toStringAsFixed(2) : '',
                    balance,
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                  fontSize: 10,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.blue700,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.5),
                  1: const pw.FlexColumnWidth(3.0),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.5),
                  4: const pw.FlexColumnWidth(1.5),
                },
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                },
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Total Debit: ${totalDebit.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.red700,
                      fontSize: 10,
                    ),
                  ),
                  pw.Text(
                    'Total Credit: ${totalCredit.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.green700,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Net Balance: ${(totalCredit - totalDebit).toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue700,
                      fontSize: 10,
                    ),
                  ),
                  pw.Text(
                    'Closing: ${closingBalance.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Generated on: ${DateTime.now().toString().split('.')[0]}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ];
          },
        ),
      );

      return pdf.save();
    } catch (e) {
      debugPrint('PDF build error: $e');
      return null;
    }
  }

  Future<void> _exportAndSharePdf() async {
    if (!mounted) return;
    setState(() => _isSharing = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please login')));
      }
      setState(() => _isSharing = false);
      return;
    }

    try {
      // Get documents using account-aware query in ascending order (balance calc)
      final snap = await _transactionsQuery(user.uid, descending: false).get();
      final docs = snap.docs.map((d) => d.data()).toList();

      final bytes = await _buildPdfBytesFromDocs(docs);
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to generate PDF')),
          );
        }
        return;
      }

      // Create temp file and share
      final temp = await getTemporaryDirectory();
      final fileName =
          'MoneyMint_Transactions_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final file = File(path.join(temp.path, fileName));
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'MoneyMint Transaction History',
        subject: 'Transactions',
      );
    } catch (e) {
      debugPrint('Share error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Share failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _downloadPdf() async {
    if (!mounted) return;
    setState(() => _isDownloading = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please login')));
      }
      setState(() => _isDownloading = false);
      return;
    }

    try {
      final snap = await _transactionsQuery(user.uid, descending: false).get();
      final docs = snap.docs.map((d) => d.data()).toList();

      final bytes = await _buildPdfBytesFromDocs(docs);
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to generate PDF')),
          );
        }
        return;
      }

      final fileName =
          'MoneyMint_Transactions_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final savedPath = await _savePdfToDevice(bytes, fileName);

      if (mounted) {
        if (savedPath != null) {
          final snackBar = SnackBar(
            content: Text('PDF saved: ${path.basename(savedPath)}'),
            backgroundColor: const Color(0xFF274647),
            action: SnackBarAction(
              label: 'OPEN',
              textColor: Colors.white,
              onPressed: () async {
                final file = File(savedPath);
                if (await file.exists()) {
                  // Use the 'open_file' package to open the file with the default app
                  await open_file.OpenFile.open(savedPath);
                }
              },
            ),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(snackBar);
          }
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Failed to save PDF')));
        }
      }
    } catch (e) {
      debugPrint('Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Widget _buildControls(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Account selector (compact): show selected short name and an icon-only menu
        if (_accounts.isNotEmpty) ...[
          // show short name and dropdown icon together inside a bordered box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedAccountId == null
                        ? 'All Accounts'
                        : _shortBankName(
                            _accounts
                                .firstWhere(
                                  (a) => a.id == _selectedAccountId,
                                  orElse: () => _accounts.first,
                                )
                                .bankName,
                          ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PopupMenuButton<String?>(
                  icon: const Icon(Icons.arrow_drop_down),
                  onSelected: (val) {
                    setState(() {
                      _selectedAccountId = val;
                    });
                  },
                  itemBuilder: (context) {
                    return [
                      const PopupMenuItem<String?>(
                        value: null,
                        child: Text('All Accounts'),
                      ),
                      ..._accounts.map((a) {
                        final mask = a.accountNumber;
                        final label = mask.length > 4
                            ? '${a.bankName} • ****${mask.substring(mask.length - 4)}'
                            : '${a.bankName} • $mask';
                        return PopupMenuItem<String?>(
                          value: a.id,
                          child: Text(label),
                        );
                      }),
                    ];
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Date filter dropdown
        DropdownButtonFormField<String>(
          value: _selectedFilter,
          decoration: const InputDecoration(labelText: 'Date Range'),
          items: _dateFilters
              .map(
                (f) => DropdownMenuItem<String>(
                  value: f['value'],
                  child: Text(f['label']!),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) _applyDateFilter(v);
          },
        ),
        const SizedBox(height: 8),

        // Selected date readout
        Row(
          children: [
            Expanded(
              child: Text(
                'Selected: ${DateFormat('MMM d, yyyy').format(_selectedDateRange.start)} - ${DateFormat('MMM d, yyyy').format(_selectedDateRange.end)}',
              ),
            ),
            if (_selectedFilter == 'custom')
              IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: _selectCustomDateRange,
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Buttons row (Share & Download) — enforce equal height and equal width
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: _isSharing ? null : _exportAndSharePdf,
                  icon: _isSharing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.share),
                  label: Text(_isSharing ? 'Preparing...' : 'Share PDF'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: _isDownloading ? null : _downloadPdf,
                  icon: _isDownloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download),
                  label: Text(_isDownloading ? 'Saving...' : 'Download PDF'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTransactionList(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Please log in'));

    // Use account-aware query for the on-screen list (descending order for newest first)
    final stream = _transactionsQuery(uid, descending: true).snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No transactions found'));
        }

        // Build table rows and totals
        double totalDebit = 0.0;
        double totalCredit = 0.0;
        final rows = docs.map<DataRow>((d) {
          final data = d.data();
          final rawDate = data['date'];
          DateTime date;
          if (rawDate is Timestamp) {
            date = rawDate.toDate();
          } else if (rawDate is DateTime)
            date = rawDate;
          else
            date =
                DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();

          final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
          final isExpense =
              (data['type'] ?? 'expense').toString().toLowerCase() == 'expense';
          final debit = isExpense ? amount.abs() : 0.0;
          final credit = !isExpense ? amount.abs() : 0.0;
          totalDebit += debit;
          totalCredit += credit;

          return DataRow(
            cells: [
              DataCell(Text(DateFormat('dd/MM/yyyy').format(date))),
              DataCell(
                Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    data['description'] ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    debit != 0.0 ? '₹${debit.toStringAsFixed(2)}' : '',
                  ),
                ),
              ),
              DataCell(
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    credit != 0.0 ? '₹${credit.toStringAsFixed(2)}' : '',
                  ),
                ),
              ),
            ],
          );
        }).toList();

        // totals row
        rows.add(
          DataRow(
            cells: [
              const DataCell(
                Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const DataCell(Text('')),
              DataCell(
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '₹${totalDebit.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
              DataCell(
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '₹${totalCredit.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        // Responsive: make the table fill available width and still allow horizontal scroll
        return LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  columnSpacing: 12,
                  columns: const [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Narration')),
                    DataColumn(label: Text('Debit'), numeric: true),
                    DataColumn(label: Text('Credit'), numeric: true),
                  ],
                  rows: rows,
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export & Backup'), centerTitle: true),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 420, child: _buildControls(context)),
                      const SizedBox(width: 20),
                      Expanded(child: _buildTransactionList(context)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildControls(context),
                      const SizedBox(height: 16),
                      Expanded(child: _buildTransactionList(context)),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
