import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app/api_client.dart';

/// Proof-of-delivery screen — open camera, capture a single photo, upload
/// to S3 via the presigned-URL flow (Phase 11 wires the real S3 path), then
/// POST proof URL + transition to DELIVERED with GPS coords.
///
/// In Phase 8 the photo upload is stubbed: we use the local file path as the
/// "photoUrl" string. Phase 11 swaps in S3 multipart upload returning a CDN
/// URL.
class ProofOfDeliveryScreen extends StatefulWidget {
  const ProofOfDeliveryScreen({super.key, required this.assignmentId});
  final String assignmentId;

  @override
  State<ProofOfDeliveryScreen> createState() => _ProofOfDeliveryScreenState();
}

class _ProofOfDeliveryScreenState extends State<ProofOfDeliveryScreen> {
  XFile? _photo;
  Position? _position;
  bool _submitting = false;
  String? _error;

  Future<void> _capture() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (!mounted) return;
      if (file != null) setState(() => _photo = file);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _readGps() async {
    try {
      final permission = await Geolocator.checkPermission();
      LocationPermission granted = permission;
      if (permission == LocationPermission.denied) {
        granted = await Geolocator.requestPermission();
      }
      if (granted == LocationPermission.denied ||
          granted == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() => _error = 'Location permission required to confirm delivery');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() => _position = pos);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _submit() async {
    if (_photo == null) {
      setState(() => _error = 'Capture a photo first');
      return;
    }
    if (_position == null) {
      await _readGps();
      if (_position == null) return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      // Phase 8 stub: hand the API a placeholder URL that contains the local
      // path. Phase 11 will replace this with a real S3 presigned PUT + the
      // resulting CDN URL.
      final photoUrl =
          'https://placeholder.biobloom.local/proof/${Uri.encodeComponent(_photo!.name)}';
      await api.uploadProof(assignmentId: widget.assignmentId, photoUrl: photoUrl);
      await api.updateStatus(
        assignmentId: widget.assignmentId,
        status: 'DELIVERED',
        lat: _position!.latitude,
        lng: _position!.longitude,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Proof of delivery')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_photo == null)
            FilledButton.tonalIcon(
              onPressed: _capture,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Capture photo'),
            )
          else
            Column(
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.black12,
                    ),
                    child: Center(child: Text(_photo!.name)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _capture,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retake'),
                ),
              ],
            ),
          const SizedBox(height: 16),
          ListTile(
            tileColor: const Color(0xFFFBF6E8),
            leading: const Icon(Icons.location_on_outlined),
            title: Text(
              _position == null
                  ? 'Capture location'
                  : 'Lat ${_position!.latitude.toStringAsFixed(5)}, '
                      'Lng ${_position!.longitude.toStringAsFixed(5)}',
            ),
            trailing: FilledButton(onPressed: _readGps, child: const Text('Locate')),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(_submitting ? 'Submitting…' : 'Mark DELIVERED'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tip: stand near the customer’s door before tapping Locate so the GPS '
            'reading matches the delivery point.',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
