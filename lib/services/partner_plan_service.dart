class PartnerPlanService {
  PartnerPlanService._();

  static const int onboardingFee = 299;
  static const int premiumFee = 699;
  static const int standardSharePercent = 85;
  static const int premiumSharePercent = 90;

  static String standardPlanName = 'STANDARD_PARTNER';
  static String premiumPlanName = 'PREMIUM_CHAUFFEUR';

  static double partnerShare({required double fare, required bool premium}) {
    final percent = premium ? premiumSharePercent : standardSharePercent;
    return fare * percent / 100;
  }

  static String shareLabel(bool premium) {
    return '${premium ? premiumSharePercent : standardSharePercent}% driver earnings';
  }
}
