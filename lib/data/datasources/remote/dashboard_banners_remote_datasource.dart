import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../models/dashboard_banner.dart';

/// Remote data source for the dashboard's admin-managed banners (BR-SAWX2U).
class DashboardBannersRemoteDataSource {
  final ApiClient _apiClient;

  DashboardBannersRemoteDataSource(this._apiClient);

  /// The banners this user qualifies for, already in render order.
  Future<ApiResult<List<DashboardBanner>>> getBanners() async {
    final result = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.dashboardBanners,
    );

    if (result.isFailure) {
      return ApiResult.failure(result.error!, statusCode: result.statusCode);
    }

    try {
      final rows = result.data!['data'] as List<dynamic>? ?? [];
      return ApiResult.success(rows
          .map((json) => DashboardBanner.fromJson(json as Map<String, dynamic>))
          .toList());
    } catch (e) {
      return ApiResult.failure('Failed to parse dashboard banners: $e');
    }
  }
}
