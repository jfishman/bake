#!/usr/bin/make

### Main build target
#
.PHONY: all
all:    targets

### Output verbosity
#
# Define V=... (to anything non-empty) to enable logging every action
#
$(V).SILENT:

ifeq ($(MAKELEVEL),0)
###
## Top-level Make
###

### Default build type if unspecified
#
ifeq ($(origin BUILD_TYPE),undefined)
ifeq ($(DEBUG),)
BUILD_TYPE := release
else
BUILD_TYPE := debug
endif
endif

### Build type as goal overrides environment
#
release:        BUILD_TYPE := release
debug:          BUILD_TYPE := debug
coverage:       BUILD_TYPE := coverage
release debug coverage: all
.PHONY: release debug coverage

### Export search path for source files
#
# Override this to change the source root directory
export VPATH := $(CURDIR)/

### Run the clean rule directly
#
clean:
	$(RM) -r build

### Additional build types and overrides
#
-include Overrides.mk

### Force execution of all rules
#
%::     force
.PHONY: force

### Prevent implicit rules from remaking the Makefiles
#
MAKEFILE       := $(firstword $(MAKEFILE_LIST))
$(MAKEFILE): ;
Overrides.mk: ;

### Delegate all unspecified goals to a sub-make
#
%:: force
	$(eval export BUILD_TYPE)
	$(eval BUILD_DIR=build/$(BUILD_TYPE))
	$(info Building to $(BUILD_DIR))
	mkdir -p $(BUILD_DIR)
	# Execute this Makefile from a build-specific subdirectory
	$(MAKE) -C $(BUILD_DIR) -I $(CURDIR) -I $(VPATH) -f $(CURDIR)/$(MAKEFILE) --no-print-directory $@

else
###
## Sub-level Make
###

### Build-specific compile flags
#
CFLAGS_release  := -g -O1
CXXFLAGS_release:= -g -O1
LDFLAGS_release := -g
CFLAGS_debug    := -g
CXXFLAGS_debug  := -g
LDFLAGS_debug   := -g
CFLAGS_coverage := --coverage
CXXFLAGS_coverage:= --coverage
LDFLAGS_coverage:= --coverage
ifeq ($(BUILD_TYPE),coverage)
export CCACHE_DISABLE := "true"
endif

### Standard file extensions
AR_EXT  := .a
BIN_EXT :=
C_EXT   := .c
CC_EXT  := .cc
CPP_EXT := .cpp
DEP_EXT := .d
OBJ_EXT := .o
LIB_EXT := .so

### Non-standard tools (defaults)
#
PROTOC  := protoc

### Build and release configuration
#
-include Config.mk
CFLAGS  := $(CFLAGS_$(BUILD_TYPE)) $(CFLAGS)
CXXFLAGS:= $(CXXFLAGS_$(BUILD_TYPE)) $(CXXFLAGS)
LDFLAGS := $(LDFLAGS_$(BUILD_TYPE)) $(LDFLAGS)
LDLIBS  := $(LDLIBS) $(LDLIBS_$(BUILD_TYPE))

### Useful procedures
#

# Indentation helpers
#   - an empty variable
#   - a variable containing a space
#   - an indentation variable for pretty printing
#   - a procedure to announce a build step with relative paths
empty :=
space := $(empty) $(empty)
ifeq ($(origin indent),undefined)
indent := $(space)$(space)
endif
define announce
$(info $(indent)$(tab)$(subst $(VPATH),,$1))
endef

# A procedure for declaring dependencies
#
# Usage: $(call depends,foo,foo.o)
# Usage: $(call depends,bar bar.a,bar.o foo.o)
#
define depends
$(addprefix $(SUBDIR),$1): $(addprefix $(SUBDIR),$2)
endef

# Procedures for backing up variables during makefile inclusions
#
empty :=
define save
SAVED_$1 := $($1)
$1 :=
endef
define restore
$1 := $(SAVED_$1)
endef
define restore_prefixed
$1 := $(SAVED_$1) $(addprefix $(SUBDIR),$($1))
endef
define restore_as_var
$1_$(SUBDIR) := $($1)
$1 := $(SAVED_$1)
endef

