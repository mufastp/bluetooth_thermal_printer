/// Company information shown on the receipt header.
class CompanyInfo {
  final String name;
  final String address1;
  final String address2;
  final String phone;
  final String? taxNo;
  final String? email;

  const CompanyInfo({
    this.name = '',
    this.address1 = '',
    this.address2 = '',
    this.phone = '',
    this.taxNo,
    this.email,
  });
}
