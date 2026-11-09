# Dedicated bench for the Q4.12 channel_top interface, independent of tb_top.sv.
THIS_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
PROJECT := $(abspath $(THIS_DIR)/../..)
BUILD := $(PROJECT)/10_sim/build/channel_awgn
RTL := $(PROJECT)/00_src/channel/channel_top.sv
BENCH := $(PROJECT)/01_bench/channel/isi_awgn.cpp
EXE := $(BUILD)/obj_dir/Vchannel_top
VERILATOR ?= verilator
GTKWAVE ?= gtkwave
JOBS ?= 2
.DEFAULT_GOAL := run
.PHONY: build run psd wave snr-wave lint
lint:
	$(VERILATOR) --lint-only --sv --Wall --top-module channel_top $(RTL)
build:
	mkdir -p $(BUILD)
	$(VERILATOR) --cc --exe --build --trace --assert --sv --Wall -j $(JOBS) --top-module channel_top --Mdir $(BUILD)/obj_dir -CFLAGS "-std=c++17 -O2" $(RTL) $(BENCH)
run: build
	cd $(BUILD) && ./obj_dir/Vchannel_top > run.log 2>&1; result=$$?; cat run.log; exit $$result
	cd $(BUILD) && python3 $(PROJECT)/01_bench/channel/check_awgn_model.py isi0_awgn_samples.csv > model_check.log 2>&1; result=$$?; cat model_check.log; exit $$result
	cd $(BUILD) && python3 $(PROJECT)/01_bench/channel/check_snr_capture.py > snr_check.log 2>&1; result=$$?; cat snr_check.log; exit $$result
wave:
	$(GTKWAVE) $(BUILD)/isi0_awgn.vcd $(THIS_DIR)/isi_awgn.gtkw
# The same RTL capture feeds the arithmetic checks and the PSD acceptance test.
psd: run
snr-wave:
	$(GTKWAVE) $(BUILD)/snr_monitor.vcd $(THIS_DIR)/snr_monitor.gtkw
