# Makefile for building a single configuration of Wren. It allows the
# following variables to be passed to it:
#
# MODE - The build mode, "debug" or "release".
#				 If omitted, defaults to "release".
# LANG - The language, "c" or "cpp".
# 		   If omitted, defaults to "c".
# ARCH - The processor architecture, "32", "64", or nothing, which indicates
#				 the compiler's default.
#        If omitted, defaults to the compiler's default.
#
# It builds a static library, shared library, and command-line interpreter for
# the given configuration. Libraries are built to "lib", and the interpreter
# is built to "bin".
#
# The output file is initially "wren". If in debug mode, "d" is appended to it.
# If the language is "cpp", then "-cpp" is appended to that. If the
# architecture is not the default then "-32" or "-64" is appended to that.
# Then, for the libraries, the correct extension is added.

# Files.
OPT_HEADERS := $(wildcard src/optional/*.h) $(wildcard src/optional/*.wren.inc)
OPT_SOURCES := $(wildcard src/optional/*.c)

VM_HEADERS   := $(wildcard src/vm/*.h) $(wildcard src/vm/*.wren.inc)
VM_SOURCES   := $(wildcard src/vm/*.c)

API_TEST_HEADERS := $(wildcard test/api/*.h)
API_TEST_SOURCES := $(wildcard test/api/*.c)

UNIT_TEST_HEADERS := $(wildcard test/unit/*.h)
UNIT_TEST_SOURCES := $(wildcard test/unit/*.c)

BUILD_DIR := build

# Allows one to enable verbose builds with VERBOSE=1
V := @
ifeq ($(VERBOSE),1)
	V :=
endif

C_OPTIONS := $(WREN_CFLAGS)
C_WARNINGS := -Wall -Wextra -Werror -Wno-unused-parameter
# Wren uses callbacks heavily, so -Wunused-parameter is too painful to enable.

# Mode configuration.
ifeq ($(MODE),debug)
	WREN := wrend
	C_OPTIONS += -O0 -DDEBUG -g
	BUILD_DIR := $(BUILD_DIR)/debug
else
	WREN += wren
	C_OPTIONS += -O3
	BUILD_DIR := $(BUILD_DIR)/release
endif

# Language configuration.
ifeq ($(LANG),cpp)
	WREN := $(WREN)-cpp
	C_OPTIONS += -std=c++98
	FILE_FLAG := -x c++
	BUILD_DIR := $(BUILD_DIR)-cpp
else
	C_OPTIONS += -std=c99
endif

# Architecture configuration.
ifeq ($(ARCH),32)
	C_OPTIONS += -m32
	WREN := $(WREN)-32
	BUILD_DIR := $(BUILD_DIR)-32
endif

ifeq ($(ARCH),64)
	C_OPTIONS += -m64
	WREN := $(WREN)-64
	BUILD_DIR := $(BUILD_DIR)-64
endif

# Some platform-specific workarounds. Note that we use "gcc" explicitly in the
# call to get the machine name because one of these workarounds deals with $(CC)
# itself not working.
OS := $(lastword $(subst -, ,$(shell gcc -dumpmachine)))

# Don't add -fPIC on Windows since it generates a warning which gets promoted
# to an error by -Werror.
ifeq      ($(OS),mingw32)
else ifeq ($(OS),cygwin)
	# Do nothing.
else
	C_OPTIONS += -fPIC
endif

# MinGW--or at least some versions of it--default CC to "cc" but then don't
# provide an executable named "cc". Manually point to "gcc" instead.
ifeq ($(OS),mingw32)
	CC = GCC
endif

# Clang on Mac OS X has different flags and a different extension to build a
# shared library.
ifneq (,$(findstring darwin,$(OS)))
	SHARED_EXT := dylib
else
	SHARED_LIB_FLAGS := -Wl,-soname,libwren.so
	SHARED_EXT := so
endif

CFLAGS := $(C_OPTIONS) $(C_WARNINGS)

OPT_OBJECTS       := $(addprefix $(BUILD_DIR)/optional/, $(notdir $(OPT_SOURCES:.c=.o)))
VM_OBJECTS        := $(addprefix $(BUILD_DIR)/vm/, $(notdir $(VM_SOURCES:.c=.o)))
API_TEST_OBJECTS  := $(patsubst test/api/%.c, $(BUILD_DIR)/test/api/%.o, $(API_TEST_SOURCES))
UNIT_TEST_OBJECTS := $(patsubst test/unit/%.c, $(BUILD_DIR)/test/unit/%.o, $(UNIT_TEST_SOURCES))

# Targets ---------------------------------------------------------------------

# Builds the VM libraries.
all: vm

# Builds just the VM libraries.
vm: shared static

# Builds the shared VM library.
shared: lib/lib$(WREN).$(SHARED_EXT)

# Builds the static VM library.
static: lib/lib$(WREN).a

# Builds the API test executable.
api_test: $(BUILD_DIR)/test/api_$(WREN)

# Builds the unit test executable.
unit_test: $(BUILD_DIR)/test/unit_$(WREN)

# Static library.
lib/lib$(WREN).a: $(OPT_OBJECTS) $(VM_OBJECTS)
	@ printf "%10s %-30s %s\n" $(AR) $@ "rcu"
	$(V) mkdir -p lib
	$(V) $(AR) rcu $@ $^

# Shared library.
lib/lib$(WREN).$(SHARED_EXT): $(OPT_OBJECTS) $(VM_OBJECTS)
	@ printf "%10s %-30s %s\n" $(CC) $@ "$(C_OPTIONS) $(SHARED_LIB_FLAGS)"
	$(V) mkdir -p lib
	$(V) $(CC) $(CFLAGS) -shared $(SHARED_LIB_FLAGS) -o $@ $^

# Optional object files.
$(BUILD_DIR)/optional/%.o: src/optional/%.c $(VM_HEADERS) $(OPT_HEADERS)
	@ printf "%10s %-30s %s\n" $(CC) $< "$(C_OPTIONS)"
	$(V) mkdir -p $(BUILD_DIR)/optional
	$(V) $(CC) -c $(CFLAGS) -Isrc/include -Isrc/vm -o $@ $(FILE_FLAG) $<

# VM object files.
$(BUILD_DIR)/vm/%.o: src/vm/%.c $(VM_HEADERS)
	@ printf "%10s %-30s %s\n" $(CC) $< "$(C_OPTIONS)"
	$(V) mkdir -p $(BUILD_DIR)/vm
	$(V) $(CC) -c $(CFLAGS) -Isrc/include -Isrc/optional -Isrc/vm -o $@ $(FILE_FLAG) $<

# Wren modules that get compiled into the binary as C strings.
src/optional/wren_opt_%.wren.inc: src/optional/wren_opt_%.wren util/wren_to_c_string.py
	@ printf "%10s %-30s %s\n" str $<
	$(V) ./util/wren_to_c_string.py $@ $<

src/vm/wren_%.wren.inc: src/vm/wren_%.wren util/wren_to_c_string.py
	@ printf "%10s %-30s %s\n" str $<
	$(V) ./util/wren_to_c_string.py $@ $<

.PHONY: all api_test unit_test vm
