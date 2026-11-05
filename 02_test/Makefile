SHELL := /bin/bash
.DEFAULT_GOAL := run
MODE ?= DFE_ONLY
TEST ?= FIXED
N ?= 128
DUMPWAVE ?= 0
OPENWAVE ?= 0
GTKWAVE ?= gtkwave
WRITE_WAVE := $(if $(filter 1,$(DUMPWAVE) $(OPENWAVE)),1,0)
VERILATOR ?= verilator
JOBS ?= 2
ROOT := $(abspath ..)
TOOL_TAG := $(shell $(VERILATOR) --version | cksum | cut -d ' ' -f1)
BUILD := $(abspath build/verilator_$(TOOL_TAG)/$(MODE))
RUN_PREFIX := $(abspath eq_independent/$(MODE)_$(TEST))
CLEAN_OUTPUTS := $(foreach dir,. eq_independent,$(foreach mode,FFE_ONLY DFE_ONLY FFE_DFE,$(foreach test,FIXED LMS,$(addprefix $(abspath $(dir))/$(mode)_$(test),.log .vcd _viewer.log))))
DRIVER := $(abspath table_test.cpp)
REGRESSION_LOG := $(abspath regression.log)

ifeq ($(MODE),FFE_ONLY)
TOP := rx_ffe
DEFINE := -DTEST_FFE
SOURCES := $(ROOT)/00_src/rx/rx_ffe.sv
else ifeq ($(MODE),DFE_ONLY)
TOP := rx_dfe
DEFINE := -DTEST_DFE
SOURCES := $(ROOT)/00_src/rx/rx_dfe.sv
else ifeq ($(MODE),FFE_DFE)
TOP := chain_tb
DEFINE := -DTEST_CHAIN
SOURCES := $(abspath eq_chain/chain_tb.sv) $(ROOT)/00_src/top.sv $(ROOT)/00_src/tx/tx_top.sv $(ROOT)/00_src/channel/channel_top.sv $(ROOT)/00_src/rx/rx_top.sv $(ROOT)/00_src/rx/rx_ffe.sv $(ROOT)/00_src/rx/rx_dfe.sv $(ROOT)/00_src/rx/rx_monitor.sv
endif

.PHONY: run build help clean regression
clean:
	@rm -f -- $(foreach file,$(CLEAN_OUTPUTS),"$(file)")
	@if [ -d "$(abspath logs)" ]; then find "$(abspath logs)" -type f \( -name 'run.log' -o -name 'wave.vcd' -o -name 'viewer.log' \) -delete; fi
	@rm -rf -- "$(abspath build)" "$(abspath eq_independent/build)"
	@echo 'Removed build directories, run logs and waveforms.'

regression:
	@passed=0; failed=0; total=0; \
	: > "$(REGRESSION_LOG)"; \
	run_case() { \
	 label="$$1"; shift; total=$$((total + 1)); \
	 printf 'Running %s ... ' "$$label"; \
	 if "$$@" >> "$(REGRESSION_LOG)" 2>&1; then \
	  passed=$$((passed + 1)); printf 'PASS\n'; \
	 else \
	  failed=$$((failed + 1)); printf 'FAIL\n'; \
	 fi; \
	}; \
	for mode in FFE_ONLY DFE_ONLY FFE_DFE; do \
	 for test in FIXED LMS; do \
	  run_case "$$mode/$$test" $(MAKE) --no-print-directory run MODE=$$mode TEST=$$test N=$(N); \
	 done; \
	done; \
	printf '\nRegression results: %s cases, %s passed, %s failed\n' "$$total" "$$passed" "$$failed"; \
	printf '\nRegression results: %s cases, %s passed, %s failed\n' "$$total" "$$passed" "$$failed" >> "$(REGRESSION_LOG)"; \
	test "$$failed" -eq 0

run: build
	@set -o pipefail; $(BUILD)/V$(TOP) $(TEST) $(N) $(if $(filter 1,$(WRITE_WAVE)),"$(RUN_PREFIX).vcd") 2>&1 | tee "$(RUN_PREFIX).log"
	@echo "Log: $(RUN_PREFIX).log"
	@if [ "$(WRITE_WAVE)" = 1 ]; then echo "Wave: $(RUN_PREFIX).vcd"; fi
	@if [ "$(OPENWAVE)" = 1 ]; then \
	 nohup "$(GTKWAVE)" "$(RUN_PREFIX).vcd" > "$(RUN_PREFIX)_viewer.log" 2>&1 < /dev/null & viewer_pid=$$!; \
	 sleep 0.3; \
	 if kill -0 $$viewer_pid 2>/dev/null; then echo "GTKWave opened (PID $$viewer_pid)."; \
	 else cat "$(RUN_PREFIX)_viewer.log"; echo 'Unable to open GTKWave; VCD has been saved.'; exit 1; fi; \
	 fi

build:
	@test -n "$(TOP)" || { echo "MODE: FFE_ONLY | DFE_ONLY | FFE_DFE"; exit 2; }
	@case "$(TEST)" in FIXED|LMS) ;; *) echo "TEST: FIXED | LMS"; exit 2;; esac
	@case "$(DUMPWAVE)" in 0|1) ;; *) echo "DUMPWAVE: 0 | 1"; exit 2;; esac
	@case "$(OPENWAVE)" in 0|1) ;; *) echo "OPENWAVE: 0 | 1"; exit 2;; esac
	@if [ "$(OPENWAVE)" = 1 ]; then command -v "$(GTKWAVE)" >/dev/null || { echo 'GTKWave not found. Install gtkwave or set GTKWAVE=/path/to/gtkwave.'; exit 2; }; fi
	@mkdir -p $(BUILD)
	@$(VERILATOR) --cc --exe --trace --sv -Wno-fatal --top-module $(TOP) --Mdir $(BUILD) -CFLAGS '-std=c++17 -O2 $(DEFINE)' $(SOURCES) $(DRIVER) > $(BUILD)/build.log 2>&1 || { cat $(BUILD)/build.log; exit 1; }
	@$(MAKE) --no-print-directory -C $(BUILD) -f V$(TOP).mk -j$(JOBS) V$(TOP) >> $(BUILD)/build.log 2>&1 || { cat $(BUILD)/build.log; exit 1; }

help:
	@echo 'make -C 02_test MODE=FFE_ONLY TEST=FIXED'
	@echo 'MODE=FFE_ONLY | DFE_ONLY | FFE_DFE'
	@echo 'TEST=FIXED | LMS   N=128   DUMPWAVE=0|1   OPENWAVE=0|1'
	@echo 'make -C 02_test regression: run all 16 FFE/DFE and BER regression cases.'
	@echo 'Regression output is saved to 02_test/regression.log.'
	@echo 'OPENWAVE=1: automatically dump VCD and open GTKWave after a passing run.'
	@echo 'make clean: remove build directories, run logs and VCD files.'
	@echo 'Output: 02_test/eq_independent/<MODE>_<TEST>.log and optional <MODE>_<TEST>.vcd.'
