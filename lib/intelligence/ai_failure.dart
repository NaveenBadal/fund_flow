/// Raised when a provider returns a non-2xx HTTP status.
///
/// [detail] carries the provider's own error text when it sent any — a
/// retired model, an invalid key — so the message can name the real cause
/// rather than a bare status code.
class AiRequestFailure implements Exception {
  const AiRequestFailure(this.statusCode, [this.detail]);
  final int statusCode;
  final String? detail;

  @override
  String toString() => detail == null ? 'Provider error $statusCode.' : detail!;
}
