import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Which document a file belongs to. Determines the storage path.
enum DocumentKind {
  idProof('id_proof'),
  drivingLicence('driving_licence');

  const DocumentKind(this.slug);

  final String slug;
}

/// Raised when a document could not be stored, with a message fit to show.
class DocumentUploadFailure implements Exception {
  const DocumentUploadFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Picks a document photo and puts it in Supabase Storage.
///
/// A plain image picker, deliberately not camera_kit's guided frame: that
/// overlay exists so two photos of the same parcel can be compared
/// position-for-position, and a document photo has nothing to be compared
/// against. Letting the rider use an existing photo of their licence is also
/// simply kinder than making them re-shoot it.
class DocumentUploader {
  DocumentUploader({
    SupabaseClient? client,
    ImagePicker? picker,
    this.bucket = 'kyc-documents',
  }) : _client = client ?? Supabase.instance.client,
       _picker = picker ?? ImagePicker();

  final SupabaseClient _client;
  final ImagePicker _picker;

  /// Private bucket. KYC documents are identity documents; they must never be
  /// world-readable, so reads go through a short-lived signed URL.
  final String bucket;

  /// Prompts for a source, uploads, and returns a signed URL.
  ///
  /// Returns null when the rider backs out of the picker — that is a normal
  /// cancellation, not an error.
  Future<String?> pickAndUpload({
    required DocumentKind kind,
    ImageSource source = ImageSource.camera,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      // Documents only need to be legible. Downscaling keeps uploads quick on
      // the patchy connections riders actually have.
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return null;

    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const DocumentUploadFailure('Sign in again to upload documents');
    }

    final extension = _extensionOf(picked.name);
    final path = '$userId/${kind.slug}.$extension';

    try {
      await _client.storage.from(bucket).upload(
        path,
        File(picked.path),
        fileOptions: const FileOptions(upsert: true),
      );
      // Signed for a day: long enough for a reviewer to open it, short enough
      // that a leaked link stops working.
      return await _client.storage
          .from(bucket)
          .createSignedUrl(path, const Duration(days: 1).inSeconds);
    } on StorageException catch (e) {
      throw DocumentUploadFailure(e.message);
    } on Exception {
      throw const DocumentUploadFailure(
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
