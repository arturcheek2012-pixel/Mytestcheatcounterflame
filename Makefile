CC     = xcrun -sdk iphoneos clang++
ARCH   = -arch arm64
FLAGS  = -fobjc-arc -Wno-deprecated-declarations
FWORKS = -framework UIKit -framework QuartzCore -framework Foundation
OUT    = CheatMenu.dylib
SRC    = src/CheatMenu.mm

.PHONY: all clean

all: $(OUT)

$(OUT): $(SRC)
	$(CC) $(ARCH) $(FLAGS) -dynamiclib $(FWORKS) -o $@ $<
	ldid -S $@

clean:
	rm -f $(OUT)
