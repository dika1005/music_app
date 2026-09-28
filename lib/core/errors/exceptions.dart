class ServerException implements Exception {
  final String message;
  const ServerException([this.message = 'Server error']);
}

class NetworkException implements Exception {
  const NetworkException();
}
