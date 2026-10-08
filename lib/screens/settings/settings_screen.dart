import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/auth_provider.dart';
import '../../providers/finance_provider.dart';
import '../../providers/inventory_provider.dart';
import '../../providers/pos_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/shop_provider.dart';
import '../../providers/supplier_provider.dart';
import '../../services/backup_restore_service.dart';
import '../../services/account_deletion_service.dart';
import '../auth/phone_entry_screen.dart';
import '../profile/shop_profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<String?> _userId() async {
    final id = context.read<AuthProvider>().userUid;
    if (id == null || id.isEmpty) {
      _message('Please sign in again before using backup tools.');
      return null;
    }
    return id;
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _shareFile(File file, String text) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      text: text,
    ));
  }

  Future<void> _createBackup() async {
    final uid = await _userId();
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      final file = await BackupRestoreService.instance.createBackup(uid);
      if (!mounted) return;
      await _shareFile(file, 'Shopkeeper Pro account backup. Keep this file private.');
    } catch (e) {
      _message('Backup failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<void> _uploadCloudBackup() async {
    final uid = await _userId();
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      await BackupRestoreService.instance.uploadBackupToCloud(uid);
      _message('Cloud backup uploaded successfully.');
    } catch (e) {
      _message('Cloud backup failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreCloudBackup() async {
    final uid = await _userId();
    if (uid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore cloud backup?'),
        content: const Text(
          'This replaces current local shop records with the latest cloud backup. '
          'Export a fresh backup first if you need to keep the current data.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await BackupRestoreService.instance.restoreLatestCloudBackup(uid);
      if (!mounted) return;
      await Future.wait([
        context.read<ShopProvider>().load(),
        context.read<InventoryProvider>().load(),
        context.read<PosProvider>().loadHistory(),
        context.read<SupplierProvider>().load(),
        context.read<SalesProvider>().load(),
        context.read<FinanceProvider>().load(),
      ]);
      _message('Latest cloud backup restored.');
    } catch (e) {
      _message('Cloud restore failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createStatement() async {
    final uid = await _userId();
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      final file = await BackupRestoreService.instance.createFinancialStatement(uid);
      if (!mounted) return;
      await _shareFile(file, 'Shopkeeper Pro financial statement. Verify the figures before official use.');
    } catch (e) {
      _message('Statement generation failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final uid = await _userId();
    if (uid == null) return;
    final selected = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Shopkeeper Pro JSON backup', extensions: ['json']),
      ],
    );
    if (selected == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Replace local shop data?'),
        content: const Text(
          'Restore will replace the current local shop records with records from this backup. '
          'Make a fresh backup first. The backup must belong to the currently signed-in account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await BackupRestoreService.instance.restoreBackup(uid, File(selected.path));
      if (!mounted) return;
      await Future.wait([
        context.read<ShopProvider>().load(),
        context.read<InventoryProvider>().load(),
        context.read<PosProvider>().loadHistory(),
        context.read<SupplierProvider>().load(),
        context.read<SalesProvider>().load(),
        context.read<FinanceProvider>().load(),
      ]);
      _message('Backup restored. Review your shop, stock, and bill history.');
    } catch (e) {
      _message('Restore failed: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Your local shop data will remain stored under this account on this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneEntryScreen()),
      (route) => false,
    );
  }


  Future<void> _deleteAccount() async {
    final uid = await _userId();
    if (uid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permanently delete account?'),
        content: const Text(
          'This permanently deletes the signed-in Firebase account, its cloud records, cloud backups, '
          'and this account\'s local database on this device. This cannot be undone. '
          'For security, Firebase requires a recent sign-in and App Check verification.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AccountDeletionService.instance.deleteCurrentAccount(uid);
      await context.read<AuthProvider>().logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PhoneEntryScreen()),
        (route) => false,
      );
    } catch (e) {
      _message('Account deletion was not confirmed: ${e.toString().replaceFirst('Exception: ', '')}. If recent sign-in is required, sign out and sign in again before retrying.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = context.watch<ShopProvider>().shop;
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings & Backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.store_outlined),
              title: Text(shop?.name ?? 'Shop profile'),
              subtitle: const Text('Name, address, phone, and shop logo'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ShopProfileScreen()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Backup & Reports', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Export & share backup'),
                  subtitle: const Text('JSON backup of shop records. Store it somewhere safe.'),
                  onTap: _busy ? null : _createBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('Upload backup to cloud now'),
                  subtitle: const Text('Requires signed-in Firebase account and Storage rules.'),
                  onTap: _busy ? null : _uploadCloudBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: const Text('Restore latest cloud backup'),
                  subtitle: const Text('Replaces current local records after confirmation.'),
                  onTap: _busy ? null : _restoreCloudBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: const Text('Restore from backup'),
                  subtitle: const Text('Replaces current local records after confirmation.'),
                  onTap: _busy ? null : _restoreBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: const Text('Create financial statement PDF'),
                  subtitle: const Text('Share using WhatsApp, Gmail, or another installed app.'),
                  onTap: _busy ? null : _createStatement,
                ),
              ],
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(auth.emailAddress ?? auth.phoneNumber ?? 'Account'),
              subtitle: const Text('Signed-in account'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy || !auth.firebaseAvailable ? null : _deleteAccount,
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Delete account and cloud data'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Backups contain business and customer information. Share them only with trusted recipients. '
            'Automatic cloud backups run after successful sync, at most once per 24 hours; cloud restore requires deployed Storage rules.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