# A procedure for including Makefiles
#
# Usage: $(call include_rules,path/to/Rules.mk)
#
#   Define the variable $D to be the directory component of the
#   absolute or relative path to the Makefile, saving any previous
#   value for $D before inclusion, and restoring this value after.
#
define include_rules
# save variables
$(eval $(call save,SUBDIR))
$(eval $(call save,SRCS))
$(eval $(call save,TGTS))
$(eval $(call save,CFLAGS))
$(eval $(call save,CXXFLAGS))
$(eval $(call save,LDFLAGS))
$(eval $(call save,LDLIBS))
# include subdirectory rules
$(eval SUBDIR := $(dir $1))
$(eval $(call announce,MK  $1))
$(eval include $1)
# process and restore variable
$(eval $(call restore_prefixed,SRCS))
$(eval $(call restore_prefixed,TGTS))
$(eval $(call restore_as_var,CFLAGS))
$(eval $(call restore_as_var,CXXFLAGS))
$(eval $(call restore_as_var,LDFLAGS))
$(eval $(call restore_as_var,LDLIBS))
$(eval $(call restore,SUBDIR))
endef

### Project build rules
#

# Find all Rules.mk files under the source directory
RULES := $(shell cd $(VPATH) && find * -depth -name Rules.mk 2>/dev/null | tac)

# Include the subdirectory rules
$(foreach path,$(RULES),$(eval $(call include_rules,$(path))))

# Force build of targets, and do nothing if there are none
.PHONY:  force
targets: force $(TGTS)

# Make all target directories
TGT_DIRS := $(foreach tgt,$(TGTS),$(dir $(tgt)))
$(TGTS): | $(addsuffix .exists,$(TGT_DIRS))
%/.exists:
	mkdir -p $(dir $@)
	touch $@
.exists:

### Dependency generation
#
# Support for C object files
SRCS_C    := $(filter %$(C_EXT),$(SRCS))
DEPS_C_O  := $(SRCS_C:$(C_EXT)=$(OBJ_EXT))
DEPS_C_D  := $(SRCS_C:$(C_EXT)=$(DEP_EXT))
DEPS_C_F  := $(sort $(foreach src,$(SRCS_C),$(dir $(src)).cflags))
# Support for C++ object files (.cc extension)
SRCS_CC   := $(filter %$(CC_EXT),$(SRCS))
DEPS_CC_O := $(SRCS_CC:$(CC_EXT)=$(OBJ_EXT))
DEPS_CC_D := $(SRCS_CC:$(CC_EXT)=$(DEP_EXT))
# Support for C++ object files (.cpp extension)
SRCS_CPP  := $(filter %$(CPP_EXT),$(SRCS))
DEPS_CPP_O := $(SRCS_CPP:$(CPP_EXT)=$(OBJ_EXT))
DEPS_CPP_D := $(SRCS_CPP:$(CPP_EXT)=$(DEP_EXT))
DEPS_CC_F := $(sort $(foreach src,$(SRCS_CC) $(SRCS_CPP),$(dir $(src)).cxxflags))
-include $(DEPS_C_D) $(DEPS_CC_D) $(DEPS_CPP_D)

### Preprocessing pattern rules
#
# C/C++ compile flag detection
#   Have the compiler emit a verbose assembly header for an empty file.
#   This header includes all supplied and implied flags, along with a
#   compiler checksum.  So long as a .o file depends on the .x, this
#   rule will be executed with the current flags, including any target-
#   specific modifications.  If the flags have changed the .x file is
#   updated, forcing the .o file to be rebuilt.
$(DEPS_C_F): force
	mkdir -p $(dir $@)
	new_flags=`$(CC) $(CFLAGS) $(CFLAGS_$(dir $@)) -S -fverbose-asm -o - -x c /dev/null 2>/dev/null`; \
	old_flags=`cat '$@' 2>/dev/null`; \
	    if [ x"$$new_flags" != x"$$old_flags" ]; then \
	        echo -n "$$new_flags" >'$@' || exit 1; \
	    fi
