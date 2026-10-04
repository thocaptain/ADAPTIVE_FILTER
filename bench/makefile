FILELIST_ARGS := $(shell sed -n '/^[+-]/p' filelist)
FILES := $(shell sed -n '/^[^+-]/p' filelist)

VERILATOR = verilator

### LINT FLAGS
LINT_FLAGS = -Wall --lint-only -sv

### VERILATE FLAGS
VERILATOR_FLAGS += -sv -cc
VERILATOR_FLAGS += -x-initial unique
VERILATOR_FLAGS += -x-assign unique
VERILATOR_FLAGS += -O3
VERILATOR_FLAGS += -Wall
VERILATOR_FLAGS += -Wno-EOFNEWLINE
VERILATOR_FLAGS += -Wno-PINCONNECTEMPTY
VERILATOR_FLAGS += --assert
VERILATOR_FLAGS += --trace-fst

# Design top module (Verilator generates Vtop)
TOP_MODULE = eq_top
VERILATOR_INPUT = $(FILELIST_ARGS) $(FILES) --top-module $(TOP_MODULE) --prefix Vtop

### TEST SELECTION
# make test                -> bin/tb_eq_top.cpp
# make test TEST=<name>    -> bin/tb_<name>.cpp
TEST ?= eq_top
TESTS = eq_top
OBJ_DIR = obj_dir_$(TEST)

.PHONY: all
all:
	@$(MAKE) --no-print-directory test

.PHONY: help
help:
	@echo -e "make [option] [TEST=name]"
	@echo -e "\tlint    lint the design"
	@echo -e "\tbuild   verilate and build"
	@echo -e "\ttest    run simulation"
	@echo -e "\tregress build and run all tests: $(TESTS)"
	@echo -e "\twave    open waveforms"
	@echo -e "\tclean   clean the working folder"

.PHONY: lint
lint:
	@$(VERILATOR) $(LINT_FLAGS) $(FILELIST_ARGS) $(FILES) --top-module $(TOP_MODULE)

.PHONY: build
build: ./$(OBJ_DIR)/Vtop
./$(OBJ_DIR)/Vtop: $(FILES) ./bin/tb_$(TEST).cpp ./bin/tb_common.h
	@$(VERILATOR) $(VERILATOR_FLAGS) $(VERILATOR_INPUT) --Mdir $(OBJ_DIR) --exe ./bin/tb_$(TEST).cpp > build_$(TEST).log
	@$(MAKE) -C $(OBJ_DIR) -f Vtop.mk -j2

.PHONY: test
test: ./$(OBJ_DIR)/Vtop
	@./$(OBJ_DIR)/Vtop $(ARGS)

.PHONY: regress
regress:
	@fail=0; for t in $(TESTS); do $(MAKE) --no-print-directory test TEST=$$t || fail=1; done; exit $$fail

.PHONY: wave
wave: wave.fst
	@gtkwave wave.fst

.PHONY: clean
clean:
	@rm -rf obj_dir obj_dir_*
	@rm -f wave.fs*
	@rm -f *.log
