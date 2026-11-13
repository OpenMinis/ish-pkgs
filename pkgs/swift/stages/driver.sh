#!/bin/sh
# swift-driver (the Swift-written driver; optional at run time, SWIFTC_DRIVER=new)
. "$PKG/stages/common.sh"
"$PKG/stages/patch-sdk.sh" check
cd "$W/src/swift-driver"
rm -f "$B/swift-driver-static/out/Products/$PRODUCTS/swift-driver"
SWIFTCI_USE_LOCAL_DEPS=1 run driver swift build -c release --swift-sdk $TRIPLE --product swift-driver \
  --scratch-path "$B/swift-driver-static" $XFLAGS
[ -x "$B/swift-driver-static/out/Products/$PRODUCTS/swift-driver" ]
