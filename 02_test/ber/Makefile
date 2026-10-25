ROOT := $(abspath ../..)
CASE ?= manual
N ?= 1
TX ?= 1
CH ?= 1
FF ?= 0
DF ?= 0
SL ?= 1
D ?= 1
TRAIN ?= 8
CW ?= 64
SKIP ?= 1
VERILATOR ?= verilator
JOBS ?= 2
BUILD := $(abspath build/$(CASE))
TOP := ber_block_test
DEFINES := -DTEST_N=$(N) -DTEST_TX=$(TX) -DTEST_CH=$(CH) -DTEST_FF=$(FF) -DTEST_DF=$(DF) -DTEST_SL=$(SL) -DTEST_D=$(D) -DTEST_TRAIN=$(TRAIN) -DTEST_CW=$(CW) -DTEST_SKIP=$(SKIP)
CASES := serial block2 block3 block4 split5 exact6 wide8 zero_delay no_training deep_pipe

.PHONY: test run build $(CASES)
test: $(CASES)

serial: ARGS = N=1 TRAIN=3000
block2: ARGS = N=2 TRAIN=5
block3: ARGS = N=3 TRAIN=4 TX=0 CH=0 SL=0
block4: ARGS = N=4 TRAIN=7 CH=2 FF=1 SL=0
split5: ARGS = N=4 TRAIN=0 D=5
exact6: ARGS = N=3 TRAIN=5 D=6
wide8: ARGS = N=8 TRAIN=17 CW=8
zero_delay: ARGS = N=4 TRAIN=0 D=0 TX=0 CH=0 SL=0 CW=4
no_training: ARGS = N=4 TRAIN=4096 SKIP=0
deep_pipe: ARGS = N=2 TX=2 CH=2 FF=1 DF=1 SL=1 D=3 TRAIN=5

$(CASES):
	@$(MAKE) --no-print-directory run CASE=$@ $(ARGS)

run: build
	@$(BUILD)/V$(TOP)

build:
	@mkdir -p $(BUILD)
	@$(VERILATOR) --cc --exe --sv --assert --top-module $(TOP) --Mdir $(BUILD) $(DEFINES) -CFLAGS '-std=c++17 -O2 $(DEFINES)' $(ROOT)/00_src/Top.sv $(abspath ber_block_test.sv) $(abspath test_block_ber.cpp) > $(BUILD)/verilator.log 2>&1 || { cat $(BUILD)/verilator.log; exit 1; }
	@$(MAKE) --no-print-directory -C $(BUILD) -f V$(TOP).mk -j$(JOBS) V$(TOP) > $(BUILD)/build.log 2>&1 || { cat $(BUILD)/build.log; exit 1; }
