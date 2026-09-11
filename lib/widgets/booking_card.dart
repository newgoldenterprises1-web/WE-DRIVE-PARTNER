import 'package:flutter/material.dart';
const navy = Color(0xFF173B6D);
class BookingCard extends StatelessWidget {
  final String customer, dateTime, pickup, status;
  final VoidCallback? onTap;
  const BookingCard({super.key, required this.customer, required this.dateTime, required this.pickup, required this.status, this.onTap});
  @override Widget build(BuildContext context) => Card(child: ListTile(onTap:onTap, leading:const CircleAvatar(backgroundColor:Color(0xFFEAF0F8),child:Icon(Icons.directions_car,color:navy)), title:Text(customer,style:const TextStyle(fontWeight:FontWeight.w700)), subtitle:Text('$dateTime\n$pickup'), isThreeLine:true, trailing:Text(status,style:const TextStyle(fontSize:10,fontWeight:FontWeight.w800,color:navy))));
}
