import 'package:core/core.dart';

/// Verification state plus today's activity, from GET /delivery-partners/me.
class RiderData {
  const RiderData({
    required this.exists,
    this.name,
    this.kycStatus,
    this.kycRejectionReason,
    this.vehicleType,
    this.vehicleNumber,
    this.isOnline = false,
    this.completedToday = 0,
  });

  factory RiderData.fromJson(Map<String, dynamic> json) => RiderData(
    exists: json['exists'] as bool,
    name: json['name'] as String?,
    kycStatus: json['kyc_status'] as String?,
    kycRejectionReason: json['kyc_rejection_reason'] as String?,
    vehicleType: json['vehicle_type'] as String?,
    vehicleNumber: json['vehicle_number'] as String?,
    isOnline: json['is_online'] as bool? ?? false,
    completedToday: json['completed_today'] as int? ?? 0,
  );

  final bool exists;
  final String? name;
  final String? kycStatus;

  /// Why a reviewer turned the application down. Only ever set when
  /// [isRejected], and shown verbatim — a rejection nobody can act on is
  /// worse than no answer at all.
  final String? kycRejectionReason;
  final String? vehicleType;
  final String? vehicleNumber;
  final bool isOnline;

  /// A plain tally of deliveries finished today. Not an earnings figure — money
  /// is reconciled on the wallet screen, and a half-computed number here would
  /// be worse than showing none.
  final int completedToday;

  bool get isApproved => kycStatus == 'approved';
  bool get isPending => kycStatus == 'pending' || kycStatus == 'submitted';
  bool get isRejected => kycStatus == 'rejected';

  /// True before any documents have been submitted at all.
  bool get needsKyc => !exists || kycStatus == null;
}

/// Vehicle options offered on the KYC screen.
enum VehicleChoice {
  bicycle('bicycle', 'Bicycle'),
  bike('bike', 'Bike'),
  scooter('scooter', 'Scooter');

  const VehicleChoice(this.wire, this.label);

  final String wire;
  final String label;

  /// A bicycle has no plate and needs no licence, so those fields are hidden
  /// outright rather than greyed out — a disabled field still reads as
  /// "something I am failing to fill in".
  bool get requiresRegistration => this != VehicleChoice.bicycle;
}

/// Which kind of offer is on screen. The two look and behave differently
/// enough that collapsing them into one flag would lose real information.
enum OfferKind {
  /// A brand new delivery, 35-second window.
  fresh,

  /// A mid-trip detour onto an existing trip, 20-second window.
  batchDetour,
}

/// An offer awaiting the rider's answer.
class RiderOffer {
  const RiderOffer({
    required this.assignmentId,
    required this.orderId,
    required this.kind,
    required this.shopName,
    required this.windowSeconds,
    required this.earningPaise,
    this.itemCount = 0,
    this.distanceToShopMeters,
    this.detourMeters,
    this.shopPhotoUrl,
  });

  /// From GET /delivery-partners/me/offer.
  ///
  /// The same offer as [RiderOffer.fromAlert] describes, arriving by the pull
  /// route instead of the push one. `window_seconds` is the server's count of
  /// the time *left*, so an offer picked up 30 seconds late shows five seconds
  /// rather than a fresh 35.
  factory RiderOffer.fromJson(Map<String, dynamic> json) {
    final kind = json['offer_type'] == 'batch_detour'
        ? OfferKind.batchDetour
        : OfferKind.fresh;
    return RiderOffer(
      assignmentId: json['assignment_id'] as String? ?? '',
      orderId: json['order_id'] as String? ?? '',
      kind: kind,
      shopName: json['shop_name'] as String? ?? 'Shop',
      windowSeconds:
          (json['window_seconds'] as num?)?.toInt() ??
          (kind == OfferKind.batchDetour ? 20 : 35),
      earningPaise: (json['delivery_fee_paise'] as num?)?.toInt() ?? 0,
      itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
      distanceToShopMeters: (json['distance_to_shop_m'] as num?)?.toInt(),
      detourMeters: (json['detour_meters'] as num?)?.toInt(),
      shopPhotoUrl: json['shop_photo_url'] as String?,
    );
  }

  factory RiderOffer.fromAlert(AlertMessage alert) {
    final kind = alert['offer_type'] == 'batch_detour'
        ? OfferKind.batchDetour
        : OfferKind.fresh;
    return RiderOffer(
      assignmentId: alert['assignment_id'] ?? '',
      orderId: alert['order_id'] ?? '',
      kind: kind,
      shopName: alert['shop_name'] ?? 'Shop',
      windowSeconds:
          alert.intOf('window_seconds') ??
          (kind == OfferKind.batchDetour ? 20 : 35),
      earningPaise: alert.intOf('delivery_fee_paise') ?? 0,
      itemCount: alert.intOf('item_count') ?? 0,
      distanceToShopMeters: alert.intOf('distance_to_shop_m'),
      detourMeters: alert.intOf('detour_meters'),
      shopPhotoUrl: alert['shop_photo_url'],
    );
  }

  final String assignmentId;
  final String orderId;
  final OfferKind kind;
  final String shopName;
  final int windowSeconds;

  /// What the rider earns for this delivery. The first number they look at.
  final int earningPaise;
  final int itemCount;
  final int? distanceToShopMeters;

  /// Extra distance a Tier 2 detour adds to the trip they are already on.
  final int? detourMeters;
  final String? shopPhotoUrl;

  bool get isBatchDetour => kind == OfferKind.batchDetour;
}

/// The assignment the rider is currently committed to.
class ActiveAssignment {
  const ActiveAssignment({
    required this.assignmentId,
    required this.orderId,
    required this.shopName,
    required this.orderStatus,
    this.ordersOnTrip = 1,
  });

  final String assignmentId;
  final String orderId;
  final String shopName;

  /// Wire status of the order, e.g. PARTNER_ASSIGNED, PICKED_UP.
  final String orderStatus;

  /// How many orders share this trip — grows via Tier 1 and Tier 2 additions.
  final int ordersOnTrip;

  bool get isBeforePickup =>
      orderStatus == 'PARTNER_ASSIGNED' ||
      orderStatus == 'PARTNER_ARRIVED_AT_SHOP';

  String get progressLabel =>
      isBeforePickup ? 'Heading to pickup' : 'Picked up, heading to drop-off';

  ActiveAssignment copyWith({String? orderStatus, int? ordersOnTrip}) =>
      ActiveAssignment(
        assignmentId: assignmentId,
        orderId: orderId,
        shopName: shopName,
        orderStatus: orderStatus ?? this.orderStatus,
        ordersOnTrip: ordersOnTrip ?? this.ordersOnTrip,
      );
}

/// Whether location access is good enough to actually track a delivery.
enum LocationAccess {
  unknown,

  /// Refused outright, or permanently denied.
  denied,

  /// "While using the app only". Looks like success and is not: the moment the
  /// rider's screen locks, tracking dies and the customer's map freezes.
  whileInUseOnly,

  /// "Always" — the only state background reporting can rely on.
  always;

  bool get canGoOnline => this == LocationAccess.always;
}
