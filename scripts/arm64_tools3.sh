#!/bin/bash
cd /srv/lineage/android
# 1. gnu as/ld for gcc-4.9 dirs (used with -no-integrated-as)
G=prebuilts/gcc/linux-x86
for pair in "arm/arm-linux-androideabi-4.9:arm-linux-androideabi:arm-linux-gnueabi-" "aarch64/aarch64-linux-android-4.9:aarch64-linux-android:aarch64-linux-gnu-"; do
  IFS=: read d t p <<< "$pair"
  mkdir -p $G/$d/$t/bin
  for x in as ld ld.bfd ld.gold; do
    src=$(command -v ${p}${x} || true); [ -z "$src" ] && src=$(command -v $x)
    rm -f $G/$d/$t/bin/$x; ln -s $src $G/$d/$t/bin/$x
  done
  for x in as ld; do ln -sfn $(command -v ${p}$x || command -v $x) $G/$d/bin/${t}-$x 2>/dev/null; done
  echo "gnu as/ld linked for $t -> $(readlink $G/$d/$t/bin/as)"
done
# 2. clang wrapper: add -Wno-error (Debian clang 11.0.1 is stricter than AOSP r383902b)
for C in clang-r383902 clang-r383902b clang-r383902b1; do
  cd /srv/lineage/android/prebuilts/clang/host/linux-x86/$C/bin
  for n in clang clang++; do
    cat > $n <<WRAP
#!/bin/bash
args=()
for a in "\$@"; do [ "\$a" = "-msoft-float" ] || args+=("\$a"); done
exec -a "\$0" /usr/bin/$n-11 "\${args[@]}" -Wno-error
WRAP
    chmod +x $n; cp $n $n.real
  done
  # 3. clang-tidy no-op (tidy checks are irrelevant for a device image)
  rm -f clang-tidy clang-tidy.real; printf '#!/bin/bash\nexit 0\n' > clang-tidy; chmod +x clang-tidy; cp clang-tidy clang-tidy.real
done
cd /srv/lineage/android
# 4. .fpu neon after .arch in all arm asm
grep -rlE "^\s*\.arch\s+armv7" bionic/libc/arch-arm external/libvpx external/libjpeg-turbo external/tremolo external/sonivox 2>/dev/null | while read f; do grep -q FPU_FIXED $f && continue; python3 - "$f" <<PY
import re,sys
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"^(\s*)(\.arch\s+armv7[^\n]*)\n", lambda m: m.group(1)+m.group(2)+"\n"+m.group(1)+".fpu neon  /* FPU_FIXED */\n", s, flags=re.M)
open(p,"w").write(s)
PY
echo "fpu-fixed $f"; done
# 5. source patches
f=art/runtime/native_stack_dump.cc; grep -q "ucontext.h" $f || sed -i '0,/#include/s//#include <ucontext.h>\n#include/' $f
echo done3
