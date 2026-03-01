voltages = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.4, 2.9, 3.1];
heights = [0, 1, 5, 9, 13, 15, 16, 17, 20.5, 21];

sum_vi = sum(voltages);
sum_hi = sum(heights);
sum_vi_hi = sum(voltages .* heights);
sum_vi_squared = sum(voltages .^ 2);
N = length(voltages);



A = [sum_vi_squared, sum_vi; sum_vi, N];
b = [sum_vi_hi; sum_hi];

x = inv(A) * b;
disp(x);