rdmd --force -version=OpDelegates -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpDelegates -version=Strict -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpDelegates -version=Cumulative -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpDelegates -version=Strict -version=Cumulative -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpFunctions -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpFunctions -version=Strict -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpFunctions -version=Cumulative -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpFunctions -version=Strict -version=Cumulative -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpSwitch -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpSwitch -version=Strict -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpSwitch -version=Cumulative -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpSwitch -version=Strict -version=Cumulative -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpNestedSwitch -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpNestedSwitch -version=Strict -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpNestedSwitch -version=Cumulative -I.. -I../src test_new_cpu.d &&
rdmd --force -version=OpNestedSwitch -version=Strict -version=Cumulative -I.. -I../src test_new_cpu.d

