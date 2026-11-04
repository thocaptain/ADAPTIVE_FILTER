.DEFAULT_GOAL := run
# The table runner is shared with 02_test; command-line options propagate through make.
.PHONY: run help clean
clean:
	@$(MAKE) --no-print-directory -C .. clean

run:
	@$(MAKE) --no-print-directory -C .. run
help:
	@$(MAKE) --no-print-directory -C .. help

ROOT := $(abspath ../..)
VERILATOR ?= verilator
JOBS ?= 2
TOOL_TAG := $(shell $(VERILATOR) --version | cksum | cut -d ' ' -f1)
BUILD := build/cpp_reference_$(TOOL_TAG)
CASES ?= fixed_basic fixed_saturation adapt_small adapt_large bypass fixed_random adapt_random adapt_rounding adapt_acc_saturation

.PHONY: all ffe dfe build_ffe build_dfe reference_checks
all:
	@status=0; $(MAKE) ffe || status=1; $(MAKE) dfe || status=1; exit $$status

reference_checks:
	@mkdir -p build
	$(CXX) -std=c++17 -Wall -Wextra -O2 reference_checks.cpp -o build/reference_checks
	./build/reference_checks

build_ffe: reference_checks
	@mkdir -p $(BUILD)/ffe
	$(VERILATOR) --cc --exe --sv -Wno-fatal --top-module rx_ffe --Mdir $(abspath $(BUILD)/ffe) -CFLAGS '-std=c++17 -DTEST_FFE' $(ROOT)/00_src/rx/rx_ffe.sv $(abspath driver.cpp)
	$(MAKE) -C $(BUILD)/ffe -f Vrx_ffe.mk -j$(JOBS) Vrx_ffe

build_dfe: reference_checks
	@mkdir -p $(BUILD)/dfe
	$(VERILATOR) --cc --exe --sv -Wno-fatal --top-module rx_dfe --Mdir $(abspath $(BUILD)/dfe) -CFLAGS '-std=c++17' $(ROOT)/00_src/rx/rx_dfe.sv $(abspath driver.cpp)
	$(MAKE) -C $(BUILD)/dfe -f Vrx_dfe.mk -j$(JOBS) Vrx_dfe

ffe: build_ffe
	@mkdir -p results; status=0; for c in $(CASES); do \
	 echo "=== FFE $$c (C++ reference) ==="; \
	 ./$(BUILD)/ffe/Vrx_ffe --case $$c results/ffe_$${c} || status=1; \
	 done; exit $$status

dfe: build_dfe
	@mkdir -p results; status=0; for c in $(CASES); do \
	 echo "=== DFE $$c (C++ reference) ==="; \
	 ./$(BUILD)/dfe/Vrx_dfe --case $$c results/dfe_$${c} || status=1; \
	 done; exit $$status
