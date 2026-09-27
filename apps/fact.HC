// NeoOS Sample NeoC Script: Factorial
I64 factorial(I64 n) {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}
factorial(6);