$(DEPS_CC_F): force
	mkdir -p $(dir $@)
	new_flags=`$(CXX) $(CXXFLAGS) $(CXXFLAGS_$(dir $@)) -S -fverbose-asm -o - -x c++ /dev/null 2>/dev/null`; \
	old_flags=`cat '$@' 2>/dev/null`; \
	    if [ x"$$new_flags" != x"$$old_flags" ]; then \
	        echo -n "$$new_flags" >'$@' || exit 1; \
	    fi
$(DEPS_CPP_F): force
	mkdir -p $(dir $@)
	new_flags=`$(CXX) $(CXXFLAGS) $(CXXFLAGS_$(dir $@)) -S -fverbose-asm -o - -x c++ /dev/null 2>/dev/null`; \
	old_flags=`cat '$@' 2>/dev/null`; \
	    if [ x"$$new_flags" != x"$$old_flags" ]; then \
	        echo -n "$$new_flags" >'$@' || exit 1; \
	    fi

# Protocol buffer C++ source generation
# #   This implicit rule will combine with the .o rule to generate %.pb.o
# #   from %.proto in two steps.
%.pb.cc %.pb.h: %.proto
	$(call announce,PB  $<)
	$(PROTOC) -I$(dir $<) --cpp_out=$(dir $@) $<
	sed -i '1i #pragma GCC diagnostic ignored "-Wshadow"' $(@:.cc=.h) $(@:.h=.cc)
	sed -i '$a #pragma GCC diagnostic warning "-Wshadow"' $(@:.cc=.h) $(@:.h=.cc)

### Compilation pattern rules
#
$(DEPS_C_O): $(DEPS_C_F)
$(DEPS_C_O): %$(OBJ_EXT): %$(C_EXT)
	$(call announce,C   $<)
	$(CC) $(CFLAGS) $(CFLAGS_$(dir $@)) -c $< -MMD -MP -MT $@ -MF $(@:$(OBJ_EXT)=$(DEP_EXT)) -o $@
$(DEPS_CC_O): $(DEPS_CC_F)
$(DEPS_CC_O): %$(OBJ_EXT): %$(CC_EXT)
	$(call announce,C++ $<)
	$(CXX) $(CXXFLAGS) $(CXXFLAGS_$(dir $@)) -c $< -MMD -MP -MT $@ -MF $(@:$(OBJ_EXT)=$(DEP_EXT)) -o $@
$(DEPS_CPP_O): $(DEPS_CPP_F)
$(DEPS_CPP_O): %$(OBJ_EXT): %$(CPP_EXT)
	$(call announce,C++ $<)
	$(CXX) $(CXXFLAGS) $(CXXFLAGS_$(dir $@)) -c $< -MMD -MP -MT $@ -MF $(@:$(OBJ_EXT)=$(DEP_EXT)) -o $@
%$(OBJ_EXT): %$(C_EXT)
	$(error Need $@ but $< is not listed as a source file)
%$(OBJ_EXT): %$(CC_EXT)
	$(error Need $@ but $< is not listed as a source file)
%$(OBJ_EXT): %$(CPP_EXT)
	$(error Need $@ but $< is not listed as a source file)

### Linking pattern rules
#
%$(BIN_EXT): %$(OBJ_EXT)
	$(call announce,BIN $@)
	$(CXX) -static $(LDFLAGS) $(LDFLAGS_$(dir $@)) \
                -o $@ $(filter %$(OBJ_EXT),$^) $(filter %$(AR_EXT),$^) $(LDLIBS_$(dir $@)) $(LDLIBS)
%$(LIB_EXT):
	$(call announce,LIB $@)
	$(CC) -shared $(LDFLAGS) $(LDFLAGS_$(dir $@)) -o $@ $^ $(LDLIBS_$(dir $@)) $(LDLIBS)
%$(AR_EXT):
	$(call announce,AR  $@)
	$(AR) rcs $@ $?

endif