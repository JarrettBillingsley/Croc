find ./croc -name '*.d' -exec dmd '{}' -w -c -g -cov -debug -op \;
find . -name 'croctest.d' -exec dmd '{}' -w -c -g -cov -debug -op \;
dmd @blerf.rsp