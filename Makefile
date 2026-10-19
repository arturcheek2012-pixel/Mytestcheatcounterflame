CC      = xcrun -sdk iphoneos clang++
ARCH    = -arch arm64
FLAGS   = -fobjc-arc -Wno-deprecated-declarations
LDFLAGS = -Wl,-undefined,dynamic_lookup
FWORKS  = -framework UIKit \
           -framework QuartzCore \
           -framework Foundation \
           -framework CoreGraphics
OUT     = CheatMenu.dylib
SRC     = src/CheatMenu.mm

.PHONY: all clean

all: $(OUT)

$(OUT): $(SRC)
	$(CC) $(ARCH) $(FLAGS) -dynamiclib $(FWORKS) $(LDFLAGS) -o $@ $<
	ldid -S $@

clean:
	rm -f $(OUT)
