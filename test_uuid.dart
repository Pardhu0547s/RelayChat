import 'package:uuid/uuid.dart';
void main() {
  final uuid = Uuid();
  print(uuid.v4obj().toBytes());
}
