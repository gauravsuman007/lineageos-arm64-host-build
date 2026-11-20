#!/bin/bash
# Make prebuilts clang-r383902 run natively: keep headers/runtime libs, replace executables by system clang-11/lld/llvm tools.
set -e
cd /srv/lineage/android/prebuilts/clang/host/linux-x86
for C in clang-r383902 clang-r383902b clang-r383902b1; do
[ -d $C.x86 ] || cp -a $C $C.x86
cd $C/bin
for n in clang clang++ clang.real clang++.real clang-11 clang-tidy clang-tidy.real; do
  rm -f $n
done
ln -s /usr/bin/clang-11 clang; ln -s /usr/bin/clang-11 clang.real; ln -s /usr/bin/clang-11 clang-11
ln -s /usr/bin/clang++-11 clang++; ln -s /usr/bin/clang++-11 clang++.real
for t in ld.lld lld lld-link llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-readelf llvm-readobj llvm-strip llvm-ranlib llvm-size llvm-strings llvm-profdata llvm-cov llvm-dwarfdump llvm-addr2line llvm-link llvm-as llvm-dis llvm-config clang-format clang-tidy; do
  s=$(ls /usr/bin/$t-11 /usr/lib/llvm-11/bin/$t 2>/dev/null | head -1); [ -n "$s" ] && { rm -f $t; ln -s $s $t; }
done
cd ../..
done
cd clang-r383902/bin; ls -l | head -60 | awk '{print $9,$10,$11}' | tr '\n' ';'
echo; ./clang --version | head -2
# resource dir lookup: Debian clang searches <bindir>/../lib/clang/11.0.1
cd /srv/lineage/android/prebuilts/clang/host/linux-x86
for C in clang-r383902 clang-r383902b clang-r383902b1; do
  v=$(ls $C/lib64/clang | head -1); mkdir -p $C/lib/clang; ln -sfn ../../lib64/clang/$v $C/lib/clang/11.0.1
done
# old clang used by renderscript
cd clang-3289846/bin
[ -d ../bin.x86 ] || cp -a . ../bin.x86
for n in clang.real clang++.real; do rm -f $n; ln -s /usr/bin/clang-11 $n; done
for t in llvm-as llvm-dis llvm-link; do rm -f $t; ln -s /usr/bin/$t-11 $t; done
echo done-clang-extra
# wrapper: Debian clang treats -msoft-float as disabling FP/NEON even when -mfloat-abi=softfp follows; drop it
for C in clang-r383902 clang-r383902b clang-r383902b1; do
  cd /srv/lineage/android/prebuilts/clang/host/linux-x86/$C/bin
  for n in clang clang++; do
    real=/usr/bin/$n-11
    rm -f $n
    cat > $n <<WRAP
#!/bin/bash
args=()
for a in "\$@"; do [ "\$a" = "-msoft-float" ] || args+=("\$a"); done
exec -a "\$0" $real "\${args[@]}"
WRAP
    chmod +x $n
  done
  rm -f clang.real clang++.real; cp clang clang.real 2>/dev/null; cp clang++ clang++.real 2>/dev/null
done
echo wrapper-installed
# composite resource dir: Debian headers (match the compiler's builtins) + AOSP runtime libs/share
for C in clang-r383902 clang-r383902b clang-r383902b1; do
  cd /srv/lineage/android/prebuilts/clang/host/linux-x86/$C
  v=$(ls lib64/clang | head -1)
  rm -rf lib/clang/11.0.1; mkdir -p lib/clang/11.0.1
  for e in lib64/clang/$v/*; do n=$(basename $e); [ "$n" = include ] || ln -s $(pwd)/lib64/clang/$v/$n lib/clang/11.0.1/$n; done
  ln -s /usr/lib/llvm-11/lib/clang/11.0.1/include lib/clang/11.0.1/include
done
echo composite-resource-dir
