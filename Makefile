CC     = xcrun -sdk iphoneos clang++
ARCH   = -arch arm64
FWORKS = -framework UIKit -framework QuartzCore -framework Foundation
OUT    = CheatMenu.dylib
SRC    = src/CheatMenu.mm

.PHONY: all clean

all: $(OUT)

$(OUT): $(SRC)
	$(CC) $(ARCH) -dynamiclib $(FWORKS) -o $@ $<
	ldid -S $@

clean:
	rm -f $(OUT)
