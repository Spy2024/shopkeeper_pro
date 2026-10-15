import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/business_branch.dart';
import '../../providers/branch_provider.dart';

class BranchManagementScreen extends StatefulWidget {
  const BranchManagementScreen({super.key});

  @override
  State<BranchManagementScreen> createState() => _BranchManagementScreenState();
}

class _BranchManagementScreenState extends State<BranchManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      await context.read<BranchProvider>().load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load branches: $e')),
      );
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editBranch({BusinessBranch? branch}) async {
    final nameController = TextEditingController(text: branch?.name ?? '');
    final codeController = TextEditingController(text: branch?.code ?? '');
    final addressController = TextEditingController(text: branch?.address ?? '');
    final phoneController = TextEditingController(text: branch?.phone ?? '');
    final managerController = TextEditingController(text: branch?.managerName ?? '');
    var isActive = branch?.isActive ?? true;
    var saving = false;
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(branch == null ? 'Add branch' : 'Edit branch'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Branch name'),
                ),
                TextField(
                  controller: codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Branch code',
                    helperText: '2–20 letters, numbers, dashes or underscores.',
                  ),
                ),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                TextField(
                  controller: managerController,
                  decoration: const InputDecoration(labelText: 'Manager name'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Branch active'),
                  value: isActive,
                  onChanged: (value) => setDialogState(() => isActive = value),
                ),
                if (error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(error!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving ? null : () async {
                setDialogState(() {
                  saving = true;
                  error = null;
                });
                try {
                  await dialogContext.read<BranchProvider>().saveBranch(
                    id: branch?.id,
                    name: nameController.text,
                    code: codeController.text,
                    address: addressController.text,
                    phone: phoneController.text,
                    managerName: managerController.text,
                    isActive: isActive,
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop(true);
                } catch (e) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() {
                    error = e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', '');
                    saving = false;
                  });
                }
              },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save branch'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    codeController.dispose();
    addressController.dispose();
    phoneController.dispose();
    managerController.dispose();
    if (saved == true && mounted) _message('Branch saved.');
  }

  Future<void> _handleAction(BusinessBranch branch, String action) async {
    final provider = context.read<BranchProvider>();
    try {
      switch (action) {
        case 'main':
          await provider.setMainBranch(branch.id);
          _message('${branch.name} is now the main branch.');
          break;
        case 'edit':
          await _editBranch(branch: branch);
          break;
        case 'active':
          await provider.saveBranch(
            id: branch.id,
            name: branch.name,
            code: branch.code,
            address: branch.address,
            phone: branch.phone,
            managerName: branch.managerName,
            isActive: !branch.isActive,
          );
          _message(branch.isActive ? 'Branch deactivated.' : 'Branch activated.');
          break;
        case 'delete':
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Delete branch?'),
              content: Text('Delete ${branch.name} only if it has no historical records. Otherwise deactivate it.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
              ],
            ),
          );
          if (confirmed == true) {
            await provider.deleteBranch(branch.id);
            _message('Branch deleted.');
          }
          break;
      }
    } catch (e) {
      _message(e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BranchProvider>();
    final branches = provider.branches;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Branch Management'),
        actions: [
          IconButton(
            tooltip: 'Refresh branches',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editBranch(),
        icon: const Icon(Icons.add_business),
        label: const Text('Add branch'),
      ),
      body: provider.isLoading && branches.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : branches.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No branches yet. Add your first branch to enable branch-level stock and sales.'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: branches.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final branch = branches[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(branch.isMain ? Icons.star : Icons.store_outlined),
                        ),
                        title: Text(branch.name),
                        subtitle: Text([
                          'Code: ${branch.code}',
                          if (branch.managerName.isNotEmpty) 'Manager: ${branch.managerName}',
                          if (branch.address.isNotEmpty) branch.address,
                          branch.isMain ? 'Main branch' : branch.isActive ? 'Active' : 'Inactive',
                        ].join(' • ')),
                        isThreeLine: branch.managerName.isNotEmpty || branch.address.isNotEmpty,
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) => _handleAction(branch, action),
                          itemBuilder: (_) => [
                            if (!branch.isMain && branch.isActive)
                              const PopupMenuItem(value: 'main', child: Text('Set as main')),
                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'active',
                              child: Text(branch.isActive ? 'Deactivate' : 'Activate'),
                            ),
                            if (!branch.isMain)
                              const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}