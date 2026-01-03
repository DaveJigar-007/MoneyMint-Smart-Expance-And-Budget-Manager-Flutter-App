import 'package:flutter/material.dart';
import 'contact_support_screen.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How to use MoneyMint',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              '1. Add a bank account',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              ' - Open "Bank Accounts" from the menu and tap + to add a new account.',
            ),
            const SizedBox(height: 8),
            const Text(
              '2. Add transactions',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              ' - From the Home Dashboard tap "Add Expense / Income" to record a transaction.',
            ),
            const SizedBox(height: 8),
            const Text(
              '3. View transactions',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              ' - Go to the user transactions or Bank Accounts tile to view transactions grouped by date.',
            ),
            const SizedBox(height: 8),
            const Text(
              '4. Track balance & budgets',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              ' - Balances update automatically when you add transactions. Use Budget Setup to configure limits.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Tips',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              ' - Always double-check the amount and account before saving a transaction.',
            ),
            const Text(' - Use clear descriptions for easier searching later.'),
            const SizedBox(height: 16),
            const Text(
              'Reporting Transaction Issues',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'If a transaction is incorrect or missing, please contact support with the following details:',
            ),
            const SizedBox(height: 8),
            const Text(
              ' - Transaction date\n - Transaction amount\n - Bank/account name\n - Approximate time or transaction ID (if available)\n - Any screenshot or proof (attach screenshots in email)',
            ),
            const SizedBox(height: 12),
            const Text(
              'Contact Support',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('Email: support@moneymint.com'),
            const SizedBox(height: 6),
            const Text('Phone: +91-7284921275'),
            const SizedBox(height: 12),
            const Text(
              'Response Time',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              ' - Support aims to respond within 24-48 hours. Include all requested details to speed up resolution.',
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ContactSupportScreen(),
                    ),
                  );
                },
                child: const Text('Contact Support'),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Note', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              ' - This is a temporary help page. You can update the contact details and add FAQs or links as needed.',
            ),
          ],
        ),
      ),
    );
  }
}
