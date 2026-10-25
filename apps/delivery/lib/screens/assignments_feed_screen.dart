import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../app/api_client.dart';
import '../app/auth_store.dart';
import 'proof_of_delivery_screen.dart';

class AssignmentsFeedScreen extends StatefulWidget {
  const AssignmentsFeedScreen({super.key});

  @override
  State<AssignmentsFeedScreen> createState() => _AssignmentsFeedScreenState();
}

class _AssignmentsFeedScreenState extends State<AssignmentsFeedScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await context.read<ApiClient>().listAssignments();
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _rows = const [];
      });
    }
  }

  Future<void> _flip({
    required String assignmentId,
    required String to,
  }) async {
    try {
      double? lat;
      double? lng;
      // GPS only on transitions that need it (DELIVERED requires it, the
      // others are cheap to skip).
      if (to == 'OUT_FOR_DELIVERY' || to == 'DELIVERED') {
        final pos = await _readGps();
        lat = pos?.latitude;
        lng = pos?.longitude;
      }
      await context
          .read<ApiClient>()
          .updateStatus(assignmentId: assignmentId, status: to, lat: lat, lng: lng);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<Position?> _readGps() async {
    try {
      final hasPermission = await Geolocator.checkPermission();
      if (hasPermission == LocationPermission.denied) {
        final granted = await Geolocator.requestPermission();
        if (granted == LocationPermission.denied ||
            granted == LocationPermission.deniedForever) {
          return null;
        }
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _openProofScreen(Map<String, dynamic> row) async {
    final assignmentId = row['id'] as String;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProofOfDeliveryScreen(assignmentId: assignmentId),
      ),
    );
    if (result == true) await _load();
  }

  Future<void> _logout() async {
    await context.read<ApiClient>().logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<Widget>(
        builder: (_) => const Scaffold(body: SizedBox.expand()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My deliveries'),
        actions: [
          FutureBuilder<String?>(
            future: context.read<AuthStore>().riderId(),
            builder: (_, snap) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  snap.data == null ? '' : 'Rider ${snap.data!.substring(0, 8)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                ],
              )
            : _rows == null
                ? const Center(child: CircularProgressIndicator())
                : _rows!.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(child: Text('No open deliveries right now. 🌿')),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rows!.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _AssignmentCard(
                          row: _rows![i],
                          onPickedUp: () =>
                              _flip(assignmentId: _rows![i]['id'] as String, to: 'PICKED_UP'),
                          onOutForDelivery: () =>
                              _flip(assignmentId: _rows![i]['id'] as String, to: 'OUT_FOR_DELIVERY'),
                          onOpenProof: () => _openProofScreen(_rows![i]),
                        ),
                      ),
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({
    required this.row,
    required this.onPickedUp,
    required this.onOutForDelivery,
    required this.onOpenProof,
  });

  final Map<String, dynamic> row;
  final VoidCallback onPickedUp;
  final VoidCallback onOutForDelivery;
  final VoidCallback onOpenProof;

  @override
  Widget build(BuildContext context) {
    final status = row['status'] as String? ?? 'ASSIGNED';
    final order = (row['order'] as Map?) ?? const {};
    final address = (order['shippingAddress'] as Map?) ?? const {};
    final customer = (order['customer'] as Map?) ?? const {};
    final items = (order['items'] as List?) ?? const [];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE5DDC8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusChip(status: status),
                const Spacer(),
                Text(
                  'Order ${(order['id'] as String? ?? '').substring(0, 8)}…',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              customer['name'] as String? ?? '(customer)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if ((customer['phone'] as String?)?.isNotEmpty ?? false)
              Text(customer['phone'] as String, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 8),
            Text(
              [
                address['line1'],
                if ((address['line2'] as String?)?.isNotEmpty ?? false) address['line2'],
                address['city'],
                address['postalCode'],
              ].whereType<String>().join(', '),
              style: const TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 12),
            ...items.map((it) {
              final m = Map<String, dynamic>.from(it as Map);
              final variant = (m['variant'] as Map?) ?? const {};
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${m['quantity']} × ${variant['name'] ?? ''} (${variant['size'] ?? ''})',
                  style: const TextStyle(fontSize: 13),
                ),
              );
            }),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == 'ASSIGNED')
                  FilledButton(onPressed: onPickedUp, child: const Text('Picked up')),
                if (status == 'PICKED_UP')
                  FilledButton(
                    onPressed: onOutForDelivery,
                    child: const Text('Out for delivery'),
                  ),
                if (status == 'OUT_FOR_DELIVERY')
                  FilledButton(onPressed: onOpenProof, child: const Text('Mark delivered')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'ASSIGNED' => const Color(0xFFEAB648),
      'PICKED_UP' => const Color(0xFFB0E8B7),
      'OUT_FOR_DELIVERY' => const Color(0xFF557F41),
      _ => const Color(0xFFCBD5C0),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}
