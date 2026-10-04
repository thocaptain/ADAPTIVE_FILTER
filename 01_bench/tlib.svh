`ifndef TLIB_SVH
`define TLIB_SVH

// TASK: Clock Generator (100 MHz)
task automatic tsk_clock_gen(ref logic i_clk);
  begin
    i_clk = 1'b1;
    forever #5 i_clk = !i_clk;
  end
endtask

// TASK: Reset is low active for a period of "RESETPERIOD"
task automatic tsk_reset(ref logic i_rst_n, input int RESETPERIOD);
  begin
    i_rst_n = 1'b0;
    #RESETPERIOD i_rst_n = 1'b1;
  end
endtask

// TASK: Timeout
task automatic tsk_timeout(input int FINISH);
  begin
    #FINISH $display("\nTimeout...\n");
            $finish;
  end
endtask

`endif
