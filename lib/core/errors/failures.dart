import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);
  @override
  List<Object> get props => [message];
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server error. Coba lagi.']);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Tidak ada koneksi internet.']);
}

class EmptyFailure extends Failure {
  const EmptyFailure([super.message = 'Tidak ada data.']);
}
