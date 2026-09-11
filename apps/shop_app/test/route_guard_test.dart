import 'package:flutter_test/flutter_test.dart';

import 'package:shop_app/src/providers/shop_providers.dart';

void main() {
  test('ShopData with pending kyc is not approved', () {
    const data = ShopData(exists: true, shopId: 'shop_1', kycStatus: 'pending');
    expect(data.isApproved, isFalse);
    expect(data.isPending, isTrue);
  });

  test('ShopData with approved kyc is approved', () {
    const data = ShopData(
      exists: true,
      shopId: 'shop_1',
      kycStatus: 'approved',
    );
    expect(data.isApproved, isTrue);
    expect(data.isPending, isFalse);
  });

  test('ShopData routes correctly for rejected kyc', () {
    const data = ShopData(
      exists: true,
      shopId: 'shop_1',
      kycStatus: 'rejected',
    );
    expect(data.isRejected, isTrue);
    expect(data.isApproved, isFalse);
  });

  test('ShopData with no shop and no kyc routes to name entry', () {
    const data = ShopData(exists: false, kycStatus: 'none');
    expect(data.exists, isFalse);
    expect(data.kycStatus, 'none');
  });
}
