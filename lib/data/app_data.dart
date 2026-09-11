import '../models/booking.dart';

class AppData {
  // Naye drivers ke liye default false rahega jab tak payment na ho
  static bool isPremiumPartner = false;

  static final List<Booking> bookings = <Booking>[
    Booking(
      id: 'WD1001',
      customer: 'Rahul Sharma',
      date: '25 Aug 2026',
      time: '09:30 AM',
      pickup: 'Banjara Hills, Hyderabad',
      destination: 'RGIA Airport, Hyderabad',
      vehicle: 'Hyundai Creta',
      status: 'REQUESTED',
      earnings: 850,
    ),
    Booking(
      id: 'WD1002',
      customer: 'Ayesha Khan',
      date: '26 Aug 2026',
      time: '06:00 PM',
      pickup: 'Jubilee Hills, Hyderabad',
      destination: 'HITEC City, Hyderabad',
      vehicle: 'Honda City',
      status: 'ACCEPTED',
      earnings: 650,
    ),
  ];

  static final List<Booking> premiumBookings = <Booking>[
    Booking(
      id: 'WD-P9001',
      customer: 'Arjun Mehta',
      date: '25 Aug 2026',
      time: '08:30 PM',
      pickup: 'Gachibowli, Hyderabad',
      destination: 'Banjara Hills, Hyderabad',
      vehicle: '',
      status: 'REQUESTED',
      earnings: 1450,
    ),
    Booking(
      id: 'WD-P9002',
      customer: 'Neha Reddy',
      date: '26 Aug 2026',
      time: '07:15 AM',
      pickup: 'Jubilee Hills, Hyderabad',
      destination: 'RGIA Airport, Hyderabad',
      vehicle: '',
      status: 'RESERVATION',
      earnings: 1650,
    ),
  ];

  static bool get premiumFeatureVisible => isPremiumPartner;
  
  static set premiumFeatureVisible(bool value) {
    isPremiumPartner = value;
  }
}