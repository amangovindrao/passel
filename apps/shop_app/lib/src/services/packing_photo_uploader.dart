import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Raised when a photo could not be stored, with a message fit to show.
class PackingPhotoFailure implements Exception {
  const PackingPhotoFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Takes the packing photo for an order and puts it in Supabase Storage.
///
/// This is a state-machine requirement, not decoration: an order cannot leave
/// PREPARING without one, because it is the shop's evidence of what went into
/// the bag when a customer later says something was missing.
///
/// Deliberately camera-first. A packing photo is meant to be of the bag as it
/// is being sealed, and letting the gallery be the default invites a photo of
/// something else entirely — but the gallery stays reachable, because a shop
/// with a broken camera app should still be able to dispatch orders.
class PackingPhotoUploader {
  PackingPhotoUploader({
    SupabaseClient? client,
    ImagePicker? picker,
    this.bucket = 'order-photos',
  }) : _client = client ?? Supabase.instance.client,
       _picker = picker ?? ImagePicker();

  final SupabaseClient _client;
  final ImagePicker _picker;

  /// Separate from the KYC bucket on purpose. These have a different audience —
  /// the rider and the customer may both need to see one — and a different
  /// lifetime from an identity document.
  final String bucket;

  /// Prompts for a photo, uploads it, and returns a URL for the backend.
  ///
  /// Returns null when the shopkeeper backs out of the picker. That is an
  /// ordinary cancellation and must not read as a failure, or the UI will show
  /// an error for someone who simply changed their mind.
  Future<String?> pickAndUpload({
    required String orderId,
    ImageSource source = ImageSource.camera,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      // Enough to see what is in the bag. Shops photograph orders one after
      // another on whatever connection they have, so size matters more than
      // fidelity.
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return null;

    if (_client.auth.currentUser == null) {
      throw const PackingPhotoFailure('Sign in again to upload the photo');
    }

    // Timestamped rather than fixed: re-packing an order should add a photo,
    // not quietly replace the evidence of the first attempt.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$orderId/packing-$stamp.${_extensionOf(picked.name)}';

    try {
      await _client.storage.from(bucket).upload(path, File(picked.path));
      return await _client.storage
          .from(bucket)
          .createSignedUrl(path, const Duration(days: 30).inSeconds);
    } on StorageException catch (e) {
      throw PackingPhotoFailure(e.message);
    } on Exception {
      throw const PackingPhotoFailure(
        'Could not upload that photo. Check your connection and try again.',
      );
    }
  }

  static String _extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot == -1 || dot == filename.length - 1) return 'jpg';
    return filename.substring(dot + 1).toLowerCase();
  }
}
