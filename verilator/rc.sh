rm -rf results/regress.res
find results -name "rv32*.log" -exec bin/find_test_fail.sh {} >> results/regress.res \;
cat results/regress.res
