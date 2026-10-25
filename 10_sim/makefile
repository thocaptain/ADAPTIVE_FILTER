SIM_DIR      := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
MAKEFILE     := $(SIM_DIR)/makefile
PROJECT_DIR  := $(abspath $(SIM_DIR)/..)

MODULE       ?= tx
SEED         ?= 1
JOBS         ?= 2
VERILATOR    ?= verilator
GTKWAVE      ?= gtkwave
TOP          := tb_top

ifeq ($(filter $(MODULE),tx rx channel),)
$(error MODULE must be tx, rx or channel)
endif

FLIST        := $(SIM_DIR)/$(MODULE)/flist
CPP          := $(PROJECT_DIR)/01_bench/$(MODULE)/tp_top.cpp
RTL_TOP      := $(PROJECT_DIR)/00_src/$(MODULE)/$(MODULE)_top.sv
TB           := $(PROJECT_DIR)/01_bench/$(MODULE)/tb_top.sv
OUT_DIR      := $(SIM_DIR)/build/$(MODULE)
OBJ_DIR      := $(OUT_DIR)/obj_dir
EXE          := $(OBJ_DIR)/V$(TOP)
WAVE         := $(OUT_DIR)/$(MODULE)_clock_reset.vcd

FLAGS        := --cc --exe --trace --sv --assert --top-module $(TOP)
FLAGS        += -O3 --compiler gcc -CFLAGS "-std=gnu++17"
FLAGS        += -x-initial unique -x-assign unique
LFLAGS       := --lint-only --sv --top-module $(TOP)
RFLAGS       := +verilator+seed+$(SEED)

.DEFAULT_GOAL := help
.PHONY: help check list lint sim run wave clean tx rx channel

help:
	@printf '%s\n' \
	  'make lint MODULE=tx|rx|channel' \
	  'make sim  MODULE=tx|rx|channel  # Build only' \
	  'make run  MODULE=tx|rx|channel  # Build and run' \
	  'make wave MODULE=tx|rx|channel' \
	  'make clean MODULE=tx|rx|channel' \
	  'make tx | make rx | make channel  # Build and run one module'

check:
	@test -f "$(FLIST)" || { printf 'Missing file list: %s\n' "$(FLIST)" >&2; exit 1; }
	@test -f "$(TB)" || { printf 'Missing testbench: %s\n' "$(TB)" >&2; exit 1; }
	@test -f "$(CPP)" || { printf 'Missing C++ driver: %s\n' "$(CPP)" >&2; exit 1; }
	@test -f "$(RTL_TOP)" || { printf 'Missing RTL: %s\nAdd the module and its dependencies to %s\n' "$(RTL_TOP)" "$(FLIST)" >&2; exit 1; }

list:
	@cat "$(FLIST)"

lint: check
	@cd "$(SIM_DIR)" && $(VERILATOR) $(LFLAGS) -f "$(FLIST)" "$(SIM_DIR)/conf.vlt"

sim: check
	@mkdir -p "$(OUT_DIR)"
	@cd "$(SIM_DIR)" && $(VERILATOR) $(FLAGS) --Mdir "$(OBJ_DIR)" -f "$(FLIST)" "$(SIM_DIR)/conf.vlt" "$(CPP)"
	@$(MAKE) --no-print-directory -C "$(OBJ_DIR)" -f "V$(TOP).mk" -j$(JOBS) "V$(TOP)"

run: sim
	@cd "$(OUT_DIR)" && "$(EXE)" $(RFLAGS)

wave:
	@test -f "$(WAVE)" || { printf 'Missing waveform: %s\nRun make run MODULE=%s first.\n' "$(WAVE)" "$(MODULE)" >&2; exit 1; }
	@$(GTKWAVE) "$(WAVE)"

clean:
	@case "$(OUT_DIR)" in \
	  "$(SIM_DIR)/build/tx"|"$(SIM_DIR)/build/rx"|"$(SIM_DIR)/build/channel") rm -rf -- "$(OUT_DIR)" ;; \
	  *) printf 'Refusing to clean outside the module build directory.\n' >&2; exit 1 ;; \
	esac

tx rx channel:
	@$(MAKE) --no-print-directory -f "$(MAKEFILE)" run MODULE=$@
