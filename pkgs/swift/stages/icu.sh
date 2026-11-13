#!/bin/sh
# Reduced ICU data objects (SWIFTC_ICU=small|tiny). Each defines the same symbol
# as lib_FoundationICU.a(icu_packaged_data.cpp.o); linked before the archives it
# keeps the linker from pulling the 34 MB full-data member.
. "$PKG/stages/common.sh"
O=$B/icudata; mkdir -p "$O"; cd "$O"
python3 "$PKG/files/icu-trim/extract.py" "$W/src/swift-foundation-icu/icuSources/common" "$O/icudt-full.dat" > "$LOGS/icu.log" 2>&1
python3 "$PKG/files/icu-trim/make_profiles.py" "$O/icudt-full.dat" "$O" >> "$LOGS/icu.log" 2>&1
SYM=$("$NATIVE/bin/llvm-ar" p $SDK/usr/lib/swift_static/linux-static/lib_FoundationICU.a icu_packaged_data.cpp.o > "$O/ref.o" && "$NATIVE/bin/llvm-nm" "$O/ref.o" | awk '$2=="R"{print $3}')
[ -n "$SYM" ] || { echo "could not determine the ICU data symbol"; exit 1; }
for p in small tiny; do
  cat > "$O/icudata-$p.S" <<S
    .section .rodata.$SYM,"a",%progbits
    .globl $SYM
    .type $SYM,%object
    .balign 16
$SYM:
    .incbin "$O/icudt-$p.dat"
    .size $SYM, .-$SYM
    .section .note.GNU-stack,"",%progbits
S
  clang --target=$TRIPLE -c "$O/icudata-$p.S" -o "$O/icudata-$p.o"
done
rm -f "$O/ref.o"; ls -la "$O"/*.o
