/// Core package for Paasel apps.
///
/// Provides shared domain models, API client, providers, and utilities.
library;

export 'src/alerts/alert_center.dart';
export 'src/alerts/alert_message.dart';
export 'src/alerts/alert_signal.dart';
export 'src/alerts/alert_transport.dart';
export 'src/api/api_client.dart';
export 'src/api/auth_interceptor.dart';
export 'src/auth/phone_auth.dart';
export 'src/env/bootstrap.dart';
export 'src/env/env_config.dart';
export 'src/errors/app_error.dart';
export 'src/errors/result.dart';
export 'src/geo/geo_helpers.dart';
export 'src/models/models.dart';
export 'src/providers/auth_provider.dart';
export 'src/catalog/catalog_templates.dart';
export 'src/repositories/address_repository.dart';
export 'src/repositories/auth_repository.dart';
export 'src/repositories/customer_repository.dart';
export 'src/repositories/order_repository.dart';
export 'src/repositories/shop_repository.dart';
export 'src/repositories/wallet_repository.dart';
export 'src/repositories/group_order_repository.dart';
export 'src/services/product_recognizer.dart';
