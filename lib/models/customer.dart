class Customer {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? notes;
  final DateTime createdAt;

  Customer({required this.id, required this.name, this.phone, this.email, this.notes, required this.createdAt}) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id', 'Cannot be empty.');
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name', 'Cannot be empty.');
  }

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name.trim(), 'phone': phone?.trim(),
    'email': email?.trim(), 'notes': notes?.trim(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
    id: map['id'] as String,
    name: map['name'] as String,
    phone: map['phone'] as String?,
    email: map['email'] as String?,
    notes: map['notes'] as String?,
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}
