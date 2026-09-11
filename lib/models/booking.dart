class Booking {
  String id;
  String customer;
  String date;
  String time;
  String pickup;
  String destination;
  String vehicle;
  String status;
  int earnings;
  String? partnerId;
  String? acceptedBy;
  DateTime? acceptedAt;

  Booking({
    required this.id,
    required this.customer,
    required this.date,
    required this.time,
    required this.pickup,
    required this.destination,
    required this.vehicle,
    required this.status,
    required this.earnings,
    this.partnerId,
    this.acceptedBy,
    this.acceptedAt,
  });
}
