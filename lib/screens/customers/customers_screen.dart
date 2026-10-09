import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/customer.dart';
import '../../providers/customer_provider.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await context.read<CustomerProvider>().load();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showCustomerDialog({Customer? existing}) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: existing?.name ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    final email = TextEditingController(text: existing?.email ?? '');
    final notes = TextEditingController(text: existing?.notes ?? '');
    final provider = context.read<CustomerProvider>();
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(existing == null ? 'Add customer' : 'Edit customer'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Full name *'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                ),
                TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'Mobile number'), keyboardType: TextInputType.phone),
                TextFormField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) return 'Enter a valid email';
                    return null;
                  },
                ),
                TextFormField(controller: notes, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 2),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  if (existing == null) {
                    await provider.add(name: name.text, phone: phone.text, email: email.text, notes: notes.text);
                  } else {
                    await provider.updateCustomer(Customer(
                      id: existing.id, name: name.text.trim(),
                      phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
                      email: email.text.trim().isEmpty ? null : email.text.trim(),
                      notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                      createdAt: existing.createdAt,
                    ));
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (e) {
                  if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Could not save customer: $e')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (saved == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer saved')));
      }
    } finally {
      name.dispose(); phone.dispose(); email.dispose(); notes.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomerProvider>();
    final customers = provider.search(_searchController.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search name, phone or email',
              suffixIcon: _searchController.text.isEmpty ? null : IconButton(
                onPressed: () { _searchController.clear(); setState(() {}); },
                icon: const Icon(Icons.clear),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : customers.isEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.people_outline, size: 52),
                    const SizedBox(height: 12),
                    Text(_searchController.text.isEmpty ? 'No customers yet' : 'No matching customers'),
                    const SizedBox(height: 8),
                    const Text('Add customer details to keep contact information organized.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: () => _showCustomerDialog(), icon: const Icon(Icons.add), label: const Text('Add customer')),
                  ]),
                ))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  itemCount: customers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final customer = customers[index];
                    final details = [customer.phone, customer.email].whereType<String>().where((v) => v.isNotEmpty).join(' • ');
                    return ListTile(
                      leading: CircleAvatar(child: Text(customer.name.trim()[0].toUpperCase())),
                      title: Text(customer.name),
                      subtitle: Text([details, customer.notes ?? ''].where((v) => v.isNotEmpty).join('\n')),
                      isThreeLine: customer.notes?.isNotEmpty == true,
                      onTap: () => _showCustomerDialog(existing: customer),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await _showCustomerDialog(existing: customer);
                          } else if (value == 'delete') {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete customer?'),
                                content: Text('Remove ' + customer.name + ' from this device?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (confirmed == true && context.mounted) await context.read<CustomerProvider>().delete(customer.id);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCustomerDialog(),
        tooltip: 'Add customer',
        child: const Icon(Icons.add),
      ),
    );
  }
}
