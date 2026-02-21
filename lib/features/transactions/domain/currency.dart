const supportedCurrencies = ['MXN', 'USD', 'EUR'];

const mxnPerCurrency = {
  'MXN': 1.0,
  'USD': 17.0,
  'EUR': 18.5,
};

double toMxn(double amount, String currency) {
  final rate = mxnPerCurrency[currency] ?? 1.0;
  return amount * rate;
}
