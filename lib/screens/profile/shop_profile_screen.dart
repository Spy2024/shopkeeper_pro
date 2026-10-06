import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/shop_provider.dart';
import '../dashboard/home_screen.dart';

class ShopProfileScreen extends StatefulWidget {
  final bool isFirstSetup;
  const ShopProfileScreen({super.key, this.isFirstSetup = false});

  @override
  State<ShopProfileScreen> createState() => _ShopProfileScreenState();
}

class _ShopProfileScreenState extends State<ShopProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  String? _logoPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final shop = context.read<ShopProvider>().shop;
    if (shop != null) {
      _nameCtrl.text = shop.name;
      _addressCtrl.text = shop.address;
      _phoneCtrl.text = shop.phone;
      _taxCtrl.text = shop.taxNumber ?? '';
      _logoPath = shop.logoPath;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _taxCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (file != null && mounted) setState(() => _logoPath = file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to select logo: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isFirstSetup ? 'Set Up Your Shop' : 'Shop Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickLogo,
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: _logoPath != null ? FileImage(File(_logoPath!)) : null,
                    child: _logoPath == null
                        ? const Icon(Icons.add_a_photo_outlined, size: 32, color: Colors.grey)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Center(child: Text('Tap to upload shop logo', style: TextStyle(color: Colors.grey))),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Shop Name', prefixIcon: Icon(Icons.store)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(labelText: 'Shop Address', prefixIcon: Icon(Icons.location_on)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone)),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _taxCtrl,
                decoration: const InputDecoration(
                  labelText: 'NTN / Tax Number (optional)',
                  prefixIcon: Icon(Icons.receipt_long),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) return;
                        setState(() => _saving = true);
                        try {
                          await context.read<ShopProvider>().save(
                                name: _nameCtrl.text,
                                address: _addressCtrl.text,
                                phone: _phoneCtrl.text,
                                taxNumber: _taxCtrl.text,
                                logoPath: _logoPath,
                              );
                          if (!context.mounted) return;
                          if (widget.isFirstSetup) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => const HomeScreen()),
                              (route) => false,
                            );
                          } else {
                            Navigator.pop(context);
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not save shop: $e')),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.isFirstSetup ? 'Finish Setup' : 'Save Changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
