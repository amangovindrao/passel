import 'package:core/src/api/api_client.dart';
import 'package:core/src/errors/result.dart';

/// A saved delivery address.
class SavedAddress {
  const SavedAddress({
    required this.id,
    required this.label,
    required this.addressText,
  });

  factory SavedAddress.fromJson(Map<String, dynamic> json) => SavedAddress(
        id: json['id'] as String,
        label: json['label'] as String,
        addressText: json['address_text'] as String,
      );

  final String id;
  final String label;
  final String addressText;
}

/// Repository for saved addresses.
class AddressRepository {
  AddressRepository(this._client);
  final ApiClient _client;

  Future<Result<List<SavedAddress>>> listAddresses() =>
      _client.get<List<SavedAddress>>(
        '/api/v1/addresses',
        fromJson: (data) => (data as List)
            .map((e) => SavedAddress.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Future<Result<SavedAddress>> createAddress({
    required String label,
    required double lat,
    required double lng,
    required String addressText,
  }) =>
      _client.post<SavedAddress>(
        '/api/v1/addresses',
        data: {
          'label': label,
          'lat': lat,
          'lng': lng,
          'address_text': addressText,
        },
        fromJson: (data) => SavedAddress.fromJson(data as Map<String, dynamic>),
      );

  Future<Result<Map<String, dynamic>>> deleteAddress(String id) =>
      _client.delete<Map<String, dynamic>>(
        '/api/v1/addresses/$id',
        fromJson: (data) => data as Map<String, dynamic>,
      );
}
