/// Domain models for Paasel Group Order and Private Cart Mode.

class GroupOrderCartItemModel {
  const GroupOrderCartItemModel({
    required this.id,
    required this.shopId,
    this.shopName,
    required this.productId,
    this.productName,
    required this.qty,
    required this.priceAtAdditionPaise,
    required this.subtotalPaise,
  });

  final String id;
  final String shopId;
  final String? shopName;
  final String productId;
  final String? productName;
  final int qty;
  final int priceAtAdditionPaise;
  final int subtotalPaise;

  double get priceRupees => priceAtAdditionPaise / 100.0;
  double get subtotalRupees => subtotalPaise / 100.0;

  factory GroupOrderCartItemModel.fromJson(Map<String, dynamic> json) {
    return GroupOrderCartItemModel(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      shopName: json['shop_name'] as String?,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String?,
      qty: (json['qty'] as num?)?.toInt() ?? 1,
      priceAtAdditionPaise: (json['price_at_addition_paise'] as num?)?.toInt() ?? 0,
      subtotalPaise: (json['subtotal_paise'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'shop_id': shopId,
    'shop_name': shopName,
    'product_id': productId,
    'product_name': productName,
    'qty': qty,
    'price_at_addition_paise': priceAtAdditionPaise,
    'subtotal_paise': subtotalPaise,
  };
}

class GroupOrderMemberModel {
  const GroupOrderMemberModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.isCreator,
    required this.status,
    required this.paymentStatus,
    this.items = const [],
    this.subtotalPaise,
    this.paidAmountPaise,
    this.walletAmountUsedPaise,
  });

  final String id;
  final String userId;
  final String name;
  final bool isCreator;
  final String status;
  final String paymentStatus;
  final List<GroupOrderCartItemModel> items;
  final int? subtotalPaise;
  final int? paidAmountPaise;
  final int? walletAmountUsedPaise;

  double? get subtotalRupees => subtotalPaise != null ? subtotalPaise! / 100.0 : null;

  factory GroupOrderMemberModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return GroupOrderMemberModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String? ?? 'Member',
      isCreator: json['is_creator'] as bool? ?? false,
      status: json['status'] as String? ?? 'joined',
      paymentStatus: json['payment_status'] as String? ?? 'pending',
      items: rawItems
          .map((i) => GroupOrderCartItemModel.fromJson(i as Map<String, dynamic>))
          .toList(),
      subtotalPaise: (json['subtotal_paise'] as num?)?.toInt(),
      paidAmountPaise: (json['paid_amount_paise'] as num?)?.toInt(),
      walletAmountUsedPaise: (json['wallet_amount_used_paise'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'name': name,
    'is_creator': isCreator,
    'status': status,
    'payment_status': paymentStatus,
    'items': items.map((i) => i.toJson()).toList(),
    'subtotal_paise': subtotalPaise,
    'paid_amount_paise': paidAmountPaise,
    'wallet_amount_used_paise': walletAmountUsedPaise,
  };
}

class GroupOrderProgressModel {
  const GroupOrderProgressModel({
    required this.memberCount,
    required this.shopCount,
    required this.cartsReadyCount,
    required this.paymentsCompletedCount,
    required this.statusText,
    required this.deliverySavingsPaise,
    this.groupTotalPaise,
  });

  final int memberCount;
  final int shopCount;
  final int cartsReadyCount;
  final int paymentsCompletedCount;
  final String statusText;
  final int deliverySavingsPaise;
  final int? groupTotalPaise;

  double get deliverySavingsRupees => deliverySavingsPaise / 100.0;
  double? get groupTotalRupees => groupTotalPaise != null ? groupTotalPaise! / 100.0 : null;

  factory GroupOrderProgressModel.fromJson(Map<String, dynamic> json) {
    return GroupOrderProgressModel(
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      shopCount: (json['shop_count'] as num?)?.toInt() ?? 0,
      cartsReadyCount: (json['carts_ready_count'] as num?)?.toInt() ?? 0,
      paymentsCompletedCount: (json['payments_completed_count'] as num?)?.toInt() ?? 0,
      statusText: json['status_text'] as String? ?? 'Ordering together',
      deliverySavingsPaise: (json['delivery_savings_paise'] as num?)?.toInt() ?? 0,
      groupTotalPaise: (json['group_total_paise'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'member_count': memberCount,
    'shop_count': shopCount,
    'carts_ready_count': cartsReadyCount,
    'payments_completed_count': paymentsCompletedCount,
    'status_text': statusText,
    'delivery_savings_paise': deliverySavingsPaise,
    'group_total_paise': groupTotalPaise,
  };
}

class GroupOrderPackageModel {
  const GroupOrderPackageModel({
    required this.id,
    required this.sessionId,
    this.orderId,
    required this.shopId,
    required this.memberId,
    this.handoverOtp,
    required this.pickupStatus,
    required this.deliveryStatus,
    required this.handoverStatus,
    required this.handoverType,
  });

  final String id;
  final String sessionId;
  final String? orderId;
  final String shopId;
  final String memberId;
  final String? handoverOtp;
  final String pickupStatus;
  final String deliveryStatus;
  final String handoverStatus;
  final String handoverType;

  factory GroupOrderPackageModel.fromJson(Map<String, dynamic> json) {
    return GroupOrderPackageModel(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      orderId: json['order_id'] as String?,
      shopId: json['shop_id'] as String,
      memberId: json['member_id'] as String,
      handoverOtp: json['handover_otp'] as String?,
      pickupStatus: json['pickup_status'] as String? ?? 'PENDING',
      deliveryStatus: json['delivery_status'] as String? ?? 'NOT_READY',
      handoverStatus: json['handover_status'] as String? ?? 'PENDING',
      handoverType: json['handover_type'] as String? ?? 'CAPTAIN_HANDOVER',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'session_id': sessionId,
    'order_id': orderId,
    'shop_id': shopId,
    'member_id': memberId,
    'handover_otp': handoverOtp,
    'pickup_status': pickupStatus,
    'delivery_status': deliveryStatus,
    'handover_status': handoverStatus,
    'handover_type': handoverType,
  };
}

class GroupOrderSessionModel {
  const GroupOrderSessionModel({
    required this.id,
    required this.creatorId,
    this.deliveryAddressId,
    required this.societyName,
    required this.status,
    required this.privateCartMode,
    this.closesAt,
    this.paymentComplete = false,
    required this.progress,
    this.members = const [],
    this.myCart = const [],
    this.mySubtotalPaise = 0,
    this.packages = const [],
  });

  final String id;
  final String creatorId;
  final String? deliveryAddressId;
  final String societyName;
  final String status;
  final bool privateCartMode;
  final DateTime? closesAt;
  final bool paymentComplete;
  final GroupOrderProgressModel progress;
  final List<GroupOrderMemberModel> members;
  final List<GroupOrderCartItemModel> myCart;
  final int mySubtotalPaise;
  final List<GroupOrderPackageModel> packages;

  double get mySubtotalRupees => mySubtotalPaise / 100.0;
  bool get isLocked => status == 'LOCKED' || status == 'PROCESSING' || status == 'DELIVERED';

  factory GroupOrderSessionModel.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'] as List<dynamic>? ?? [];
    final rawMyCart = json['my_cart'] as List<dynamic>? ?? [];
    final rawPackages = json['packages'] as List<dynamic>? ?? [];

    return GroupOrderSessionModel(
      id: json['id'] as String,
      creatorId: json['creator_id'] as String,
      deliveryAddressId: json['delivery_address_id'] as String?,
      societyName: json['society_name'] as String? ?? 'Society Group Order',
      status: json['status'] as String? ?? 'OPEN',
      privateCartMode: json['private_cart_mode'] as bool? ?? false,
      closesAt: json['closes_at'] != null ? DateTime.tryParse(json['closes_at'] as String) : null,
      paymentComplete: json['payment_complete'] as bool? ?? false,
      progress: GroupOrderProgressModel.fromJson(json['progress'] as Map<String, dynamic>? ?? {}),
      members: rawMembers
          .map((m) => GroupOrderMemberModel.fromJson(m as Map<String, dynamic>))
          .toList(),
      myCart: rawMyCart
          .map((i) => GroupOrderCartItemModel.fromJson(i as Map<String, dynamic>))
          .toList(),
      mySubtotalPaise: (json['my_subtotal_paise'] as num?)?.toInt() ?? 0,
      packages: rawPackages
          .map((p) => GroupOrderPackageModel.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'creator_id': creatorId,
    'delivery_address_id': deliveryAddressId,
    'society_name': societyName,
    'status': status,
    'private_cart_mode': privateCartMode,
    'closes_at': closesAt?.toIso8601String(),
    'payment_complete': paymentComplete,
    'progress': progress.toJson(),
    'members': members.map((m) => m.toJson()).toList(),
    'my_cart': myCart.map((i) => i.toJson()).toList(),
    'my_subtotal_paise': mySubtotalPaise,
    'packages': packages.map((p) => p.toJson()).toList(),
  };
}
