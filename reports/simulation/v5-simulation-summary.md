# V5 Economic Core Simulation Report
Generated: 2026-09-18T12:48:49.314Z

## 1. Scale Benchmarks
| Houses | Days | Duration (ms) | Survival Rate | Market Volume (Credits) | Earth Revenue | Gini |
|---|---|---|---|---|---|---|
| 100 | 90 | 11ms | 100.0% | 562,218 | 1,647,100 | 0.050 |
| 1000 | 90 | 49ms | 100.0% | 5,631,338 | 23,483,500 | 0.043 |
| 10000 | 30 | 172ms | 100.0% | 21,918,971 | 78,712,810 | 0.019 |

## 2. Canonical Scenario Matrix (100 Houses, 90 Days)
| Scenario | Survival Rate | Trades | Earth Revenue | Specialization Advantage | Gini | Closing Material | Closing Energy | Closing Food |
|---|---|---|---|---|---|---|---|---|
| `all-houses-choose-energy` | 3.0% | 290 | 1,006,735 | 1.00x | 0.006 | 118.7 | 5.1 | 41.6 |
| `all-houses-choose-food` | 3.0% | 0 | 1,173,855 | 1.00x | 0.018 | 8.5 | 49.7 | 5.1 |
| `corporation-material-monopoly` | 100.0% | 23777 | 1,817,270 | 1.38x | 0.267 | 5.0 | 248.5 | 5.0 |
| `energy-shortage` | 3.0% | 9678 | 1,269,140 | 1.01x | 0.037 | 21.3 | 259.9 | 15.9 |
| `compute-shortage` | 100.0% | 24226 | 1,647,100 | 1.04x | 0.058 | 5.0 | 15.3 | 5.0 |
| `excess-material` | 100.0% | 24226 | 1,647,100 | 1.08x | 0.061 | 5.0 | 15.3 | 5.0 |
| `excess-components` | 100.0% | 24226 | 1,647,100 | 1.06x | 0.049 | 5.0 | 15.3 | 5.0 |
| `low-rent` | 100.0% | 24226 | 1,579,600 | 1.05x | 0.050 | 5.0 | 15.3 | 5.0 |
| `progressive-rent` | 100.0% | 24226 | 1,669,372 | 1.05x | 0.050 | 5.0 | 15.3 | 5.0 |
| `many-small-corporations` | 100.0% | 24226 | 1,657,900 | 1.05x | 0.050 | 5.0 | 15.3 | 5.0 |
| `one-mega-corporation` | 100.0% | 24226 | 1,169,830 | 1.05x | 0.050 | 5.0 | 15.3 | 5.0 |
| `inactive-players` | 100.0% | 15190 | 1,466,300 | 1.08x | 0.043 | 5.0 | 19.9 | 5.0 |
| `bankrupt-producers` | 84.0% | 21644 | 1,619,820 | 1.74x | 0.400 | 5.0 | 118.2 | 5.0 |
| `construction-boom` | 100.0% | 23547 | 2,662,100 | 1.38x | 0.121 | 5.0 | 21.7 | 5.0 |
| `stalled-construction` | 100.0% | 23887 | 1,063,950 | 0.99x | 0.029 | 5.0 | 5.0 | 5.0 |
| `independent-heavy` | 100.0% | 22909 | 801,370 | 1.02x | 0.043 | 5.0 | 5.0 | 5.0 |
| `baseline` | 100.0% | 24226 | 1,647,100 | 1.05x | 0.050 | 5.0 | 15.3 | 5.0 |
