import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/business_branch.dart';
import '../../providers/branch_provider.dart';

class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<BranchProvider>().load();
    });
  }

  Future<void> _editBranch([BusinessBranch? branch]) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: branch?.name ?? '');
    final code = TextEditingController(text: branch?.code ?? '');
    final address = TextEditingController(text: branch?.address ?? '');
    final phone = TextEditingController(text: branch?.phone ?? '');
    final manager = TextEditingController(text: branch?.managerName ?? '');
    var active = branch?.isActive ?? true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(branch == null ? 'Add branch' : 'Edit branch'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Branch name *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter branch name' : null),
                    TextFormField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Branch code *', helperText: '2–20 letters, numbers, _ or -'), validator: (v) => (v == null || !RegExp(r'^[A-Za-z0-9_-]{2,20}$').hasMatch(v.trim())) ? 'Enter a valid unique code' : null),
                    TextFormField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
                    TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
                    TextFormField(controller: manager, decoration: const InputDecoration(labelText: 'Branch manager')),
                    SwitchListTile(title: const Text('Branch active'), value: active, onChanged: (value) => setDialogState(() => active = value)),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true); }, child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result == true && mounted) {
      try {
        await context.read<BranchProvider>().saveBranch(
          id: branch?.id,
          name: name.text,
          code: code.text,
          address: address.text,
          phone: phone.text,
          managerName: manager.text,
          isActive: active,
        );
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Branch save failed: ${e.toString().replaceFirst('Exception: ', '')}')));
      }
    }
    name.dispose();
    code.dispose();
    address.dispose();
    phone.dispose();
    manager.dispose();
  }

  Future<void> _deleteBranch(BusinessBranch branch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete branch?'),
        content: Text('Delete "${branch.name}"? The main branch cannot be deleted. This local branch registry is not yet connected to transaction assignment or cloud sync.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<BranchProvider>().deleteBranch(branch.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BranchProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Branches')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _editBranch(), icon: const Icon(Icons.add), label: const Text('Add branch')),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.branches.isEmpty
              ? const Center(child: Text('No branches yet. Add your first branch.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.branches.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final branch = provider.branches[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(branch.isMain ? Icons.star : Icons.store_outlined),
                        title: Text(branch.name),
                        subtitle: Text('${branch.code} • ${branch.address.isEmpty ? 'No address' : branch.address}\n${branch.managerName.isEmpty ? 'No manager' : branch.managerName} • ${branch.isActive ? 'Active' : 'Inactive'}'),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            if (action == 'main') {
                              await context.read<BranchProvider>().setMainBranch(branch.id);
                            } else if (action == 'edit') {
                              await _editBranch(branch);
                            } else if (action == 'delete') {
                              await _deleteBranch(branch);
                            }
                          },
                          itemBuilder: (_) => [
                            if (!branch.isMain) const PopupMenuItem(value: 'main', child: Text('Set as main branch')),
                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                            if (!branch.isMain) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
